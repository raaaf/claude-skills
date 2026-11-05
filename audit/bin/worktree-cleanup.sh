#!/usr/bin/env bash
# Ends a git worktree cleanly: stops what its test runs left behind, drops its registered test databases, removes
# the worktree and its branch. Called by `/worktree rm` and by the Feierabend daemon (after merged, on archive or
# discard of a failed task; not while a retry is possible).
#
# Usage: worktree-cleanup.sh <worktree>
# Exit:  0 removed, 1 refused (one line `worktree-cleanup: refused ...`), 2 usage.
# Env (tests): TESTRUN_STATE_DIR, TESTRUN_PSQL, TESTRUN_KILL_GRACE; the lib's own variables apply.
#
# Refuses (nothing touched) for the main checkout, uncommitted changes (tracked or untracked, ignored files do not
# count) and commits that no remote branch contains.
# Processes: only what is proven to belong to this worktree, always by process group, never by name:
#   1. every live run ticket (lib-testrun.sh) whose cwd is inside the worktree: its group and descendants. That
#      covers the test command, Paratest workers and the Playwright servers started by Pest in that group.
#   2. a process with parent 1 whose cwd is inside the worktree (an orphaned browser or Playwright server whose
#      group left the ticket): the pid and its descendants (its group only when it leads it, tr_kill_orphan). An
#      interactive shell sitting in the folder has a real parent and is safe.
# Then the registered databases (tr_worktree_cleanup), `git worktree remove`, and the branch: `-d`, or `-D` when
# a remote branch contains it. bash 3.2 compatible.

set -u
HERE=$(cd "$(dirname "$0")" && pwd)
# shellcheck disable=SC1091
. "$HERE/lib-testrun.sh" || { echo "worktree-cleanup: lib-testrun.sh missing" >&2; exit 2; }

WT=${1:-}
[ -n "$WT" ] && [ -d "$WT" ] || { echo "usage: worktree-cleanup.sh <worktree>" >&2; exit 2; }
WT=$(cd "$WT" && git rev-parse --show-toplevel 2>/dev/null) || { echo "worktree-cleanup: refused, $1 is not a git checkout" >&2; exit 1; }
WT=$(cd "$WT" && pwd -P)
refuse() { echo "worktree-cleanup: refused, $1 ($WT)" >&2; exit 1; }

GIT_DIR=$(git -C "$WT" rev-parse --path-format=absolute --git-dir 2>/dev/null)
COMMON=$(git -C "$WT" rev-parse --path-format=absolute --git-common-dir 2>/dev/null)
[ -n "$GIT_DIR" ] && [ "$GIT_DIR" != "$COMMON" ] || refuse "this is the main checkout"
[ -z "$(git -C "$WT" status --porcelain 2>/dev/null)" ] || refuse "uncommitted changes"
AHEAD=$(git -C "$WT" rev-list --count HEAD --not --remotes 2>/dev/null || echo 1)
[ "$AHEAD" = 0 ] || refuse "$AHEAD commit(s) are not on any remote"
BRANCH=$(git -C "$WT" branch --show-current 2>/dev/null)
MAIN=$(dirname "$COMMON")

inside() { case "$1/" in "$WT"/*) return 0 ;; esac; return 1; }

# 1. run tickets of this worktree
for id in $(_tr_live_ids); do
  f=$(_tr_ticket "$id")
  cwd=$(_tr_field cwd "$f")
  inside "$(cd "$cwd" 2>/dev/null && pwd -P || echo "$cwd")" || continue
  g=$(_tr_field pgid "$f")
  [ -n "$g" ] && tr_kill_tree "$g" worktree-cleanup
  tr_release "$id"
done

# 2. orphans (parent 1) whose cwd is in the worktree, by their group
for pid in $(ps -ax -o pid=,ppid= 2>/dev/null | awk '$2 == 1 { print $1 }'); do
  c=$(_tr_cwd "$pid"); [ -n "$c" ] || continue
  inside "$(cd "$c" 2>/dev/null && pwd -P || echo "$c")" || continue
  tr_kill_orphan "$pid" worktree-cleanup-orphan
done

tr_worktree_cleanup "$WT"

cd "$MAIN" 2>/dev/null || cd / || exit 1
git -C "$MAIN" worktree remove "$WT" >/dev/null 2>&1 || git -C "$MAIN" worktree remove --force "$WT" >/dev/null 2>&1 \
  || { echo "worktree-cleanup: refused, git could not remove the worktree ($WT)" >&2; exit 1; }
kept=""
if [ -n "$BRANCH" ]; then
  if ! git -C "$MAIN" branch -d "$BRANCH" >/dev/null 2>&1; then
    if [ -n "$(git -C "$MAIN" branch -r --contains "refs/heads/$BRANCH" 2>/dev/null)" ]; then
      git -C "$MAIN" branch -D "$BRANCH" >/dev/null 2>&1
    else
      kept=", branch $BRANCH kept"
    fi
  fi
fi
[ -d "$WT" ] && rm -rf "$WT"   # ignored leftovers (vendor, build output) git leaves behind
echo "worktree-cleanup: removed $WT${BRANCH:+ (branch $BRANCH)}$kept"
