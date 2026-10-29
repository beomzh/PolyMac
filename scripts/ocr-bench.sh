#!/usr/bin/env bash
# OCR 정확도 측정 — 샘플(기본 Tests/OCRSamples)의 글자 오류율을 설정별로 비교한다.
#
#   scripts/ocr-bench.sh [샘플 폴더] [-v]     (-v: 틀린 결과 글자까지)
#   scripts/ocr-bench.sh --tables [-v]       표 인식 (Tests/OCRSamples/tables, macOS 26 이상)
#
# 샘플 다시 만들기: swift scripts/make-ocr-samples.swift, swift scripts/make-table-samples.swift
set -euo pipefail
cd "$(dirname "$0")/.."
swift build -c release --product OCRBench > /dev/null
exec "$(swift build -c release --show-bin-path)/OCRBench" "$@"
