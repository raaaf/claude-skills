#!/usr/bin/env bash
#
# Warns when the diff is too large for a meaningful audit. Large diffs
# produce noisy findings, waste tokens, and should usually be split.
#
# Output:
#   DIFF_LINES=<n>
#   DIFF_FILES=<n>
#   DIFF_SIZE_RESULT=OK | LARGE | HUGE
set -euo pipefail

# shellcheck source=lib-git-base.sh
source "$(dirname "$0")/lib-git-base.sh"

DEFAULT_BRANCH=$(resolve_default_branch)
BASE_REF=$(resolve_base_ref "$DEFAULT_BRANCH")

LINES=$(git diff --shortstat "$BASE_REF"...HEAD 2>/dev/null | { grep -oE '[0-9]+ insertion|[0-9]+ deletion' || true; } | awk '{s+=$1} END {print s+0}')
WORKING=$(git diff --shortstat HEAD 2>/dev/null | { grep -oE '[0-9]+ insertion|[0-9]+ deletion' || true; } | awk '{s+=$1} END {print s+0}')
TOTAL=$((LINES + WORKING))

FILES=$(git diff --name-only "$BASE_REF"...HEAD 2>/dev/null | wc -l | tr -d ' ')
WORKING_FILES=$(git diff --name-only HEAD 2>/dev/null | wc -l | tr -d ' ')
TOTAL_FILES=$((FILES + WORKING_FILES))

echo "DIFF_LINES=$TOTAL"
echo "DIFF_FILES=$TOTAL_FILES"

if [ "$TOTAL" -gt 5000 ] || [ "$TOTAL_FILES" -gt 50 ]; then
  echo "DIFF_SIZE_RESULT=HUGE"
elif [ "$TOTAL" -gt 2000 ] || [ "$TOTAL_FILES" -gt 20 ]; then
  echo "DIFF_SIZE_RESULT=LARGE"
else
  echo "DIFF_SIZE_RESULT=OK"
fi
