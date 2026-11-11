#!/usr/bin/env bash
# PolyMac.app 빌드 (Xcode 없이 Command Line Tools만으로도 가능)
#
# Xcode가 설치돼 있으면 Xcode 도구로 빌드해 단축어(Shortcuts) 앱 동작 목록(App Intents 메타데이터)까지 넣는다.
# Command Line Tools만 있으면 단축어 동작만 빠지고 나머지는 같다.
#
#   scripts/build-app.sh            → build/PolyMac.app 생성
#   scripts/build-app.sh --install  → /Applications에 설치하고 실행
#
# 서명 인증서 선택 순서 (앞에 있는 것이 있으면 그것을 쓴다):
#   1. POLYMAC_SIGN_IDENTITY="이름"   직접 지정
#   2. "PolyMac …"                     자체 서명 인증서 (scripts/make-signing-cert.sh, 또는 키체인 접근에서 만든 "PolyMac Local")
#   3. "Apple Development: …"          Xcode › Settings › Accounts에 Apple ID를 넣으면 생기는 무료 개발 인증서
#   4. ad-hoc                          빌드할 때마다 서명이 바뀌어 macOS 권한(손쉬운 사용 등)을 다시 줘야 한다
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

# 단축어 동작 메타데이터는 Xcode의 appintentsmetadataprocessor가 만든다 (xcode-select는 바꾸지 않는다)
if [[ -z "${DEVELOPER_DIR:-}" && "$(xcode-select -p 2>/dev/null)" != *.app/* && -d /Applications/Xcode.app ]]; then
    export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
fi
DEV_DIR="${DEVELOPER_DIR:-$(xcode-select -p)}"
INTENTS_TOOL="$DEV_DIR/Toolchains/XcodeDefault.xctoolchain/usr/bin/appintentsmetadataprocessor"

VERSION="$(tr -d '[:space:]' < VERSION)"
SHORT_VERSION="${VERSION%%-*}"
BUILD="$(scripts/build-number.sh "$VERSION")"   # 버전에서 계산 — scripts/build-number.sh
IDENTITIES="$(security find-identity -v -p codesigning 2>/dev/null || true)"
if [[ -n "${POLYMAC_SIGN_IDENTITY:-}" ]]; then
    IDENTITY="$POLYMAC_SIGN_IDENTITY"
elif grep -q '"PolyMac [^"]*"' <<< "$IDENTITIES"; then
    IDENTITY="$(grep -o '"PolyMac [^"]*"' <<< "$IDENTITIES" | head -1 | tr -d '"')"
else
    IDENTITY="$(grep -o '"Apple Development: [^"]*"' <<< "$IDENTITIES" | head -1 | tr -d '"' || true)"
fi
APP="$ROOT/build/PolyMac.app"

scripts/fetch-sparkle.sh
echo "▶ swift build (release) — PolyMac $VERSION ($BUILD)"
swift build -c release --product PolyMac
BIN_DIR="$(swift build -c release --show-bin-path)"

echo "▶ 앱 번들 조립"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$APP/Contents/Frameworks"
cp "$BIN_DIR/PolyMac" "$APP/Contents/MacOS/PolyMac"
cp App/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
cp -R App/en.lproj "$APP/Contents/Resources/"   # 영어 시스템에서 권한 안내·단축어 동작 문구   # 아이콘 다시 만들기: swift scripts/make-icon.swift
# 라이선스 — PolyMac(MIT)과 함께 넣는 Sparkle(MIT, bsdiff 등 BSD 포함)은 배포본에 저작권 고지를 함께 넣어야 한다
cp LICENSE "$APP/Contents/Resources/LICENSE.txt"
cp THIRD_PARTY_NOTICES.md "$APP/Contents/Resources/THIRD_PARTY_NOTICES.md"
# Sparkle 공개 키 (없으면 업데이트 확인을 쓰지 않는 빌드 — docs/RELEASING.md "업데이트 서명 키")
SPARKLE_KEY="$([[ -f App/sparkle-public-key.txt ]] && tr -d "[:space:]" < App/sparkle-public-key.txt || true)"
sed -e "s/__VERSION__/$VERSION/" -e "s/__SHORT_VERSION__/$SHORT_VERSION/" -e "s/__BUILD__/$BUILD/" -e "s|__SPARKLE_PUBLIC_KEY__|$SPARKLE_KEY|" \
    App/Info.plist > "$APP/Contents/Info.plist"
plutil -lint "$APP/Contents/Info.plist" > /dev/null

# Sparkle.framework — 샌드박스 앱이 아니라 XPC 서비스는 필요 없다 (Sparkle 문서)
SPARKLE="$(find "$BIN_DIR" -maxdepth 2 -name Sparkle.framework -type d | head -1)"
[[ -n "$SPARKLE" ]] || { echo "✗ $BIN_DIR 에 Sparkle.framework가 없습니다"; exit 1; }
ditto "$SPARKLE" "$APP/Contents/Frameworks/Sparkle.framework"
rm -rf "$APP/Contents/Frameworks/Sparkle.framework/XPCServices" "$APP/Contents/Frameworks/Sparkle.framework/Versions/B/XPCServices"
otool -l "$APP/Contents/MacOS/PolyMac" | grep -q "@executable_path/../Frameworks" \
    || install_name_tool -add_rpath @executable_path/../Frameworks "$APP/Contents/MacOS/PolyMac"
# Xcode 빌드가 넣는 툴체인 경로(/Applications/Xcode.app/…) rpath는 뺀다 — 받는 Mac에는 없는 경로이고, 앱 밖에서 라이브러리를 찾게 된다
otool -l "$APP/Contents/MacOS/PolyMac" | awk '/LC_RPATH/ {r=1} r && /path / {print $2; r=0}' | grep -E '^/Applications/|Xcode|CommandLineTools' \
    | while read -r path; do install_name_tool -delete_rpath "$path" "$APP/Contents/MacOS/PolyMac"; done

echo "▶ 단축어 동작 (App Intents)"
INTERMEDIATES="$(find "$ROOT/.build" -type d -path '*Release*' -name 'PolyMac-p.build' 2>/dev/null | head -1)"
if [[ -x "$INTENTS_TOOL" && -n "$INTERMEDIATES" ]]; then
    LISTS="$(mktemp -d)"
    find "$INTERMEDIATES" -name '*.swiftconstvalues' > "$LISTS/constvalues"
    "$INTENTS_TOOL" --output "$APP/Contents/Resources" \
        --toolchain-dir "$DEV_DIR/Toolchains/XcodeDefault.xctoolchain" --module-name PolyMacApp \
        --sdk-root "$(xcrun --sdk macosx --show-sdk-path)" \
        --xcode-version "$(xcodebuild -version | awk '/Build version/ {print $3}')" \
        --platform-family macOS --deployment-target 14.0 --target-triple "$(uname -m)-apple-macos14.0" \
        --source-file-list "$(find "$INTERMEDIATES" -name 'PolyMac.SwiftFileList' | head -1)" \
        --swift-const-vals-list "$LISTS/constvalues" --quiet-warnings 2>&1 | grep -v 'appintentsmetadataprocessor\[' || true
    rm -rf "$LISTS"
    [[ -f "$APP/Contents/Resources/Metadata.appintents/extract.actionsdata" ]] \
        || { echo "✗ 단축어 동작 메타데이터를 만들지 못했습니다"; exit 1; }
    echo "  동작 $(python3 -c 'import json,sys; print(len(json.load(open(sys.argv[1]))["actions"]))' "$APP/Contents/Resources/Metadata.appintents/extract.actionsdata")개"
else
    echo "  ⚠️  Xcode가 없어 건너뜁니다 — 단축어 앱 목록에 PolyMac 동작이 뜨지 않습니다 (polymac:// URL은 그대로 동작)"
fi

echo "▶ 서명"
if [[ -n "$IDENTITY" ]] && grep -qF "\"$IDENTITY\"" <<< "$IDENTITIES"; then
    SIGN="$IDENTITY"
    echo "  서명: $IDENTITY"
else
    SIGN="-"
    echo "  ⚠️  코드 서명 인증서가 없어 ad-hoc 서명했습니다."
    echo "     다시 빌드할 때마다 권한을 다시 줘야 합니다 — README의 '고정 인증서 만들기' 참고"
fi
# 안쪽부터: Sparkle의 실행 파일 → 프레임워크 → 앱 (앱과 같은 인증서여야 Hardened Runtime이 불러온다)
FRAMEWORK="$APP/Contents/Frameworks/Sparkle.framework"
codesign --force --options runtime --sign "$SIGN" "$FRAMEWORK/Versions/B/Autoupdate"
codesign --force --options runtime --sign "$SIGN" "$FRAMEWORK/Versions/B/Updater.app"
codesign --force --options runtime --sign "$SIGN" "$FRAMEWORK"
codesign --force --options runtime --entitlements App/PolyMac.entitlements --sign "$SIGN" "$APP"
codesign --verify --strict --deep "$APP"

if [[ "${1:-}" == "--install" ]]; then
    echo "▶ /Applications 에 설치"
    pkill -x PolyMac 2>/dev/null && sleep 1 || true
    rm -rf /Applications/PolyMac.app
    cp -R "$APP" /Applications/PolyMac.app
    open /Applications/PolyMac.app
    echo "✅ 설치 완료 — 메뉴바의 PolyMac 아이콘(큐브)을 확인하세요"
else
    echo "✅ $APP"
fi
