#!/bin/bash

set -euo pipefail

LCOV_FILE="lcov.info"

# Check required tools
for cmd in gh awk grep; do
  if ! command -v "$cmd" &> /dev/null; then
    echo "Error: '$cmd' is not installed."
    exit 1
  fi
done

[[ ! -f "$LCOV_FILE" ]] && echo "Error: $LCOV_FILE not found." && exit 1

# Initialize
COMMENT="### 🔍 Coverage Report
Coverage after merging \`${GITHUB_HEAD_REF:-HEAD}\` into \`${GITHUB_BASE_REF:-main}\`:

<details><summary>Coverage Report</summary>

| File | Stmts | Branches | Funcs | Lines | Uncovered Lines |
|------|-------|----------|-------|-------|-----------------|"

# Track coverage per file
current_file=""
stmt_hit=0; stmt_total=0
func_hit=0; func_total=0
branch_hit=0; branch_total=0
declare -a uncovered_lines

print_file_summary() {
  if [[ -n "$current_file" ]]; then
    stmt_cov=$(printf "%.2f" "$(bc <<< "scale=4; if ($stmt_total > 0) $stmt_hit*100/$stmt_total else 0")")
    branch_cov=$(printf "%.2f" "$(bc <<< "scale=4; if ($branch_total > 0) $branch_hit*100/$branch_total else 0")")
    func_cov=$(printf "%.2f" "$(bc <<< "scale=4; if ($func_total > 0) $func_hit*100/$func_total else 0")")
    line_cov="$stmt_cov"
    uncovered_str=$(IFS=, ; echo "${uncovered_lines[*]}")
    COMMENT+="
| $current_file | ${stmt_cov}% | ${branch_cov}% | ${func_cov}% | ${line_cov}% | ${uncovered_str} |"
  fi
}

# Parse the lcov file
while IFS= read -r line; do
  case "$line" in
    SF:*)
      print_file_summary
      current_file=$(basename "${line#SF:}")
      stmt_hit=0; stmt_total=0
      func_hit=0; func_total=0
      branch_hit=0; branch_total=0
      uncovered_lines=()
      ;;
    DA:*)
      stmt_total=$((stmt_total + 1))
      lineno=$(cut -d',' -f1 <<< "$line" | cut -d':' -f2)
      hits=$(cut -d',' -f2 <<< "$line")
      [[ "$hits" -gt 0 ]] && stmt_hit=$((stmt_hit + 1)) || uncovered_lines+=("$lineno")
      ;;
    FNDA:*)
      hits=$(cut -d',' -f1 <<< "$line" | cut -d':' -f2)
      [[ "$hits" -gt 0 ]] && func_hit=$((func_hit + 1))
      ;;
    FNF:*)
      func_total=$((func_total + ${line#FNF:}))
      ;;
    FNH:*)
      func_hit=$((func_hit + ${line#FNH:}))
      ;;
    BRDA:*)
      branch_total=$((branch_total + 1))
      val=$(cut -d',' -f4 <<< "$line")
      [[ "$val" != "-" && "$val" -gt 0 ]] && branch_hit=$((branch_hit + 1))
      ;;
    end_of_record)
      print_file_summary
      current_file=""
      ;;
  esac
done < "$LCOV_FILE"

COMMENT+="

</details>"

# Post the comment to GitHub PR
if [[ -z "${PR_NUMBER:-}" ]]; then
  echo "❌ Error: PR_NUMBER env var is not set"
  exit 1
fi

gh pr comment "$PR_NUMBER" --body "$COMMENT"
