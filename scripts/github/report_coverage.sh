#!/bin/bash

set -e

LCOV_FILE="lcov.info"

# Ensure required tools are installed
for cmd in lcov gh; do
  if ! command -v $cmd &> /dev/null; then
    echo "Error: $cmd is not installed."
    exit 1
  fi
done

# Check if lcov.info exists
if [[ ! -f "$LCOV_FILE" ]]; then
  echo "Error: $LCOV_FILE not found."
  exit 1
fi

# Initialize total counters
total_lines=0
total_lines_hit=0
total_branches=0
total_branches_hit=0
total_functions=0
total_functions_hit=0

# Initialize comment content
COMMENT="### 🔍 Coverage Report
Coverage after merging \`${GITHUB_HEAD_REF}\` into \`${GITHUB_BASE_REF}\`:

<details><summary>Coverage Details</summary>

| File | Stmts | Branches | Funcs | Lines |
|------|-------|----------|-------|-------|"

# Parse lcov.info
awk '
  /^SF:/ { file=$0; sub(/^SF:/, "", file); nextfile=1 }
  /^DA:/ { split($0, a, ","); total_lines++; if (a[2] > 0) total_lines_hit++ }
  /^BRDA:/ { split($0, a, ","); total_branches++; if (a[4] != "-" && a[4] > 0) total_branches_hit++ }
  /^FN:/ { total_functions++ }
  /^FNDA:/ { split($0, a, ","); if (a[1] == "FNDA" && a[2] > 0) total_functions_hit++ }
  /^end_of_record/ {
    if (nextfile) {
      stmt_cov = total_lines ? (total_lines_hit / total_lines) * 100 : 0
      branch_cov = total_branches ? (total_branches_hit / total_branches) * 100 : 0
      func_cov = total_functions ? (total_functions_hit / total_functions) * 100 : 0
      line_cov = stmt_cov  # Assuming statements coverage is equivalent to lines coverage

      printf "| %s | %.2f%% | %.2f%% | %.2f%% | %.2f%% |\n", file, stmt_cov, branch_cov, func_cov, line_cov

      # Reset counters
      total_lines=0; total_lines_hit=0
      total_branches=0; total_branches_hit=0
      total_functions=0; total_functions_hit=0
      nextfile=0
    }
  }
' "$LCOV_FILE" >> temp_coverage_report.md

# Append per-file coverage to comment
cat temp_coverage_report.md >> temp_comment.md
rm temp_coverage_report.md

# Calculate total coverage
total_stmt_cov=$(lcov --summary "$LCOV_FILE" | awk '/lines\.*:/{print $2}')
total_branch_cov=$(lcov --summary "$LCOV_FILE" | awk '/branches\.*:/{print $2}')
total_func_cov=$(lcov --summary "$LCOV_FILE" | awk '/functions\.*:/{print $2}')
total_line_cov=$total_stmt_cov  # Assuming statements coverage is equivalent to lines coverage

# Append total coverage to comment
echo "
</details>

**Total Coverage:**

- Statements: $total_stmt_cov
- Branches: $total_branch_cov
- Functions: $total_func_cov
- Lines: $total_line_cov
" >> temp_comment.md

# Post comment to PR
gh pr comment "$PR_NUMBER" --body "$(cat temp_comment.md)"
rm temp_comment.md
