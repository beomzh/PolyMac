#!/usr/bin/env bash
# PolyMac.app 빌드 (Xcode 없이 Command Line Tools만으로 가능)
#
#   scripts/build-app.sh            → build/PolyMac.app 생성
#   scripts/build-app.sh --install  → /Applications에 설치하고 실행
#
# 서명 인증서 선택 순서 (앞에 있는 것이 있으면 그것을 쓴다):
#   1. POLYMAC_SIGN_IDENTITY="이름"   직접 지정
#   2. "PolyMac Local"                 키체인 접근에서 만든 자체 서명 인증서
#   3. "Apple Development: …"          Xcode › Settings › Accounts에 Apple ID를 넣으면 생기는 무료 개발 인증서
#   4. ad-hoc                          빌드할 때마다 서명이 바뀌어 macOS 권한(손쉬운 사용 등)을 다시 줘야 한다
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

VERSION="$(tr -d '[:space:]' < VERSION)"
SHORT_VERSION="${VERSION%%-*}"
BUILD="$(git rev-list --count HEAD 2>/dev/null || echo 1)"
IDENTITIES="$(security find-identity -v -p codesigning 2>/dev/null || true)"
if [[ -n "${POLYMAC_SIGN_IDENTITY:-}" ]]; then
    IDENTITY="$POLYMAC_SIGN_IDENTITY"
elif grep -q '"PolyMac Local"' <<< "$IDENTITIES"; then
    IDENTITY="PolyMac Local"
else
    IDENTITY="$(grep -o '"Apple Development: [^"]*"' <<< "$IDENTITIES" | head -1 | tr -d '"' || true)"
fi
APP="$ROOT/build/PolyMac.app"

echo "▶ swift build (release) — PolyMac $VERSION ($BUILD)"
swift build -c release --product PolyMac
BIN_DIR="$(swift build -c release --show-bin-path)"

echo "▶ 앱 번들 조립"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/PolyMac" "$APP/Contents/MacOS/PolyMac"
cp App/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"   # 아이콘 다시 만들기: swift scripts/make-icon.swift
sed -e "s/__VERSION__/$VERSION/" -e "s/__SHORT_VERSION__/$SHORT_VERSION/" -e "s/__BUILD__/$BUILD/" \
    App/Info.plist > "$APP/Contents/Info.plist"
plutil -lint "$APP/Contents/Info.plist" > /dev/null

echo "▶ 서명"
if [[ -n "$IDENTITY" ]] && grep -qF "\"$IDENTITY\"" <<< "$IDENTITIES"; then
    codesign --force --options runtime --entitlements App/PolyMac.entitlements --sign "$IDENTITY" "$APP"
    echo "  서명: $IDENTITY"
else
    codesign --force --options runtime --entitlements App/PolyMac.entitlements --sign - "$APP"
    echo "  ⚠️  코드 서명 인증서가 없어 ad-hoc 서명했습니다."
    echo "     다시 빌드할 때마다 권한을 다시 줘야 합니다 — README의 '고정 인증서 만들기' 참고"
fi
codesign --verify --strict "$APP"

if [[ "${1:-}" == "--install" ]]; then
    echo "▶ /Applications 에 설치"
    pkill -x PolyMac 2>/dev/null && sleep 1 || true
    rm -rf /Applications/PolyMac.app
    cp -R "$APP" /Applications/PolyMac.app
    open /Applications/PolyMac.app
    echo "✅ 설치 완료 — 메뉴바의 ▦ 아이콘을 확인하세요"
else
    echo "✅ $APP"
fi
