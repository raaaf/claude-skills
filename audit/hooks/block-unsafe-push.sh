#!/usr/bin/env bash
#
# PreToolUse hook for the /audit skill.
#
# Blocks `git push` invocations unless a recent audit-passed marker exists for
# the current working directory. The marker is written by the /audit skill
# itself when an audit run completes cleanly and is valid for 30 minutes.
#
# Input: Claude Code PreToolUse hook payload on stdin (JSON with
# `tool_input.command` and `cwd`).
#
# This guard never hard-blocks (its message asks Claude to consult the user
# first, which exit 2 cannot express -- exit 2 denies outright with no way
# back). Instead it mirrors the pattern ~/.claude/settings.json already uses
# for the same `git push` case: print a JSON object with
# hookSpecificOutput.permissionDecision "ask" to stdout and exit 0, which
# makes Claude Code prompt the user instead of blocking or silently
# proceeding.
#
# Exit codes:
#   0 — always (allow, or allow-with-a-relayed-"ask"-prompt via stdout JSON)
set -euo pipefail

input=$(cat)
cmd=$(echo "$input" | jq -r '.tool_input.command')

# Anchor on `git` in COMMAND POSITION rather than matching it as a bare word
# anywhere: a plain \b<git>\b also fires inside quoted text and arguments
# (`grep -rn "git push" docs/`, `echo "remember to git push later"`), which
# is an over-block, not a safety margin. A command position is: start of
# string, a chain operator (&&, ;, |, &), a subshell/brace-group opener
# (`(`, `{`), a backtick (legacy command substitution, `` `git push` `` and
# `` RESULT=`git reset --hard` `` both open with a bare backtick -- no space
# and no other anchor char precedes it, so the backtick itself has to be a
# self-sufficient anchor), or a control-flow keyword (then, do, else) --
# optionally followed by one or more `NAME=value` env assignments and a path
# to the binary (absolute or relative). That reconstructs every round-1
# bypass shape (`FOO=bar git push`, `(git push)`, `{ git push; }`,
# `if true; then git push; fi`, `for i in 1; do git push; done`,
# `/usr/bin/git push`, `sleep 1 & git push`, `git --git-dir=.git push`) plus
# the round-3 backtick bypass, without matching `git` as text. This is a
# static regex, not a shell parser: it cannot and does not try to see into
# `sh -c '...'` or `eval '...'` payloads -- the guard's threat model is an
# ordinary fix agent following instructions, not an adversary obfuscating a
# command through a string-eval layer.
#
# Matching is case-insensitive (grep -i): this machine's boot volume is
# case-insensitive APFS, so `GIT PUSH` / `Git Push` resolve to the same real
# git binary as `git push` and must be caught identically, not just the
# lowercase spelling.
#
# Accepted, not fixed (round 3, Finding 3): `echo "$cmd" | grep` feeds a
# multi-line command to grep line-by-line, so `^` in GIT_ANCHOR matches the
# start of EVERY physical line, not just the start of the logical command.
# A harmless multi-line commit message can in principle trip this the same
# way it can trip block-worktree-wide-git.sh, though this guard only
# hard-blocks `push`, so the practical exposure here is smaller. Squashing
# newlines before matching (the only portable, bash 3.2 / BSD-grep-safe
# alternative to -Pz) would blur real chain-operator boundaries and risks a
# NEW under-block for backslash-continued multi-line `git ... push`
# invocations. Same call as the sibling guard: stay fail-closed, accept the
# rare over-block, see block-worktree-wide-git.sh for the full reasoning.
#
# Accepted, not fixed (backtick anchor false positive): the backtick was
# added to GIT_ANCHOR so real command substitution (`` `git push` ``) gets
# caught, but a regex cannot tell an opening backtick from one that sits
# inertly inside a single-quoted argument -- a commit message like
# `git commit -m 'see `git reset --hard` in the docs for danger'` raises an
# unnecessary "ask" here even though that backtick never starts real
# substitution. Distinguishing an inert backtick from a live one needs
# quote-state tracking, which a single regex cannot do. Accepted because
# the failure direction is always an extra confirmation prompt, never a
# missed push. Workaround: rephrase the message without backticks.
GIT_ANCHOR='(^|&&|;|\||&|\(|\{|`|\bthen\b|\bdo\b|\belse\b)\s*'
ENV_ASSIGN='([A-Za-z_][A-Za-z0-9_]*=\S*\s+)*'
BIN_PATH='(\S*/)?'
OPTS='(-C\s+\S+\s+|--git-dir=\S+\s+|--work-tree=\S+\s+|(-[A-Za-z]|--[a-z-]+)(=\S+)?(\s+\S+)?\s+)*'
if ! echo "$cmd" | grep -qiE "${GIT_ANCHOR}${ENV_ASSIGN}${BIN_PATH}git\s+${OPTS}push"; then
  exit 0
fi

cwd=$(echo "$input" | jq -r '.cwd')
hash=$(echo -n "$cwd" | md5 2>/dev/null || echo -n "$cwd" | md5sum 2>/dev/null | cut -d' ' -f1)
marker="/tmp/claude-audit-passed-$hash"

# Marker valid for 30 minutes (1800 s). If fresh, allow the push.
# Do NOT delete the marker here — multiple hooks may check the same marker
# sequentially. The marker expires via TTL (30 min) and is harmless after that.
marker_mtime=$(stat -f%m "$marker" 2>/dev/null || stat -c%Y "$marker" 2>/dev/null || echo 0)
if [ "$marker_mtime" -gt 0 ] && [ $(( $(date +%s) - marker_mtime )) -lt 1800 ]; then
  exit 0
fi

printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"ask","permissionDecisionReason":"Kein /audit-Marker vorhanden (oder aelter als 30 Min). Vor dem Push wurde kein /audit ausgefuehrt. Soll ich den Audit jetzt starten, oder direkt pushen?"}}\n'
exit 0
