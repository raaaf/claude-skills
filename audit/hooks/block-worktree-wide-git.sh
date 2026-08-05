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
#   2 — hard block the tool call (surfaced to Claude via stderr); anything
#       other than 2 is a non-blocking error per the PreToolUse hook docs,
#       so this MUST stay 2, not 1.
set -euo pipefail

input=$(cat)
cmd=$(echo "$input" | jq -r '.tool_input.command')

# Anchor on `git` in COMMAND POSITION rather than matching it as a bare word
# anywhere: a plain \b<git>\b also fires inside quoted text and arguments
# (`grep -rn "git reset" docs/`, `echo "git stash" >> notes.md`), which is
# an over-block, not a safety margin. A command position is: start of
# string, a chain operator (&&, ;, |, &), a subshell/brace-group opener
# (`(`, `{`), a backtick (legacy command substitution, `` `git push` `` and
# `` RESULT=`git reset --hard` `` both open with a bare backtick -- no space
# and no other anchor char precedes it, so the backtick itself has to be a
# self-sufficient anchor), or a control-flow keyword (then, do, else) --
# optionally followed by one or more `NAME=value` env assignments and a path
# to the binary (absolute or relative). That reconstructs every round-1
# bypass shape (`FOO=bar git push`, `(git push)`, `{ git push; }`,
# `if true; then git push; fi`, `for i in 1; do git push; done`,
# `/usr/bin/git push`, `sleep 1 & git push`) plus the round-3 backtick
# bypass, without matching `git` as text. This is a static regex, not a
# shell parser: it does not track quote state or parse `sh -c`/`eval`
# argument boundaries, so the anchor set above does not include the wrapper
# class (`sh -c`, `bash -c`, `eval`, `xargs`) as command-position openers --
# that is a deliberate scope decision, not because the text is invisible.
# The hook receives the whole command string, so `sh -c 'git push'` IS
# visible to this pattern as text; what a static regex cannot do is decide
# whether that text will be executed as a command or is an inert string.
# The guard's threat model is an ordinary fix agent following instructions,
# not an adversary obfuscating a command through a string-eval layer.
#
# Matching is case-insensitive (grep -i) throughout: this machine's boot
# volume is case-insensitive APFS, so the git BINARY resolves under any
# casing (`GIT`, `Git`, `git`). Git SUBCOMMANDS, by contrast, are
# case-sensitive -- `GIT PUSH` fails outright ("cannot handle PUSH as a
# builtin") and never runs -- so the only real bypass shape is an
# uppercase/mixed-case binary with a lowercase subcommand (`GIT push`,
# `Git push`). Case-insensitive matching catches the binary-casing
# variation regardless of subcommand case, which safely covers the real
# bypass without depending on the subcommand's own case.
#
# Accepted, not fixed (round 3, Finding 3): `echo "$cmd" | grep` feeds a
# multi-line command to grep line-by-line, so `^` in GIT_ANCHOR matches the
# start of EVERY physical line, not just the start of the logical command.
# A harmless `git commit -m "line1\nline2 mentions git reset --hard"` can
# hard-block on line 2 even though that text is inside a quoted message
# body. The only portable (bash 3.2 / BSD grep, no -Pz) fix is squashing
# newlines to spaces before matching, but that blurs real chain-operator
# boundaries and risks a NEW under-block: a backslash-continued multi-line
# destructive command (`git \` / `  reset --hard`) would squash into
# `git \ reset --hard`, where `\` breaks the OPTS match and the command
# slips through uncaught. An occasional false positive on a multi-line -m
# message (workaround: single-line message, or `-F <file>`) is preferable
# to opening a new bypass surface, so this guard deliberately stays
# fail-closed and over-blocks that rare case.
#
# Accepted, not fixed (backtick anchor false positive): the backtick was
# added to GIT_ANCHOR so real command substitution (`` `git reset --hard` ``)
# gets caught, but a regex cannot tell an opening backtick from one that
# sits inertly inside a single-quoted argument -- a commit message like
# `git commit -m 'see `git reset --hard` in the docs for danger'` hard-blocks
# even though that backtick never starts real substitution. Distinguishing
# an inert backtick from a live one needs quote-state tracking, which a
# single regex cannot do. Accepted because the failure direction is always
# a false block, never a missed destructive command. Workaround: rephrase
# the message without backticks.
GIT_ANCHOR='(^|&&|;|\||&|\(|\{|`|\bthen\b|\bdo\b|\belse\b)\s*'
ENV_ASSIGN='([A-Za-z_][A-Za-z0-9_]*=\S*\s+)*'
BIN_PATH='(\S*/)?'
OPTS='(-C\s+\S+\s+|--git-dir=\S+\s+|--work-tree=\S+\s+|(-[A-Za-z]|--[a-z-]+)(=\S+)?(\s+\S+)?\s+)*'
PREFIX="${GIT_ANCHOR}${ENV_ASSIGN}${BIN_PATH}git\s+${OPTS}"

BLOCKED=0
# `git stash list` / `git stash show` are read-only inspection, not a
# working-tree mutation -- exempt only those two, keep every mutating stash
# form (bare, push, pop, apply, drop, clear, save, create, store) blocked.
if echo "$cmd" | grep -qiE "${PREFIX}stash\b"; then
  if ! echo "$cmd" | grep -qiE "${PREFIX}stash\s+(list|show)\b"; then
    BLOCKED=1
  fi
fi
if echo "$cmd" | grep -qiE "${PREFIX}restore\b"; then BLOCKED=1; fi
if echo "$cmd" | grep -qiE "${PREFIX}reset\b"; then BLOCKED=1; fi
if echo "$cmd" | grep -qiE "${PREFIX}clean\b"; then BLOCKED=1; fi
if echo "$cmd" | grep -qiE "${PREFIX}revert\b"; then BLOCKED=1; fi
# Any `checkout` is destructive-by-pathspec or branch-switch risk EXCEPT
# `-b <new-branch>` (creates a new branch, touches nothing existing).
if echo "$cmd" | grep -qiE "${PREFIX}checkout\b"; then
  if ! echo "$cmd" | grep -qiE "${PREFIX}checkout\s+(\S+\s+)*-b(\s|=|\$)"; then
    BLOCKED=1
  fi
fi

if [ "$BLOCKED" -eq 0 ]; then
  exit 0
fi

echo 'BLOCKED: Worktree-weite destruktive Git-Befehle (git stash/checkout/restore/reset/clean/revert) sind hier nicht erlaubt. Mehrere Agents teilen sich denselben Working Tree -- so ein Befehl kann fremde, noch ungesicherte Aenderungen zerstoeren. Das ist dem Orchestrator vorbehalten, der das bewusst sequenziert. Read-only Git (git diff, git status, git show, git log) bleibt erlaubt. `git checkout -b <neuer-branch>` bleibt erlaubt.' >&2
exit 2
