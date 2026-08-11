#!/usr/bin/env bash
#
# PreToolUse guard for the batch-fix runner: blocks destructive git commands
# (git stash, git checkout -- <path>, git reset, git clean, git revert) while
# an automated fix pass is writing to the shared working tree. Read-only
# inspection commands (git status, git diff, git log, git stash list/show,
# git checkout -b <new-branch>) stay allowed so an agent can still orient
# itself before deciding what to run next.
#
# Input: PreToolUse hook payload on stdin (JSON with tool_input.command).
# Exit codes: 0 = allow, 2 = block (PreToolUse only treats exit 2 as
# blocking; every other non-zero code is a non-blocking error).
set -euo pipefail

input=$(cat)
cmd=$(echo "$input" | jq -r '.tool_input.command')

# Read-only / safe forms pass straight through without touching the
# destructive check below.
READONLY_RE='git[[:space:]]+(status|diff|log|show)\b|stash[[:space:]]+(list|show)\b|checkout[[:space:]]+-b\b'
if echo "$cmd" | grep -qiE "$READONLY_RE"; then
  exit 0
fi

# Anything that mutates the working tree in bulk gets blocked.
DESTRUCTIVE_RE='git[[:space:]]+(stash\b|checkout[[:space:]]+--|reset\b|clean\b|revert\b)'
if echo "$cmd" | grep -qiE "$DESTRUCTIVE_RE"; then
  echo 'BLOCKED: destructive git command not allowed during an automated fix run.' >&2
  exit 2
fi

exit 0
