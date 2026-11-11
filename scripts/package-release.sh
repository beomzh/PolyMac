#!/usr/bin/env bash
# 배포 파일 만들기: build/release/PolyMac-X.Y.Z.zip + .zip.sha256 + appcast.xml (docs/RELEASING.md 4-6, 4-7)
#
#   scripts/package-release.sh          → 태그 vX.Y.Z가 찍힌 깨끗한 main에서만 묶는다
#   scripts/package-release.sh --dry    → 확인 없이 묶어 본다 (올리지 말 것)
#
# 공증하지 않는다. 서명 인증서는 build-app.sh와 같은 순서로 고른다 (POLYMAC_SIGN_IDENTITY로 지정 가능).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

VERSION="$(tr -d '[:space:]' < VERSION)"
NAME="PolyMac-$VERSION"
OUT="$ROOT/build/release"

if [[ "${1:-}" != "--dry" ]]; then
    [[ "$VERSION" != *-* ]] || { echo "✗ VERSION이 사전 배포($VERSION)입니다 — 정식 번호로 올린 뒤 묶으세요"; exit 1; }
    [[ -z "$(git status --porcelain)" ]] || { echo "✗ 커밋하지 않은 변경이 있습니다"; exit 1; }
    [[ "$(git describe --exact-match --tags HEAD 2>/dev/null || true)" == "v$VERSION" ]] \
        || { echo "✗ HEAD에 태그 v${VERSION}이 없습니다 — git tag -a v$VERSION -m \"PolyMac $VERSION\""; exit 1; }
fi

scripts/build-app.sh

IDENTITY_LINE="$(codesign -dvv build/PolyMac.app 2>&1 | grep '^Authority=' | head -1 || true)"
if [[ -z "$IDENTITY_LINE" ]]; then
    echo "✗ ad-hoc 서명입니다 — 받는 사람의 권한이 업데이트마다 풀립니다. 고정 인증서를 만든 뒤 다시 실행하세요 (README '고정 인증서 만들기')"
    [[ "${1:-}" == "--dry" ]] || exit 1
fi
if [[ "$IDENTITY_LINE" == *"Apple Development"* ]]; then
    echo "✗ Apple Development 인증서로 서명됐습니다 — 서명에 이메일·실명이 드러나고 1년 뒤 만료됩니다. scripts/make-signing-cert.sh로 자체 서명 인증서를 만드세요"
    [[ "${1:-}" == "--dry" ]] || exit 1
fi

echo "▶ 묶기 — $NAME"
rm -rf "$OUT"
mkdir -p "$OUT"
# 확장 속성(com.apple.provenance 등)을 넣으면 zip 안에 ._ 파일이 생겨, unzip으로 풀었을 때 서명이 깨진다
ditto -c -k --norsrc --noextattr --noacl --keepParent build/PolyMac.app "$OUT/$NAME.zip"
CHECK="$(mktemp -d)"
trap 'rm -rf "$CHECK"' EXIT
if unzip -Z1 "$OUT/$NAME.zip" | grep -qE '(^|/)\._'; then echo "✗ zip에 ._ 파일이 들어갔습니다"; exit 1; fi
unzip -q "$OUT/$NAME.zip" -d "$CHECK" && codesign --verify --strict "$CHECK/PolyMac.app" \
    || { echo "✗ 압축을 푼 앱의 서명이 유효하지 않습니다"; exit 1; }
for notice in LICENSE.txt THIRD_PARTY_NOTICES.md; do   # 라이선스 고지가 배포본에 있어야 한다 (THIRD_PARTY_NOTICES.md)
    [[ -s "$CHECK/PolyMac.app/Contents/Resources/$notice" ]] || { echo "✗ 앱에 $notice 가 없습니다"; exit 1; }
done
(cd "$OUT" && shasum -a 256 "$NAME.zip" > "$NAME.zip.sha256" && shasum -a 256 -c "$NAME.zip.sha256")

# Sparkle appcast — 앱은 releases/latest/download/appcast.xml을 읽는다. 비밀 키는 키체인에만 있다 (generate_keys)
APPCAST=""
if [[ -s App/sparkle-public-key.txt ]]; then
    SPARKLE_BIN="$ROOT/Vendor/Sparkle/bin"
    [[ -x "$SPARKLE_BIN/sign_update" ]] || { echo "✗ Sparkle 도구(sign_update)가 없습니다 — scripts/fetch-sparkle.sh"; exit 1; }
    [[ "$("$SPARKLE_BIN/generate_keys" -p 2>/dev/null)" == "$(tr -d '[:space:]' < App/sparkle-public-key.txt)" ]] \
        || { echo "✗ 키체인의 Sparkle 키가 App/sparkle-public-key.txt와 다릅니다"; exit 1; }
    SIGNATURE="$("$SPARKLE_BIN/sign_update" "$OUT/$NAME.zip")"   # sparkle:edSignature="…" length="…"
    BUILD="$(/usr/libexec/PlistBuddy -c 'Print CFBundleVersion' build/PolyMac.app/Contents/Info.plist)"
    DOWNLOAD="https://github.com/beomzh/PolyMac/releases/download/v$VERSION"
    cat > "$OUT/appcast.xml" <<XML
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
  <channel>
    <title>PolyMac</title>
    <item>
      <title>PolyMac $VERSION</title>
      <pubDate>$(LC_ALL=C date -u '+%a, %d %b %Y %H:%M:%S +0000')</pubDate>
      <sparkle:version>$BUILD</sparkle:version>
      <sparkle:shortVersionString>$VERSION</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>14.0</sparkle:minimumSystemVersion>
      <sparkle:releaseNotesLink>https://github.com/beomzh/PolyMac/releases/tag/v$VERSION</sparkle:releaseNotesLink>
      <enclosure url="$DOWNLOAD/$NAME.zip" $SIGNATURE type="application/octet-stream"/>
    </item>
  </channel>
</rss>
XML
    xmllint --noout "$OUT/appcast.xml"
    APPCAST="\"$OUT/appcast.xml\""
    echo "  appcast: $OUT/appcast.xml"
else
    echo "  ⚠️  App/sparkle-public-key.txt가 없어 appcast를 만들지 않습니다 (이 빌드는 업데이트 확인을 쓰지 않음)"
fi

echo "✅ $OUT/$NAME.zip"
echo "   서명: ${IDENTITY_LINE#Authority=}"
echo "   sha256: $(cut -d' ' -f1 "$OUT/$NAME.zip.sha256")  (packaging/homebrew/polymac.rb)"
echo "   올리기: gh release create v$VERSION \"$OUT/$NAME.zip\" \"$OUT/$NAME.zip.sha256\" $APPCAST --title \"PolyMac $VERSION\" --notes-file <노트 파일>"
