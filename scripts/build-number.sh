#!/usr/bin/env bash
# VERSION에서 빌드 번호(CFBundleVersion, Sparkle의 sparkle:version)를 만든다.
#   major × 1,000,000 + minor × 1,000 + patch     예) 0.2.18 → 2018, 1.0.0 → 1000000
#   사전 배포(0.3.0-beta.1)는 정식 번호보다 1 작게 — 정식판이 나오면 업데이트로 보인다.
# 커밋 수로 만들면 기능 브랜치 빌드(커밋 여러 개)가 squash 병합 뒤의 정식 릴리스보다 번호가 커져
# Sparkle이 업데이트를 숨기고, 얕은 클론에서는 1이 된다. 버전으로 만들면 버전이 오를 때만 커진다.
# 0.2.13까지는 커밋 수(최대 43)였다 — 새 번호(2014 이상)가 항상 더 크다.
set -euo pipefail
version="${1:-$(tr -d '[:space:]' < "$(dirname "$0")/../VERSION")}"
base="${version%%-*}"
IFS=. read -r major minor patch extra <<< "$base"
if [[ -n "${extra:-}" || ! "$major" =~ ^[0-9]+$ || ! "$minor" =~ ^[0-9]+$ || ! "${patch:-}" =~ ^[0-9]+$ ]] \
    || (( 10#$minor > 999 || 10#$patch > 999 )); then
    echo "✗ 빌드 번호를 만들 수 없는 VERSION: $version (MAJOR.MINOR.PATCH, MINOR·PATCH는 999 이하)" >&2
    exit 1
fi
build=$(( 10#$major * 1000000 + 10#$minor * 1000 + 10#$patch ))
[[ "$version" == "$base" ]] || build=$(( build - 1 ))
echo "$build"
