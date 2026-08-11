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

# Recognize `$(which git)` / `` `which git` `` as a stand-in for the literal
# `git` binary before any other matching happens. Both resolve to the git
# binary at runtime exactly like a bare `git` word does, but the
# anchor/wrapper/binpath grammar below only recognizes `git` as literal
# text, and the parens/backticks around the resolver call are ordinary
# characters to this single-grep guard (it does not segment the command
# the way block-worktree-wide-git.sh does), so `$(which git) push` sat
# between an unmatched `$(` and the anchor never found a `git` word
# adjacent to `push` on the string's own terms. Substituting the whole
# resolver expression for a literal `git` closes that gap. Only the exact
# `which git` idiom is recognized (the reproduced bypass); `command -v
# git` / `type -p git` are a further extension of the same idea, not
# covered here.
cmd=$(printf '%s' "$cmd" | sed -E 's/(\$\(|`)[[:space:]]*which[[:space:]]+git[[:space:]]*(\)|`)/git/g')

# Anchor on `git` in COMMAND POSITION rather than matching it as a bare word
# anywhere: a plain \b<git>\b also fires inside quoted text and arguments
# (`grep -rn "git push" docs/`, `echo "remember to git push later"`), which
# is an over-block, not a safety margin. A command position is: start of
# string, a chain operator (&&, ;, |, &), a subshell/brace-group opener
# (`(`, `{`), a backtick (legacy command substitution, `` `git push` `` and
# `` RESULT=`git reset --hard` `` both open with a bare backtick -- no space
# and no other anchor char precedes it, so the backtick itself has to be a
# self-sufficient anchor), a control-flow keyword (then, do, else), or a
# bare `!` (negation: `if ! git push; then ...`, `while ! git push; do
# sleep 1; done` -- `!` is a self-sufficient anchor for the same reason as
# the backtick, since whatever precedes it, e.g. `if`/`while`, is not
# itself in the anchor set and does not need to be for the match to
# succeed) -- optionally followed by zero or more WRAPPER tokens (see
# below) and a path to the binary (absolute or relative). That
# reconstructs every round-1 bypass shape (`FOO=bar git push`, `(git
# push)`, `{ git push; }`, `if true; then git push; fi`, `for i in 1; do
# git push; done`, `/usr/bin/git push`, `sleep 1 & git push`, `git
# --git-dir=.git push`) plus the round-3 backtick bypass, without matching
# `git` as text.
#
# WRAPPER covers ordinary command prefixes that keep `git` in command
# position: `time`, `command`, `env`, `sudo`, `nohup`, `xargs`, and
# `NAME=value` env assignments -- each may repeat and combine in any order
# (`sudo env FOO=1 git push`, `time git push`). `xargs` belongs here even
# though `sh -c`/`bash -c`/`eval` do not: `xargs git push` hands xargs the
# literal argv words "git" "push" to execute directly, there is no
# intermediate string for a shell to interpret, so a static pattern can
# safely treat it exactly like `sudo` or `env`. This is a static regex,
# not a shell parser: it does not track quote state or parse `sh -c`/`eval`
# argument boundaries, so WRAPPER deliberately excludes that
# string-interpreting wrapper class (`sh -c`, `bash -c`, `eval`) -- the
# hook receives the whole command string, so `sh -c 'git push'` IS visible
# to this pattern as text; what a static regex cannot do is decide whether
# that text will be executed as a command or is an inert string. The
# guard's threat model is an ordinary fix agent following instructions,
# not an adversary obfuscating a command through a string-eval layer.
#
# Matching is case-insensitive (grep -i): this machine's boot volume is
# case-insensitive APFS, so the git BINARY resolves under any casing
# (`GIT`, `Git`, `git`). Git SUBCOMMANDS, by contrast, are case-sensitive --
# `GIT PUSH` fails outright ("cannot handle PUSH as a builtin") and never
# pushes -- so the only real bypass shape is an uppercase/mixed-case binary
# with a lowercase subcommand (`GIT push`, `Git push`). Case-insensitive
# matching catches the binary-casing variation regardless of subcommand
# case, which safely covers the real bypass without depending on the
# subcommand's own case.
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
# missed push. Workaround: rephrase the message without backticks. The
# bare-`!` anchor above is the same class of tradeoff and accepted for the
# same reason. The same quote-state limitation also applies to the
# `then`/`do`/`else` anchors themselves: `git commit -m "we do git push
# later"` raises an unnecessary "ask" because `\bdo\b` matches inside the
# quoted message. Removing those keywords from GIT_ANCHOR would reopen the
# real bypass they exist for (`for i in 1; do git push; done`), so this is
# accepted for the same reason as the backtick/`!` cases: prefer an extra
# confirmation prompt over a missed push.
#
# `-exec`/`-execdir` (find's action flags) are also a real command
# position: `find . -exec git push \;` hands the following words to
# exec(3) as a literal argv, exactly like xargs does -- there is no
# intermediate shell to interpret them. Ordinary bulk-operation shape for a
# fix agent, not adversarial obfuscation, so it belongs in the anchor set
# (shared, byte-identical with block-worktree-wide-git.sh).
#
# WRAPPER additionally tolerates flags on `xargs` itself (`xargs -n1 git
# push`): the previous grammar only matched bare `xargs` followed
# immediately by whitespace, so any flag between `xargs` and `git` fell
# through unmatched. Flags are zero or more dash-prefixed tokens directly
# after `xargs`.
#
# BIN_PATH additionally tolerates one leading backslash before `git`
# (`\git push`, a common way to skip an alias/shell function and invoke
# the binary directly -- no string-interpretation layer involved, so it is
# the same static-text-visible prefix class as `/usr/bin/git`).
GIT_ANCHOR='(^|&&|;|\||&|\(|\{|`|\bthen\b|\bdo\b|\belse\b|!|-exec\b|-execdir\b)\s*'
WRAPPER='(\b(time|command|env|sudo|nohup)\b\s+|\bxargs\b(\s+-\S+)*\s+|[A-Za-z_][A-Za-z0-9_]*=\S*\s+)*'
BIN_PATH='\\?(\S*/)?'
OPTS='(-C\s+\S+\s+|--git-dir=\S+\s+|--work-tree=\S+\s+|(-[A-Za-z]|--[a-z-]+)(=\S+)?(\s+\S+)?\s+)*'
if ! echo "$cmd" | grep -qiE "${GIT_ANCHOR}${WRAPPER}${BIN_PATH}git\s+${OPTS}push"; then
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
