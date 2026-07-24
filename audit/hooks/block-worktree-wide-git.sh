#!/usr/bin/env bash
#
# PreToolUse hook for the /audit skill.
#
# Blocks worktree-wide destructive git commands: git stash (any subcommand),
# git checkout --, git restore, git reset, git clean, git revert. Fix agents
# run in PARALLEL in ONE shared working tree that holds every sibling
# agent's uncommitted work -- any of these commands can silently destroy
# another agent's fix (2026-07-22: a fix agent's `git stash` + `git stash
# pop` wiped a sibling's only Critical fix and still reported APPLIED).
# Reserved for the orchestrator, which sequences worktree-wide git
# deliberately.
#
# Input: Claude Code PreToolUse hook payload on stdin (JSON with
# `tool_input.command` and `cwd`).
#
# Exit codes:
#   0 — allow the tool call (no matching git command detected)
#   1 — block the tool call and surface the stderr message to Claude
set -euo pipefail

input=$(cat)
cmd=$(echo "$input" | jq -r '.tool_input.command')

# Shared prefix: `git`, chained or not (`foo && git reset --hard`), with any
# global options before the subcommand -- including `git -C <path> ...`,
# `--git-dir=`, `--work-tree=`.
PREFIX='(^|&&|;|\|)\s*git\s+(-C\s+\S+\s+|--git-dir=\S+\s+|--work-tree=\S+\s+|(-[A-Za-z]|--[a-z-]+)(=\S+)?(\s+\S+)?\s+)*'

BLOCKED=0
if echo "$cmd" | grep -qE "${PREFIX}stash\b"; then BLOCKED=1; fi
if echo "$cmd" | grep -qE "${PREFIX}restore\b"; then BLOCKED=1; fi
if echo "$cmd" | grep -qE "${PREFIX}reset\b"; then BLOCKED=1; fi
if echo "$cmd" | grep -qE "${PREFIX}clean\b"; then BLOCKED=1; fi
if echo "$cmd" | grep -qE "${PREFIX}revert\b"; then BLOCKED=1; fi
if echo "$cmd" | grep -qE "${PREFIX}checkout\s+(\S+\s+)*--(\s|\$)"; then BLOCKED=1; fi

if [ "$BLOCKED" -eq 0 ]; then
  exit 0
fi

echo 'BLOCKED: Worktree-weite destruktive Git-Befehle (git stash/checkout --/restore/reset/clean/revert) sind hier nicht erlaubt. Mehrere Agents teilen sich denselben Working Tree -- so ein Befehl kann fremde, noch ungesicherte Aenderungen zerstoeren. Das ist dem Orchestrator vorbehalten, der das bewusst sequenziert. Read-only Git (git diff, git status, git show, git log) bleibt erlaubt.' >&2
exit 1
