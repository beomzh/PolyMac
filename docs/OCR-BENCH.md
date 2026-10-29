# OCR 정확도 측정

텍스트 추출(OCR) 설정을 바꿀 때 근거로 삼는 측정 방법과 결과입니다. 모두 이 Mac 안에서 Apple Vision으로 돌고, 인터넷을 쓰지 않습니다.

## 실행

```bash
scripts/ocr-bench.sh
```

- `-v`를 붙이면 틀린 샘플의 정답과 인식 결과를 함께 보여 줍니다.
- 다른 폴더를 재려면 `scripts/ocr-bench.sh <폴더>`.
- 샘플 다시 만들기: `swift scripts/make-ocr-samples.swift`
- 다른 설정을 시험하려면 `Sources/OCRBench/main.swift`의 `configs`에 더합니다.
- 표 인식: `scripts/ocr-bench.sh --tables` (아래 [표 인식](#표-인식))

## 샘플

`Tests/OCRSamples/`에 `<이름>.png`(화면 캡처처럼 그린 이미지)와 `<이름>.txt`(정답)가 짝으로 있습니다.

| 샘플 | 내용 |
|---|---|
| ko-body, ko-paragraph, ko-long | 한글 본문, 여러 줄 문단, 큰 캡처(2000 px 폭) |
| ko-small-1x | 11pt 글자를 1배율로 (외장 모니터 등에서 작은 글씨 캡처) |
| mixed-ko-en, english | 한영 혼합, 영어 |
| numbers, address, url-email | 숫자·날짜·전화번호, 주소, URL·이메일 |
| code-mono | 고정폭 글꼴 코드 |
| dark-mode, low-contrast, system-ui | 어두운 배경, 흐린 회색 글자, 시스템 UI 글꼴 |
| symbols | 괄호·낫표·줄표·가운뎃점·말줄임 |

실제 캡처로 재고 싶으면 같은 폴더에 PNG와 정답 TXT를 같은 이름으로 넣으면 됩니다. 개인 정보가 담긴 캡처는 저장소에 올리지 말고 다른 폴더에 두고 재세요.

## 지표

- **글자 오류율(CER)** = 편집 거리 / 정답 글자 수. 비교 전에 한글을 NFC로 맞추고 공백·줄바꿈은 한 칸으로 봅니다 (줄바꿈 정리 방식과 무관하게 글자만 비교).
- **exact**: 오류가 하나도 없는 샘플 수
- **avg ms**: 샘플당 평균 시간 (측정 전에 모든 설정을 한 번씩 돌려 모델 준비 시간은 빼고 잼)

## 결과 (2026-10-29, macOS 26.6, Apple Silicon)

```
sample          app            0.1.0          no-upscale     no-cleanup
address           0.0%           0.0%           0.0%           0.0%
code-mono         5.5%           3.6%           3.6%           5.5%
dark-mode         0.0%           0.0%           0.0%           0.0%
english           0.0%           0.0%           0.0%           0.0%
ko-body           0.0%           0.0%           0.0%           0.0%
ko-long           0.0%           0.0%           0.0%           0.0%
ko-paragraph      0.0%           1.4%           1.4%           0.0%
ko-small-1x       0.0%           0.0%           0.0%           0.0%
low-contrast      0.0%           0.0%           0.0%           0.0%
mixed-ko-en       4.3%           5.7%           5.7%           4.3%
numbers           0.0%           0.0%           0.0%           0.0%
symbols           9.5%          16.7%           9.5%          16.7%
system-ui         0.0%           9.7%           6.5%           6.5%
url-email         0.0%           0.0%           0.0%           0.0%

total CER        0.93%          1.58%          1.21%          1.40%
exact           11/14          9/14           9/14           10/14
avg ms          124            113            112            122
```

- `app`: 지금 앱 설정 (한국어 → 영어, 2배 확대, 기호 정리)
- `0.1.0`: 이전 설정 (확대·정리 없음)

## 알게 된 것

| 시도 | 결과 | 결정 |
|---|---|---|
| 2배 확대 후 인식 | 줄 첫 글자 빠짐("로그인"→"그인")·가운뎃점 누락이 줄어듦. 코드 샘플은 `}`를 `y`로 읽어 조금 나빠짐 | 채택. 2 MP를 넘는 캡처는 확대하지 않음 (큰 글자엔 효과가 없고 2000×1870에서 +0.24초) |
| 기호 정리 | 한글 사이 `•`→`·`, `•·•`→`…` | 채택 (줄 맨 앞 `•`와 마침표 `...`는 그대로) |
| 영어를 먼저 | 한글을 거의 못 읽음 (오류율 62%) | 언어 순서 바꾸기는 넣지 않음 |
| 사용자 단어장 (customWords) | 한국어 인식에서는 효과 없음 | 넣지 않음 |
| 영어로 한 번 더 읽어 대소문자 되살리기 | `macOS`는 못 고치고 `the`→`The` 같은 새 오류 | 넣지 않음 |
| 언어 교정 끄기 | 기호 일부가 나아지나 확대+정리보다 못함 | 켜 둠 |

남은 오류: 한국어 모델이 영어 낱말의 대소문자를 잃음 (`macOS`→`macos`, `isPinned`→`ispinned`), 코드의 `$0`→`$o`, 줄표 `—`→`-`.

## 표 인식

macOS 26의 Vision 문서 인식(`RecognizeDocumentsRequest`)으로 표를 찾아 칸 단위로 비교합니다.

```bash
scripts/ocr-bench.sh --tables      # -v: 틀린 표 전체
swift scripts/make-table-samples.swift   # 샘플 다시 만들기
```

샘플은 `Tests/OCRSamples/tables/`에 `<이름>.png`와 `<이름>.tsv`(정답, 탭으로 나눈 칸)가 짝으로 있습니다.

| 샘플 | 내용 |
|---|---|
| ko-grid, dark-grid | 칸마다 선이 있는 한글 표, 어두운 배경 |
| mixed-numbers | 한영·숫자·쉼표·따옴표, 빈 칸 |
| sheet-light, stripes-en | 옅은 가로선만 (스프레드시트), 줄무늬 (선 없음) |
| ko-small-1x | 11pt 글자를 1배율로 |

지표: **cells right** = 정답과 같은 칸 / 전체 칸, **cell CER** = 칸 글자 오류율, **shape** = 행·열 수가 맞은 표

### 결과 (2026-10-29, macOS 26.6, Apple Silicon)

```
sample          app                   upscale-2x            no-cleanup
dark-grid       9/12 4×3              9/12 4×3              9/12 4×3
ko-grid         16/16 4×4             16/16 4×4             16/16 4×4
ko-small-1x     15/16 4×4             15/16 4×4             15/16 4×4
mixed-numbers   20/20 5×4             20/20 5×4             20/20 5×4
sheet-light     16/16 4×4             16/16 4×4             16/16 4×4
stripes-en      15/15 5×3             15/15 5×3             15/15 5×3

cells right     95.8%                 95.8%                 95.8%
cell CER        1.88%                 1.88%                 1.88%
shape           6/6                   6/6                   6/6
avg ms          221                   266                   216
```

- 선이 없는 표(줄무늬·옅은 가로선)도 행·열을 모두 맞혔습니다.
- 2배 확대는 표에서는 나아지는 게 없고 45 ms 더 걸려 **표는 확대하지 않습니다** (`TableRecognizer.defaultOptions`).
- 틀린 칸: `⌃⇧1` 같은 키 기호(dark-grid 3칸), 작은 글씨의 쉼표를 마침표로 읽음(ko-small-1x `6,108`→`6.108`, 확대해도 같음).
