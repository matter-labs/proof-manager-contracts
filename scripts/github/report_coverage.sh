#!/bin/bash

set -euo pipefail

LCOV_FILE="lcov.info"

# Verify required tools
for cmd in gh awk grep; do
  if ! command -v "$cmd" &> /dev/null; then
    echo "Error: '$cmd' is not installed."
    exit 1
  fi
done

if [[ ! -f "$LCOV_FILE" ]]; then
  echo "Error: '$LCOV_FILE' not found."
  exit 1
fi

# Initialize
COMMENT="### 🔍 Coverage Report
Coverage after merging \`${GITHUB_HEAD_REF:-HEAD}\` into \`${GITHUB_BASE_REF:-main}\`:

<details><summary>Coverage Report</summary>

| File | Stmts | Branches | Funcs | Lines | Uncovered Lines |
|------|-------|----------|-------|-------|-----------------|"

# Temporary variables
current_file=""
declare -a uncovered_lines
stmt_hit=0
stmt_total=0
func_hit=0
func_total=0
branch_hit=0
branch_total=0

print_file_summary() {
  if [[ -n "$current_file" ]]; then
    stmt_cov=$(awk "BEGIN {printf \"%.2f\", ($stmt_total ? $stmt_hit / $stmt_total * 100 : 0)}")
    branch_cov=$(awk "BEGIN {printf \"%.2f\", ($branch_total ? $branch_hit / $branch_total * 100 : 0)}")
    func_cov=$(awk "BEGIN {printf \"%.2f\", ($func_total ? $func_hit / $func_total * 100 : 0)}")
    line_cov="$stmt_cov"
    uncovered_line_str=$(IFS=, ; echo "${uncovered_lines[*]}")
    COMMENT+="
| $current_file | ${stmt_cov}% | ${branch_cov}% | ${func_cov}% | ${line_cov}% | ${uncovered_line_str} |"
  fi
}

# Parse lcov.info
while IFS= read -r line; do
  case "$line" in
    SF:*)
      print_file_summary
      current_file=$(basename "${line#SF:}")
      uncovered_lines=()
      stmt_hit=0; stmt_total=0
      func_hit=0; func_total=0
      branch_hit=0; branch_total=0
      ;;
    DA:*)
      stmt_total=$((stmt_total + 1))
      hits=$(echo "$line" | cut -d',' -f2)
      lineno=$(echo "$line" | cut -d',' -f1 | cut -d':' -f2)
      if [[ "$hits" -gt 0 ]]; then
        stmt_hit=$((stmt_hit + 1))
      else
        uncovered_lines+=("$lineno")
      fi
      ;;
    FNDA:*)
      hits=$(echo "$line" | cut -d',' -f1 | cut -d':' -f2)
      if [[ "$hits" -gt 0 ]]; then
        func_hit=$((func_hit + 1))
      fi
      ;;
    FNF:*)
      func_total=$((func_total + ${line#FNF:}))
      ;;
    FNH:*)
      func_hit=$((func_hit + ${line#FNH:}))
      ;;
    BRDA:*)
      branch_total=$((branch_total + 1))
      parts=(${line//,/ })
      [[ "${parts[3]}" != "-" && "${parts[3]}" -gt 0 ]] && branch_hit=$((branch_hit + 1))
      ;;
    end_of_record)
      print_file_summary
      current_file=""
      ;;
  esac
done < "$LCOV_FILE"

COMMENT+="

</details>"

# Post to GitHub PR
if [[ -z "${PR_NUMBER:-}" ]]; then
  echo "Error: PR_NUMBER environment variable not set."
  exit 1
fi

gh pr comment "$PR_NUMBER" --body "$COMMENT"
