#!/usr/bin/env bash
# 배포 파일 만들기: build/release/PolyMac-X.Y.Z.zip + .zip.sha256 (docs/RELEASING.md 4-6, 4-7)
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
        || { echo "✗ HEAD에 태그 v$VERSION이 없습니다 — git tag -a v$VERSION -m \"PolyMac $VERSION\""; exit 1; }
fi

scripts/build-app.sh

IDENTITY_LINE="$(codesign -dvv build/PolyMac.app 2>&1 | grep '^Authority=' | head -1 || true)"
if [[ -z "$IDENTITY_LINE" ]]; then
    echo "✗ ad-hoc 서명입니다 — 받는 사람의 권한이 업데이트마다 풀립니다. 고정 인증서를 만든 뒤 다시 실행하세요 (README '고정 인증서 만들기')"
    [[ "${1:-}" == "--dry" ]] || exit 1
fi
if [[ "$IDENTITY_LINE" == *"Apple Development"* ]]; then
    echo "✗ Apple Development 인증서로 서명됐습니다 — 서명에 이메일·실명이 드러나고 1년 뒤 만료됩니다. scripts/make-signing-cert.sh로 PolyMac Local을 만드세요"
    [[ "${1:-}" == "--dry" ]] || exit 1
fi

echo "▶ 묶기 — $NAME"
rm -rf "$OUT"
mkdir -p "$OUT"
ditto -c -k --keepParent build/PolyMac.app "$OUT/$NAME.zip"
(cd "$OUT" && shasum -a 256 "$NAME.zip" > "$NAME.zip.sha256" && shasum -a 256 -c "$NAME.zip.sha256")

echo "✅ $OUT/$NAME.zip"
echo "   서명: ${IDENTITY_LINE#Authority=}"
echo "   올리기: gh release create v$VERSION \"$OUT/$NAME.zip\" \"$OUT/$NAME.zip.sha256\" --title \"PolyMac $VERSION\" --notes-file <노트 파일>"
