#!/usr/bin/env bash
# README.md(영어)와 README.ko.md(한국어)가 같은 내용을 담고 있는지 확인한다.
# 한쪽만 고치면 실패한다 — 규칙은 CONTRIBUTING.md "README는 두 언어로".
#   1. 제목 단계(#, ##, ###…)의 순서가 같다
#   2. bash 코드 블록이 같은 순서로 똑같다 (명령은 번역하지 않는다)
#   3. 저장소 안 파일 링크(docs/…, LICENSE 등)가 같다 — 문서 안 앵커(#…)와 외부 주소는 언어마다 달라 뺀다
#   4. "현재 버전"과 "Current version"의 번호가 같다
set -euo pipefail
cd "$(dirname "$0")/.."
EN=README.md KO=README.ko.md
fail=0
report() { echo "✗ README 불일치: $1" >&2; fail=1; }

headings() { awk '/^```/{c=!c; next} !c && /^#+ /{match($0,/^#+/); print RLENGTH}' "$1"; }
bash_blocks() { awk '/^```bash$/{b=1; print "---"; next} /^```/{b=0; next} b' "$1"; }
links() { grep -oE '\]\([^)#][^)]*\)|src="[^"]+"' "$1" | sed -E 's/^\]\(|\)$|^src="|"$//g' | grep -v -E '^README(\.ko)?\.md$|^https?://' | sort -u; }

[[ -f $EN && -f $KO ]] || { echo "✗ $EN 또는 $KO가 없습니다" >&2; exit 1; }
diff <(headings $EN) <(headings $KO) > /dev/null || report "제목 구조가 다릅니다 (단계 순서: $EN $(headings $EN | wc -l | tr -d ' ')개, $KO $(headings $KO | wc -l | tr -d ' ')개)"
diff <(bash_blocks $EN) <(bash_blocks $KO) > /dev/null || report "bash 코드 블록이 다릅니다 — diff <(awk '/^\`\`\`bash/,/^\`\`\`$/' $EN) <(awk '/^\`\`\`bash/,/^\`\`\`$/' $KO)"
if ! diff <(links $EN) <(links $KO) > /dev/null; then report "링크한 파일이 다릅니다:"; diff <(links $EN) <(links $KO) | grep -E '^[<>]' | sed 's/^/    /' >&2; fi
v_en="$(grep -oE 'Current version [0-9][0-9.]*' $EN | head -1 | awk '{print $3}')"
v_ko="$(grep -oE '현재 버전 [0-9][0-9.]*' $KO | head -1 | awk '{print $3}')"
[[ -n $v_en && $v_en == "$v_ko" ]] || report "현재 버전 표기가 다릅니다 ($EN: ${v_en:-없음}, $KO: ${v_ko:-없음})"
grep -q 'href="README.ko.md"' $EN || report "$EN에 한국어 링크가 없습니다"
grep -q 'href="README.md"' $KO || report "$KO에 English 링크가 없습니다"

if (( fail )); then echo "  두 README를 함께 고치세요 (CONTRIBUTING.md)" >&2; exit 1; fi
echo "✓ README.md · README.ko.md 구조 일치"
