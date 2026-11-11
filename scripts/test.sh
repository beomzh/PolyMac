#!/usr/bin/env bash
# 단위 테스트 실행. XCTest/Swift Testing 런타임은 Xcode에만 있어서, xcode-select가
# Command Line Tools를 가리키고 있어도 설치된 Xcode를 찾아 그걸로 실행한다 (sudo 불필요).
set -euo pipefail
cd "$(dirname "$0")/.."

# 영어·한국어 README가 함께 고쳐졌는지 (빠름, Xcode 불필요)
scripts/check-docs.sh

# 빌드 번호는 버전이 오를 때만 커진다 (Sparkle 업데이트 판단) — 0.2.13까지 쓴 커밋 수(43)보다 커야 한다
for pair in "0.2.18:2018" "1.0.0:1000000" "0.3.0-beta.1:2999" "0.2.14:2014"; do
    [[ "$(scripts/build-number.sh "${pair%%:*}")" == "${pair##*:}" ]] || { echo "✗ build-number.sh ${pair%%:*} ≠ ${pair##*:}" >&2; exit 1; }
done
(( $(scripts/build-number.sh) > 43 )) || { echo "✗ 빌드 번호가 지난 릴리스(43)보다 작습니다" >&2; exit 1; }
! scripts/build-number.sh 0.2 2>/dev/null || { echo "✗ build-number.sh가 잘못된 VERSION을 받아들였습니다" >&2; exit 1; }

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
scripts/fetch-sparkle.sh
echo "▶ $(xcrun xcodebuild -version | head -1) — $DEVELOPER_DIR"
swift test "$@"
