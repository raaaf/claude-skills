#!/bin/bash
# Benchmark one historical case against the /audit gate (find and log only).
#
# Usage: run-case.sh <case-no> <repo> <base> <head> <out-dir>
#   case-no  label used for the output subdirectory (see cases.md)
#   repo     path of the git repository the case comes from
#   base     commit the audited change starts from
#   head     last commit of the audited change
#   out-dir  parent directory for results; this run writes <out-dir>/case<N>/
#
# What it does: a detached worktree at <base> inside the output directory, <base>..<head> applied
# as an UNCOMMITTED diff (so the audit scope is the pending change, as before a push), then
# a headless `claude -p "/audit ..."` (bin/lib-headless.sh: narrow allow list, AUDIT_DONE sentinel, up to 3 resumes) with AUDIT_DIMENSIONS=all, AUDIT_FIX_SCOPE=none (find and log only),
# AUDIT_BASE_REF=<base> and AUDIT_SKIP_LEARNING_CHECK=1 (skips Phase 0, the open issues/PR
# lookup, which must not look at the real repo). The audit log is copied next to claude.out.
#
# CLEANUP IS MANUAL. The worktree stays at <out-dir>/case<N>/audit-review.wt so the log and state
# can be inspected. Remove it afterwards with the lib helper from inside <repo>, never with a
# literal force-remove git command (the worktree git guard blocks that in a Bash call):
#   cd <repo> && . <skills>/audit/bin/lib-orchestrator.sh && orch_review_worktree_remove "<out-dir>/case<N>/audit-review.wt"
#
# A run costs 8.5-14.4 M weighted tokens and 15-20 minutes. Run one case at a time.
# bash 3.2 compatible.
set -u

if [ "$#" -ne 5 ]; then
  echo "usage: $0 <case-no> <repo> <base> <head> <out-dir>" >&2
  exit 2
fi
N="$1"; REPO="$2"; BASE="$3"; HEAD="$4"
OUT="$5/case$N"
WT="$OUT/audit-review.wt"   # the name must contain audit-review.: orch_review_worktree_remove refuses other paths
mkdir -p "$OUT" || exit 1

git -C "$REPO" worktree add --detach "$WT" "$BASE" >"$OUT/setup.log" 2>&1 \
  || { echo "worktree failed" >>"$OUT/setup.log"; exit 1; }
git -C "$REPO" diff --binary "$BASE" "$HEAD" >"$OUT/case.patch"
( cd "$WT" && git apply "$OUT/case.patch" ) >>"$OUT/setup.log" 2>&1 \
  || { echo "apply failed" >>"$OUT/setup.log"; exit 1; }
echo "changed: $(cd "$WT" && git status --short | wc -l)" >>"$OUT/setup.log"

START=$(date +%s)
. "$(cd "$(dirname "$0")" && pwd)/../bin/lib-headless.sh"
export AUDIT_DIMENSIONS=all AUDIT_FIX_SCOPE=none AUDIT_BASE_REF="$BASE" AUDIT_SKIP_LEARNING_CHECK=1
audit_headless_run "$WT" "/audit Gib als allerletzte Zeile AUDIT_DONE aus, erst nachdem jeder gestartete Workflow beendet und das Log geschrieben ist." \
  AUDIT_DONE "$OUT/claude.out" 0
echo "rc=$? resumes=$HEADLESS_RESUMES seconds=$(( $(date +%s) - START ))" >>"$OUT/setup.log"

# Audit logs are named YYYY-MM-DD_HHMMSS-<branch>.md (audit-log-template.md).
cp "$WT"/.claude/audits/[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]_*.md "$OUT/" 2>/dev/null
echo "done; from inside $REPO remove the worktree with orch_review_worktree_remove \"$WT\"" >>"$OUT/setup.log"
