#!/bin/bash

set -e

# Define input file
LCOV_FILE="lcov.info"

# Generate summary
TOTAL_COVERAGE=$(genhtml $LCOV_FILE --branch-coverage --quiet --output-directory /tmp/lcov-summary | grep "lines......: " | awk '{print $2}')

# Create a markdown table header
COMMENT="### 🔍 Coverage Report
Coverage after merging \`${GITHUB_HEAD_REF}\` into \`${GITHUB_BASE_REF}\` will be

**${TOTAL_COVERAGE}**

<details><summary>Coverage Report</summary>

\`\`\`
File                            Stmts    Branches    Funcs    Lines    Uncovered Lines
\`\`\`"

# Extract detailed file-wise report using lcov-summary or similar
TABLE=$(lcov --summary $LCOV_FILE | grep -A 100 "Filename" | tail -n +2 | awk '{printf "%-32s %6s %10s %8s %8s\n", $1, $2, $3, $4, $5}')

# Format into Markdown
COMMENT+="
\`\`\`
$TABLE
\`\`\`
</details>
"

# Post comment on PR using GitHub CLI
gh pr comment "$PR_NUMBER" --body "$COMMENT"
