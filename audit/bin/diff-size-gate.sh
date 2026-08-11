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
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/lib-git-base.sh"

DEFAULT_BRANCH=$(resolve_default_branch)
BASE_REF=$(resolve_base_ref "$DEFAULT_BRANCH")

# Combined diff: committed-unpushed + working-tree changes, deduplicated.
# Using BASE_REF..HEAD (two-dot) + unstaged would double-count files that have
# both committed and working-tree changes. Instead, diff from BASE_REF to the
# working tree directly (which includes staged + unstaged on top of HEAD).
TOTAL=$(git diff --shortstat "$BASE_REF" 2>/dev/null | { grep -oE '[0-9]+ insertion|[0-9]+ deletion' || true; } | awk '{s+=$1} END {print s+0}')
TOTAL_FILES=$(git diff --name-only "$BASE_REF" 2>/dev/null | wc -l | tr -d ' ')

# `git diff` (any form, against any ref) never reports untracked (never-`git
# add`ed) files, so they are invisible to both counts above. That matters here
# specifically: a diff dominated by new untracked files is the single biggest
# kind of change this gate exists to catch, and it would silently dodge
# LARGE/HUGE exactly then. Union them in, matching collect_changed_files()'s
# use of `git ls-files --others --exclude-standard`.
#
# There is no ref to diff an untracked file against, so a per-file line count
# can't come from `git diff <ref>` the way the tracked total above does.
# Chosen approach: `git diff --no-index /dev/null <file>`, which reports the
# same "N insertions" shortstat a tracked file would show on its first
# commit. That keeps untracked and tracked files on one consistent basis
# (line count, not byte or `wc -l` count), and a binary untracked file
# contributes 0 insertions, same as a tracked binary add would.
UNTRACKED_FILES=0
UNTRACKED_LINES=0
while IFS= read -r -d '' f; do
  [ -n "$f" ] || continue
  UNTRACKED_FILES=$((UNTRACKED_FILES + 1))
  LINES=$(git diff --no-index --shortstat -- /dev/null "$f" 2>/dev/null | grep -oE '[0-9]+ insertion' | awk '{print $1}') || true
  UNTRACKED_LINES=$((UNTRACKED_LINES + ${LINES:-0}))
done < <(git ls-files -z --others --exclude-standard 2>/dev/null)

TOTAL=$((TOTAL + UNTRACKED_LINES))
TOTAL_FILES=$((TOTAL_FILES + UNTRACKED_FILES))

echo "DIFF_LINES=$TOTAL"
echo "DIFF_FILES=$TOTAL_FILES"

if [ "$TOTAL" -gt 5000 ]; then
  echo "DIFF_SIZE_RESULT=HUGE"
elif [ "$TOTAL_FILES" -gt 50 ]; then
  # Two-axis rule: file threshold exceeded, but lines under 20% of the line
  # threshold means many small, logically separate changes — warn and continue
  # as LARGE instead of recommending an abort.
  if [ "$TOTAL" -lt 1000 ]; then
    echo "DIFF_SIZE_RESULT=LARGE"
    echo "DIFF_SIZE_NOTE=$TOTAL_FILES files exceed the file threshold, but only $TOTAL changed lines (<20% of the line threshold) — downgraded from HUGE, continuing with a warning"
  else
    echo "DIFF_SIZE_RESULT=HUGE"
  fi
elif [ "$TOTAL" -gt 2000 ] || [ "$TOTAL_FILES" -gt 20 ]; then
  echo "DIFF_SIZE_RESULT=LARGE"
else
  echo "DIFF_SIZE_RESULT=OK"
fi
