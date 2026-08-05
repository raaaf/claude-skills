#!/usr/bin/env bash
#
# PreToolUse dispatcher for the /audit skill's Bash guards.
#
# Registered as the single PreToolUse/Bash hook entry in SKILL.md
# frontmatter. stdin carries the tool payload and is single-consumption
# (each guard does `input=$(cat)`), so wiring both guards up as two separate
# hook entries would hand the second guard an empty pipe. This script reads
# stdin exactly once and re-feeds the identical payload to each guard via
# its own stdin. It finds its siblings via `dirname "$0"` -- the path
# Claude Code invokes this dispatcher at -- so no install-path probe is
# needed here (SKILL.md still probes once, to locate this dispatcher).
#
# Aggregation rule:
#   1. block-worktree-wide-git.sh runs first. It is the hard-deny guard:
#      exit 2 means block immediately, its stderr is relayed verbatim, and
#      the second guard does not run.
#   2. block-unsafe-push.sh runs otherwise. It never hard-blocks; it exits 0
#      either silently (allow) or with a JSON permissionDecision:"ask"
#      object on stdout, which is relayed verbatim so Claude Code prompts
#      the user.
#   3. A missing sibling script is skipped (treated as allow) -- a partial
#      or broken install must fail OPEN, not block every Bash call.
#
# Exit codes: 0 allow (stdout may carry an "ask" JSON object), 2 hard block
# (stderr carries the reason).
set -uo pipefail

DIR="$(cd "$(dirname "$0")" && pwd)"
input=$(cat)

WORKTREE_GUARD="$DIR/block-worktree-wide-git.sh"
PUSH_GUARD="$DIR/block-unsafe-push.sh"

if [ -f "$WORKTREE_GUARD" ]; then
  err=$(printf '%s' "$input" | bash "$WORKTREE_GUARD" 2>&1 1>/dev/null)
  rc=$?
  if [ "$rc" -eq 2 ]; then
    printf '%s\n' "$err" >&2
    exit 2
  fi
fi

if [ -f "$PUSH_GUARD" ]; then
  out=$(printf '%s' "$input" | bash "$PUSH_GUARD")
  if [ -n "$out" ]; then
    printf '%s\n' "$out"
  fi
fi

exit 0
