#!/usr/bin/env bash
# 영어 문서(NAME.md)와 한국어 문서(NAME.ko.md)가 같은 내용을 담고 있는지 확인한다.
# 한쪽만 고치면 실패한다 — 규칙은 CONTRIBUTING.md "Documents in two languages".
#   1. 제목 단계(#, ##, ###…)의 순서가 같다
#   2. bash 코드 블록이 같은 순서로 똑같다 (명령은 번역하지 않는다, `#` 주석은 빼고 비교)
#   3. 저장소 안 파일 링크가 같다 — NAME.ko.md는 NAME.md로 맞춰 비교하고, 앵커(#…)와 외부 주소는 언어마다 달라 뺀다
#   4. 서로를 가리키는 언어 전환 링크가 있다
#   5. README의 "Current version"과 "현재 버전" 번호가 같다
set -euo pipefail
cd "$(dirname "$0")/.."
fail=0
report() { echo "✗ $1" >&2; fail=1; }

headings() { awk '/^```/{c=!c; next} !c && /^#+ /{match($0,/^#+/); print RLENGTH}' "$1"; }
bash_blocks() { awk '/^```bash$/{b=1; print "---"; next} /^```/{b=0; next} b' "$1" | sed -E 's/[[:space:]]+#.*$//; /^[[:space:]]*#/d'; }
links() {
  grep -oE '\]\([^)#][^)]*\)|src="[^"]+"|href="[^"#][^"]*"' "$1" \
    | sed -E 's/^\]\(|\)$|^src="|^href="|"$//g; s/#.*$//; s/\.ko\.md$/.md/' \
    | grep -v -E '^https?://' | sort -u
}

pairs=0
while IFS= read -r ko; do
  en="${ko%.ko.md}.md"
  pairs=$((pairs + 1))
  if [[ ! -f $en ]]; then report "$ko: 영어판 ${en}이 없습니다"; continue; fi
  name="$(basename "$en" .md)"
  diff <(headings "$en") <(headings "$ko") > /dev/null \
    || report "$en ↔ $ko: 제목 구조가 다릅니다 (단계 순서: $(headings "$en" | wc -l | tr -d ' ')개 vs $(headings "$ko" | wc -l | tr -d ' ')개)"
  diff <(bash_blocks "$en") <(bash_blocks "$ko") > /dev/null \
    || report "$en ↔ $ko: bash 코드 블록이 다릅니다"
  if ! diff <(links "$en") <(links "$ko") > /dev/null; then
    report "$en ↔ $ko: 링크한 파일이 다릅니다:"
    diff <(links "$en") <(links "$ko") | grep -E '^[<>]' | sed 's/^/    /' >&2
  fi
  grep -qE "\]\($name\.ko\.md\)|href=\"$name\.ko\.md\"" "$en" || report "$en: 한국어판($name.ko.md) 링크가 없습니다"
  grep -qE "\]\($name\.md\)|href=\"$name\.md\"" "$ko" || report "$ko: 영어판($name.md) 링크가 없습니다"
done < <(git ls-files --cached --others --exclude-standard '*.ko.md')

v_en="$(grep -oE 'Current version [0-9][0-9.]*' README.md | head -1 | awk '{print $3}')"
v_ko="$(grep -oE '현재 버전 [0-9][0-9.]*' README.ko.md | head -1 | awk '{print $3}')"
[[ -n $v_en && $v_en == "$v_ko" ]] || report "README 현재 버전 표기가 다릅니다 (README.md: ${v_en:-없음}, README.ko.md: ${v_ko:-없음})"

# 일본어·중국어 README는 요약판 — 버전 번호와 다른 언어판으로 가는 링크만 맞춘다
summaries=0
for f in README.ja.md README.zh-Hans.md README.zh-Hant.md; do
  [[ -f $f ]] || { report "$f이 없습니다"; continue; }
  summaries=$((summaries + 1))
  grep -q "$v_en" "$f" || report "$f: 버전 ${v_en}이 README.md와 다릅니다"
  for other in README.md README.ko.md README.ja.md README.zh-Hans.md README.zh-Hant.md; do
    [[ $other == "$f" ]] && continue
    grep -q "href=\"$other\"" "$f" || report "$f: $other 링크가 없습니다"
    grep -q "href=\"$f\"" "$other" || report "$other: $f 링크가 없습니다"
  done
done

if (( fail )); then echo "  영어·한국어 문서를 함께 고치세요 (CONTRIBUTING.md)" >&2; exit 1; fi
echo "✓ 문서 ${pairs}쌍 구조 일치 (영어 · 한국어), README 요약판 ${summaries}개 (日本語 · 简体中文 · 繁體中文)"
