#!/usr/bin/env bash
# Resume dirty-check for /full-audit. For every batch marked "clean" in the state
# file, compare the batch file list against everything that changed since the HEAD
# recorded at batch completion (committed diff + current working tree). Emits one
# line per clean batch:
#   BATCH_DIRTY id=<ID> files=<K>    -> orchestrator resets the row to pending
#   BATCH_CLEAN id=<ID>              -> keep clean, never re-audit
# Fails toward re-auditing: missing batch list or unresolvable HEAD -> BATCH_DIRTY.
# This script only READS; resetting rows is the orchestrator's job (orchestrator
# writes, scripts return). Batch lists must be repo-root-relative (one path per
# line), same as git output. bash 3.2 safe.
#
# Usage: resume-check.sh <STATE_FILE>
set -uo pipefail
STATE="${1:?usage: resume-check.sh <state-file>}"

[ -f "$STATE" ] || { echo "NO_STATE"; exit 0; }
ROOT=$(git rev-parse --show-toplevel 2>/dev/null) || { echo "NOT_A_REPO"; exit 2; }
cd "$ROOT" || exit 2

BATCH_DIR=$(grep -m1 '^batch-dir:' "$STATE" | sed 's/^batch-dir:[[:space:]]*//')
[ -n "$BATCH_DIR" ] || BATCH_DIR=".claude/audits/full-audit-batches"

# Emit "id<TAB>head" per clean row; columns located from the header row.
awk '
  function trim(s){ gsub(/^[ \t]+|[ \t]+$/,"",s); return s }
  BEGIN{ FS="|"; id_col=0; status_col=0; head_col=0 }
  /^[[:space:]]*\|/ {
    if (status_col==0) {
      for(f=1;f<=NF;f++){ c=tolower(trim($f))
        if(c=="id") id_col=f
        if(c=="status") status_col=f
        if(c=="head") head_col=f }
      if (status_col>0) next
    }
    if ($0 ~ /^[[:space:]]*\|[[:space:]:|-]+$/) next
    if (status_col>0 && id_col>0) {
      st=tolower(trim($status_col))
      if (st=="clean") printf "%s\t%s\n", trim($id_col), (head_col>0 ? trim($head_col) : "")
    }
  }
' "$STATE" | while IFS=$(printf '\t') read -r id head; do
  [ -n "$id" ] || continue
  batch_file="$BATCH_DIR/batch-$id.txt"

  if [ ! -f "$batch_file" ]; then
    echo "BATCH_DIRTY id=$id files=unknown"
    continue
  fi
  if [ -z "$head" ] || [ "$head" = "-" ] || ! git rev-parse --verify --quiet "${head}^{commit}" >/dev/null 2>&1; then
    echo "BATCH_DIRTY id=$id files=unknown"
    continue
  fi

  changed=$( { git diff --name-only "${head}..HEAD" 2>/dev/null
               git status --porcelain 2>/dev/null | sed 's/^...//; s/^.* -> //'; } | sort -u )
  if [ -z "$changed" ]; then
    echo "BATCH_CLEAN id=$id"
    continue
  fi

  dirty_count=$(printf '%s\n' "$changed" | sort -u | comm -12 - <(sort -u "$batch_file") | grep -c . || true)
  if [ "$dirty_count" -gt 0 ]; then
    echo "BATCH_DIRTY id=$id files=$dirty_count"
  else
    echo "BATCH_CLEAN id=$id"
  fi
done
exit 0
