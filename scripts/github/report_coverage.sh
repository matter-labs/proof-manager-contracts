#!/bin/bash

set -e

LCOV_FILE="lcov.info"
TEMP_DIR=$(mktemp -d)
GENHTML_OUTPUT="${TEMP_DIR}/genhtml"
SUMMARY_FILE="${GENHTML_OUTPUT}/coverage.info"

# Ensure dependencies exist
command -v lcov >/dev/null || { echo "lcov is required but not found."; exit 1; }
command -v genhtml >/dev/null || { echo "genhtml is required but not found."; exit 1; }
command -v gh >/dev/null || { echo "gh CLI is required but not found."; exit 1; }

# Check file existence
if [[ ! -f "$LCOV_FILE" ]]; then
  echo "Coverage file '$LCOV_FILE' not found!"
  exit 1
fi

# Generate HTML and extract summary using genhtml
genhtml "$LCOV_FILE" --output-directory "$GENHTML_OUTPUT" --quiet --branch-coverage > "${TEMP_DIR}/summary.log"

# Get total coverage from summary
TOTAL_LINE_COVERAGE=$(grep "lines......:" "${TEMP_DIR}/summary.log" | head -n1 | awk '{print $2}')
TOTAL_BRANCH_COVERAGE=$(grep "branches...:" "${TEMP_DIR}/summary.log" | head -n1 | awk '{print $2}')
TOTAL_FUNC_COVERAGE=$(grep "functions..:" "${TEMP_DIR}/summary.log" | head -n1 | awk '{print $2}')
TOTAL_STMT_COVERAGE=$TOTAL_LINE_COVERAGE # lcov doesn't report stmts separately, use lines as proxy

# Begin comment content
COMMENT="### 🔍 Coverage Report
Coverage after merging \`${GITHUB_HEAD_REF}\` into \`${GITHUB_BASE_REF}\` will be

**${TOTAL_LINE_COVERAGE}**

<details><summary>Coverage Report</summary>

| File | Stmts | Branches | Funcs | Lines | Uncovered Lines |
|------|-------|----------|-------|-------|-----------------|"

# Parse genhtml-generated per-file summaries
FILE_SUMMARY="${GENHTML_OUTPUT}/index.html"

# Extract per-file stats
grep -Po '(?<=<td class="headerCovTableEntryLo" colspan="2">)[^<]+</td>.*?<td class="headerCovTableEntryLo">[^<]+</td>.*?<td class="headerCovTableEntryLo">[^<]+</td>.*?<td class="headerCovTableEntryLo">[^<]+</td>' "$FILE_SUMMARY" |
while IFS= read -r row; do
  FILE=$(echo "$row" | sed -n 's/.*>\(.*\.sol\)<.*/\1/p')
  STMT=$(echo "$row" | grep -Po '.*<td class="headerCovTableEntryLo">\K[^<]+' | sed -n 1p)
  BR=$(echo "$row" | grep -Po '.*<td class="headerCovTableEntryLo">\K[^<]+' | sed -n 2p)
  FUNC=$(echo "$row" | grep -Po '.*<td class="headerCovTableEntryLo">\K[^<]+' | sed -n 3p)
  LINE=$(echo "$row" | grep -Po '.*<td class="headerCovTableEntryLo">\K[^<]+' | sed -n 4p)
  
  COMMENT+="
| $FILE | $STMT | $BR | $FUNC | $LINE | |"
done

COMMENT+="

</details>"

# Post comment to PR
echo "Posting comment to PR #${PR_NUMBER}..."
gh pr comment "$PR_NUMBER" --body "$COMMENT"
