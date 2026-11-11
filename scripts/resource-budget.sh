#!/usr/bin/env bash
# 자원 예산 회귀 검사 (docs/ARCHITECTURE.md 3 "Resource budget"). CI가 PR마다 돌린다.
#   1. 앱 번들을 빌드해 번들 ID만 dev.polymac.budget으로 바꾼 사본을 띄운다
#      → 설정·데이터 폴더·키체인 항목이 따로라 설치된 PolyMac의 기록을 건드리지 않는다 (AppIdentity)
#   2. 띄운 뒤 WARMUP초 기다렸다가 메모리(phys_footprint)를 재고, WINDOW초 동안 CPU 사용률을 잰다
#   3. OCR을 일꾼에게 맡긴 쪽(부르는 프로세스) 메모리가 거의 늘지 않는지 잰다 (OCRBench --worker-memory)
# 한도를 넘으면 실패한다. 한도는 환경 변수로 바꿀 수 있다.
#
#   scripts/resource-budget.sh            빌드부터
#   scripts/resource-budget.sh --no-build build/PolyMac.app과 .build/debug를 그대로 쓴다
#
# 로컬에서 돌리면 측정하는 동안(약 1분 반) 메뉴바에 PolyMac 아이콘이 하나 더 생기고, 단축키는 설치된 앱과 겹칠 수 있다.
set -euo pipefail
cd "$(dirname "$0")/.."

MEMORY_LIMIT_MB="${MEMORY_LIMIT_MB:-40}"      # 처음 띄운 뒤 쉬는 동안 메모리
CPU_LIMIT_PERCENT="${CPU_LIMIT_PERCENT:-1.0}"  # 쉬는 동안 평균 CPU (클립보드 확인 0.5초 간격이 유일한 주기 작업)
OCR_GROWTH_LIMIT_MB="${OCR_GROWTH_LIMIT_MB:-25}" # OCR 3번 뒤 부르는 쪽 메모리 증가 (일꾼 없이 앱 안에서 하면 약 150 MB)
WARMUP="${WARMUP:-30}"
WINDOW="${WINDOW:-60}"
BUNDLE_ID="dev.polymac.budget"

if [[ -z "${DEVELOPER_DIR:-}" && "$(xcode-select -p 2>/dev/null)" != *.app/* && -d /Applications/Xcode.app ]]; then
    export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
fi

if [[ "${1:-}" != "--no-build" ]]; then
    scripts/build-app.sh > /dev/null 2> "$(mktemp)" || { echo "✗ scripts/build-app.sh 실패"; exit 1; }
    swift build --product OCRBench > /dev/null
    swift build --product PolyMac > /dev/null
fi

WORK="$(mktemp -d)"
APP="$WORK/PolyMac Budget.app"
PID=""
cleanup() {
    [[ -n "$PID" ]] && kill "$PID" 2>/dev/null || true
    defaults delete "$BUNDLE_ID" > /dev/null 2>&1 || true
    rm -rf "$HOME/Library/Application Support/PolyMac ($BUNDLE_ID)" "$WORK"
    security delete-generic-password -s "$BUNDLE_ID" > /dev/null 2>&1 || true
}
trap cleanup EXIT

# 1. 따로 쓰는 사본 — 번들 ID를 바꾸면 서명이 깨지므로 ad-hoc으로 다시 서명한다
ditto build/PolyMac.app "$APP"
/usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier $BUNDLE_ID" "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :SUEnableAutomaticChecks false" "$APP/Contents/Info.plist" 2>/dev/null || true
codesign --force --deep --sign - "$APP" 2> /dev/null
# 시작 안내 창은 처음 한 번만 뜨는 것이라 쉬는 상태 측정에서 뺀다
defaults write "$BUNDLE_ID" onboarding.done -bool true

"$APP/Contents/MacOS/PolyMac" > /dev/null 2>&1 &
PID=$!
disown "$PID"   # 끝낼 때 셸이 "Terminated"를 찍지 않게
echo "▶ PolyMac ($BUNDLE_ID) pid $PID — ${WARMUP}초 기다린 뒤 ${WINDOW}초 측정"
sleep "$WARMUP"
kill -0 "$PID" 2>/dev/null || { echo "✗ 앱이 실행 중에 끝났습니다"; exit 1; }

# ps의 누적 CPU 시간 "분:초.백분의일" → 초
cpu_seconds() { ps -o time= -p "$PID" | awk -F: '{ print $1 * 60 + $2 }'; }
footprint_mb() { footprint -p "$PID" 2>/dev/null | awk '/phys_footprint:/ { v=$2; u=$3; if (u=="KB") v/=1024; if (u=="GB") v*=1024; print v; exit }'; }

cpu_start="$(cpu_seconds)"
sleep "$WINDOW"
cpu_end="$(cpu_seconds)"
memory="$(footprint_mb)"
peak="$(footprint -p "$PID" 2>/dev/null | awk '/phys_footprint_peak:/ { v=$2; u=$3; if (u=="KB") v/=1024; if (u=="GB") v*=1024; print v; exit }')"
cpu="$(awk -v a="$cpu_start" -v b="$cpu_end" -v w="$WINDOW" 'BEGIN { printf "%.2f", (b - a) / w * 100 }')"

# 3. OCR 일꾼 — 부르는 쪽 메모리
ocr="$(.build/debug/OCRBench --worker-memory .build/debug/PolyMac Tests/OCRSamples/ko-long.png)"
growth="$(sed -n 's/^caller_growth_mb=//p' <<< "$ocr")"
chars="$(sed -n 's/^recognized_chars=//p' <<< "$ocr")"

fail=0
check() { # 이름 값 한도 단위
    if awk -v v="$2" -v l="$3" 'BEGIN { exit !(v < l) }'; then
        printf "✓ %-30s %8s %s (한도 %s)\n" "$1" "$2" "$4" "$3"
        result="pass"
    else
        printf "✗ %-30s %8s %s (한도 %s)\n" "$1" "$2" "$4" "$3"
        result="**over**"; fail=1
    fi
    rows+="| $1 | $2 $4 | < $3 $4 | $result |"$'\n'
}
rows=""
check "Idle memory after launch" "$memory" "$MEMORY_LIMIT_MB" "MB"
check "Idle CPU (${WINDOW} s average)" "$cpu" "$CPU_LIMIT_PERCENT" "%"
check "Caller memory after 3 OCRs" "$growth" "$OCR_GROWTH_LIMIT_MB" "MB"
echo "  (실행 뒤 최대 메모리 ${peak} MB, OCR 글자 수 ${chars})"
[[ "${chars:-0}" -gt 0 ]] || { echo "✗ OCR 일꾼이 글자를 읽지 못했습니다"; fail=1; }

if [[ -n "${GITHUB_STEP_SUMMARY:-}" ]]; then
    {
        echo "### Resource budget"
        echo
        echo "| Item | Measured | Limit | Result |"
        echo "|---|---|---|---|"
        printf "%s" "$rows"
        echo
        echo "Peak memory after launch: ${peak} MB. Limits are in docs/ARCHITECTURE.md section 3."
    } >> "$GITHUB_STEP_SUMMARY"
fi
exit "$fail"
