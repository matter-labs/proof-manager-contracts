#!/bin/bash

set -euo pipefail

LCOV_FILE="lcov.info"
REPO="your_org_or_user/your_repo"  # ← Replace with your GitHub repo
REF="${GITHUB_HEAD_REF:-main}"

# Ensure tools
for cmd in gh bc awk; do
  if ! command -v "$cmd" &> /dev/null; then
    echo "❌ Error: '$cmd' is required but not installed."
    exit 1
  fi
done

[[ ! -f "$LCOV_FILE" ]] && echo "❌ Error: $LCOV_FILE not found." && exit 1

# Start comment
COMMENT="### 🔍 Coverage Report
Coverage after merging \`${GITHUB_HEAD_REF:-HEAD}\` into \`${GITHUB_BASE_REF:-main}\`:

<details><summary>Coverage Report</summary>

| File | Stmts | Branches | Funcs | Lines | Uncovered |
|------|-------|----------|-------|-------|-----------|"

# Init
current_file=""
relative_path=""
stmt_hit=0; stmt_total=0
func_hit=0; func_total=0
branch_hit=0; branch_total=0
declare -a uncovered_lines

# Group uncovered lines: 1,2,3,5,6 → 1-3,5-6
group_lines() {
  local -a lines=($(printf '%s\n' "${uncovered_lines[@]}" | sort -n))
  local output=()
  local start end

  for i in "${!lines[@]}"; do
    [[ -z "$start" ]] && start=${lines[$i]} && end=$start && continue
    if [[ ${lines[$i]} -eq $((end + 1)) ]]; then
      end=${lines[$i]}
    else
      [[ "$start" -eq "$end" ]] && output+=("$start") || output+=("$start-$end")
      start=${lines[$i]}
      end=$start
    fi
  done

  [[ -n "$start" ]] && ([[ "$start" -eq "$end" ]] && output+=("$start") || output+=("$start-$end"))

  # Make links to GitHub
  local link_base="https://github.com/$REPO/blob/$REF/$relative_path"
  local link_list=()
  for range in "${output[@]}"; do
    local link="$link_base#L${range//-/-L}"
    link_list+=("[\`$range\`]($link)")
  done
  IFS=", " ; echo "${link_list[*]}"
}

# Print row for each file
print_file_summary() {
  if [[ -n "$current_file" ]]; then
    stmt_cov=$(printf "%.2f" "$(bc <<< "scale=4; if ($stmt_total > 0) $stmt_hit*100/$stmt_total else 0")")
    branch_cov=$(printf "%.2f" "$(bc <<< "scale=4; if ($branch_total > 0) $branch_hit*100/$branch_total else 0")")
    func_cov=$(printf "%.2f" "$(bc <<< "scale=4; if ($func_total > 0) $func_hit*100/$func_total else 0")")
    line_cov="$stmt_cov"
    uncovered_str=$(group_lines)
    COMMENT+="
| \`$current_file\` | ${stmt_cov}% | ${branch_cov}% | ${func_cov}% | ${line_cov}% | ${uncovered_str} |"
  fi
}

# Parse lcov
while IFS= read -r line; do
  case "$line" in
    SF:*)
      print_file_summary
      relative_path="${line#SF:}"
      current_file=$(basename "$relative_path")
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

# Post to GitHub
if [[ -z "${PR_NUMBER:-}" ]]; then
  echo "❌ Error: PR_NUMBER not set."
  exit 1
fi

gh pr comment "$PR_NUMBER" --body "$COMMENT"
