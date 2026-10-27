#!/usr/bin/env bash
# 단위 테스트 실행. XCTest/Swift Testing 런타임은 Xcode에만 있어서, xcode-select가
# Command Line Tools를 가리키고 있어도 설치된 Xcode를 찾아 그걸로 실행한다 (sudo 불필요).
set -euo pipefail
cd "$(dirname "$0")/.."

if [[ -z "${DEVELOPER_DIR:-}" ]]; then
    SELECTED="$(xcode-select -p 2>/dev/null || true)"
    if [[ "$SELECTED" == *".app/Contents/Developer" ]]; then
        export DEVELOPER_DIR="$SELECTED"
    else
        XCODE="$(mdfind "kMDItemCFBundleIdentifier == 'com.apple.dt.Xcode'" 2>/dev/null | sort -r | head -1)"
        if [[ -z "$XCODE" ]]; then
            echo "❌ Xcode가 없습니다. swift test에는 Xcode가 필요합니다 (Command Line Tools만으로는 불가)." >&2
            exit 1
        fi
        export DEVELOPER_DIR="$XCODE/Contents/Developer"
    fi
fi
echo "▶ $(xcrun xcodebuild -version | head -1) — $DEVELOPER_DIR"
swift test "$@"
