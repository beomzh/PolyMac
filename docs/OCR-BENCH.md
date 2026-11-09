# OCR accuracy measurements

**English** · [한국어](OCR-BENCH.ko.md)

How OCR accuracy is measured, and the results that OCR setting changes are based on. Everything runs on this Mac with Apple Vision, without the internet.

## Running

```bash
scripts/ocr-bench.sh
```

- Add `-v` to show the expected text and the recognized text for samples with errors.
- To measure another folder: `scripts/ocr-bench.sh <folder>`.
- Regenerate the samples: `swift scripts/make-ocr-samples.swift`
- To try other settings, add them to `configs` in `Sources/OCRBench/main.swift`.
- Tables: `scripts/ocr-bench.sh --tables` (see [Table recognition](#table-recognition) below)

## Samples

`Tests/OCRSamples/` holds pairs of `<name>.png` (an image drawn like a screen capture) and `<name>.txt` (the expected text).

| Sample | Content |
|---|---|
| ko-body, ko-paragraph, ko-long | Korean body text, a multi-line paragraph, a large capture (2000 px wide) |
| ko-small-1x | 11 pt text at 1x scale (small text captured on an external monitor, etc.) |
| mixed-ko-en, english | Mixed Korean and English, English |
| numbers, address, url-email | Numbers, dates, phone numbers, an address, URLs and email |
| code-mono | Code in a monospaced font |
| dark-mode, low-contrast, system-ui | Dark background, faint gray text, the system UI font |
| symbols | Brackets, corner brackets, dashes, middle dots, ellipses |
| code-indent, yaml-indent | Indented code and YAML (monospaced font) — measures whitespace preservation |
| ko-list | An indented Korean list (proportional font) |

To measure real captures, put a PNG and an expected-text TXT with the same name in the same folder. Don't commit captures containing personal information; keep them in another folder and measure there.

## Metrics

- **Character error rate (CER)** = edit distance / number of expected characters. Before comparing, Korean is normalized to NFC and whitespace and line breaks count as one space (only characters are compared, regardless of line break cleanup).
- **exact**: number of samples with no errors at all
- **layout CER**: the same edit distance measured with whitespace kept as is (only trailing spaces and blank lines removed). Shows whether leading indentation survived.
- **avg ms**: average time per sample (every setting is run once before measuring, so model warm-up time is excluded)

## Results (2026-11-02, macOS 26.6.2, Apple Silicon)

```
sample          app            0.1.0          no-upscale     no-cleanup     no-indent
address           0.0%           0.0%           0.0%           0.0%           0.0%
code-indent       6.6%           5.8%           5.8%           6.6%           6.6%
code-mono         5.5%           3.6%           3.6%           5.5%           5.5%
dark-mode         0.0%           0.0%           0.0%           0.0%           0.0%
english           0.0%           0.0%           0.0%           0.0%           0.0%
ko-body           0.0%           0.0%           0.0%           0.0%           0.0%
ko-list           0.0%           0.0%           0.0%           0.0%           0.0%
ko-long           0.0%           0.0%           0.0%           0.0%           0.0%
ko-paragraph      0.0%           1.4%           1.4%           0.0%           0.0%
ko-small-1x       0.0%           0.0%           0.0%           0.0%           0.0%
low-contrast      0.0%           0.0%           0.0%           0.0%           0.0%
mixed-ko-en       4.3%           5.7%           5.7%           4.3%           4.3%
numbers           0.0%           0.0%           0.0%           0.0%           0.0%
symbols           9.5%          16.7%           9.5%          16.7%           9.5%
system-ui         0.0%           9.7%           6.5%           6.5%           0.0%
url-email         0.0%           0.0%           0.0%           0.0%           0.0%
yaml-indent       6.3%           8.9%           8.9%           6.3%           6.3%

total CER        1.73%          2.33%          2.03%          2.10%          1.73%
exact           12/17          10/17          10/17          11/17          12/17
avg ms          136            118            117            133            133

layout (compared including spaces and indentation)
address           0.0%           0.0%           0.0%           0.0%           0.0%
code-indent       8.3%           4.8%           4.8%           8.3%          22.1%
code-mono         5.5%           3.6%           3.6%           5.5%           5.5%
dark-mode         0.0%           0.0%           0.0%           0.0%           0.0%
english           0.0%           0.0%           0.0%           0.0%           0.0%
ko-body           0.0%           0.0%           0.0%           0.0%           0.0%
ko-list           9.1%           9.1%           9.1%           9.1%          13.6%
ko-long           0.7%           0.7%           0.7%           0.7%           0.7%
ko-paragraph      0.0%           1.4%           1.4%           0.0%           0.0%
ko-small-1x       0.0%           0.0%           0.0%           0.0%           0.0%
low-contrast      0.0%           0.0%           0.0%           0.0%           0.0%
mixed-ko-en       4.3%           5.7%           5.7%           4.3%           4.3%
numbers           0.0%           0.0%           0.0%           0.0%           0.0%
symbols           9.5%          16.7%           9.5%          16.7%           9.5%
system-ui         0.0%           9.7%           6.5%           6.5%           0.0%
url-email         0.0%           0.0%           0.0%           0.0%           0.0%
yaml-indent       5.0%           6.9%           6.9%           5.0%          26.7%
layout CER       2.60%          2.89%          2.60%          2.96%          5.84%
layout exact    10/17          8/17           8/17           9/17           10/17
```

- `app`: the current app settings (Korean → English, 2x upscale, symbol cleanup)
- `0.1.0`: the previous settings (no upscale or cleanup)
- `no-indent`: settings that don't preserve indentation (the app up to 0.2.1)

## What we learned

| Attempt | Result | Decision |
|---|---|---|
| Recognize after a 2x upscale | Fewer dropped first characters ("로그인" → "그인") and missing middle dots. Code samples got slightly worse by reading `}` as `y` | Adopted. Captures over 2 MP are not upscaled (no effect on large text, and +0.24 s at 2000×1870) |
| Symbol cleanup | `•` → `·` between Korean text, `•·•` → `…` | Adopted (a `•` at the start of a line and a period `...` are left alone) |
| English first | Almost no Korean is read (62% error rate) | Language order is not changed |
| Custom word list (customWords) | No effect on Korean recognition | Not added |
| Reading again in English to restore letter case | Doesn't fix `macOS` and adds new errors like `the` → `The` | Not added |
| Turning off language correction | Some symbols improve, but less than upscale + cleanup | Kept on |
| Preserving indentation ("keep lines as shown") | Rebuilds leading spaces from the line box's left edge ÷ the width of one character. layout CER 5.84% → 2.60% (code-indent 22.1→8.3%, yaml-indent 26.7→5.0%, ko-list 13.6→9.1%), samples without indentation unchanged | Adopted (default). Differences under two spaces are dropped, and it is skipped when lines sit side by side (multiple columns, tables). With proportional fonts spaces are narrow, so the count isn't exact |

Remaining errors: the Korean model loses the case of English words (`macOS` → `macos`, `isPinned` → `ispinned`), `$0` → `$o` in code, the dash `—` → `-`, the 2x upscale misses lines that contain only `}` (code-indent), and a space before colons like `services:` → `services :`.

## Table recognition

Finds tables with macOS 26 Vision document recognition (`RecognizeDocumentsRequest`) and compares them cell by cell.

```bash
scripts/ocr-bench.sh --tables      # -v: every wrong table in full
swift scripts/make-table-samples.swift   # regenerate the samples
```

`Tests/OCRSamples/tables/` holds pairs of `<name>.png` and `<name>.tsv` (expected cells, tab-separated).

| Sample | Content |
|---|---|
| ko-grid, dark-grid | A Korean table with lines around every cell, a dark background |
| mixed-numbers | Korean and English, numbers, commas, quotes, empty cells |
| sheet-light, stripes-en | Only faint horizontal lines (spreadsheet), stripes (no lines) |
| ko-small-1x | 11 pt text at 1x scale |

Metrics: **cells right** = cells matching the expected text / all cells, **cell CER** = character error rate per cell, **shape** = tables with the right number of rows and columns

### Results (2026-10-29, macOS 26.6, Apple Silicon)

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

- Tables without lines (stripes, faint horizontal lines) got every row and column right too.
- A 2x upscale doesn't help tables and takes 45 ms longer, so **tables are not upscaled** (`TableRecognizer.defaultOptions`).
- Wrong cells: key symbols like `⌃⇧1` (3 cells in dark-grid), and a comma in small text read as a period (ko-small-1x `6,108` → `6.108`, same with upscaling).
