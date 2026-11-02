#!/usr/bin/env bash
# Sparkle(자동 업데이트, MIT)을 Vendor/Sparkle에 받는다. build-app.sh·test.sh가 먼저 부른다.
#
# SwiftPM의 원격 바이너리 받기는 일부 환경에서 멈춰서(2026-11 확인), 같은 파일을 curl로 받고
# Sparkle 저장소 Package.swift(태그 2.10.0)에 적힌 체크섬과 맞을 때만 푼다. 이미 있으면 아무것도 하지 않는다.
set -euo pipefail

VERSION="2.10.0"
SHA256="17e28312b8e18ab7cdbbe09a6fb28cc55a5479ec6c371dbc07cdecd2a14fd959"
URL="https://github.com/sparkle-project/Sparkle/releases/download/$VERSION/Sparkle-for-Swift-Package-Manager.zip"

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DEST="$ROOT/Vendor/Sparkle"
[[ "$(cat "$DEST/.version" 2>/dev/null)" == "$VERSION" && -d "$DEST/Sparkle.xcframework" ]] && exit 0

echo "▶ Sparkle $VERSION 받기"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
curl -fsSL --retry 2 -o "$TMP/sparkle.zip" "$URL"
echo "$SHA256  $TMP/sparkle.zip" | shasum -a 256 -c --status \
    || { echo "✗ Sparkle 체크섬이 다릅니다 — 받은 파일을 쓰지 않습니다"; exit 1; }
rm -rf "$DEST"
mkdir -p "$DEST"
ditto -x -k "$TMP/sparkle.zip" "$DEST"
echo "$VERSION" > "$DEST/.version"
echo "  $DEST"
