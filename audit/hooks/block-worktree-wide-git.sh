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
# self-sufficient anchor), a control-flow keyword (then, do, else), or a
# bare `!` (negation: `if ! git push; then ...`, `while ! git push; do
# sleep 1; done` -- `!` is a self-sufficient anchor for the same reason as
# the backtick, since whatever precedes it, e.g. `if`/`while`, is not
# itself in the anchor set and does not need to be for the match to
# succeed) -- optionally followed by zero or more WRAPPER tokens (see
# below) and a path to the binary (absolute or relative). That
# reconstructs every round-1 bypass shape (`FOO=bar git push`, `(git
# push)`, `{ git push; }`, `if true; then git push; fi`, `for i in 1; do
# git push; done`, `/usr/bin/git push`, `sleep 1 & git push`) plus the
# round-3 backtick bypass, without matching `git` as text.
#
# WRAPPER covers ordinary command prefixes that keep `git` in command
# position: `time`, `command`, `env`, `sudo`, `nohup`, `xargs`, and
# `NAME=value` env assignments -- each may repeat and combine in any order
# (`sudo env FOO=1 git push`, `time git reset --hard`). `xargs` belongs
# here even though `sh -c`/`bash -c`/`eval` do not: `xargs git push` hands
# xargs the literal argv words "git" "push" to execute directly, there is
# no intermediate string for a shell to interpret, so a static pattern can
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
# the message without backticks. The bare-`!` anchor above is the same
# class of tradeoff: `!` inside a quoted argument (`git commit -m "no! git
# reset is not what I meant"`) can anchor a false match for the same
# quote-state reason, accepted for the same reason -- both are deliberate:
# this guard's policy is to prefer a false block over a missed destructive
# command. The backtick is now ALSO a segment-split delimiter (see
# "Per-occurrence evaluation" below), so the example above is split into
# its own segment too; the false block still happens, just via that
# segment's `^` anchor instead of the backtick's own GIT_ANCHOR entry --
# the observable behavior of this tradeoff is unchanged.
#
# Per-occurrence evaluation (stash/checkout exemptions): the stash and
# checkout checks below each carry an exemption (`stash list`/`stash
# show`, `checkout -b`). Testing the exemption against the WHOLE command
# string was itself a bypass: `git stash list && git stash pop` contains a
# read-only `stash list`, so a whole-string "is there a list/show
# anywhere" check disarmed the guard for the mutating `stash pop` right
# next to it -- the exact shape of the 2026-07-22 incident this guard
# exists to prevent. The same bypass shape exists via command/process
# substitution: `git stash pop $(git stash list)` embeds a read-only
# `stash list` in the SAME segment as the mutating `stash pop` unless the
# substitution itself becomes a segment boundary. Each command is
# therefore split into segments on the chain operators `&`, `|`, `;`
# (which also splits `&&`/`||` into two operators, leaving one harmless
# empty segment between them), on `(` and `)` (which also covers `$(`,
# `<(` and `>(` -- the distinguishing `$`/`<`/`>` character just trails
# onto the adjacent segment, harmlessly, since none of those three are a
# GIT_ANCHOR anchor character), on the backtick (legacy substitution), plus
# real newlines. Every check below runs once per segment instead of once
# per whole command, so a mutating occurrence is caught even when a
# read-only occurrence of the same subcommand sits elsewhere in the same
# line or is nested in a substitution embedded in it. A stray operator or
# paren character inside a quoted argument can create an extra, harmless
# empty segment, but it never merges two real segments into one, so it
# cannot hide a mutating occurrence behind a read-only one. A git command
# that legitimately opens a bare subshell (e.g. `(git reset --hard)`)
# still gets caught after the split: the text right after the removed `(`
# becomes the START of a new segment, matched via the `^` alternative in
# GIT_ANCHOR instead of the `\(` alternative. GIT_ANCHOR itself keeps `\(`
# and the backtick unchanged (shared, byte-identical with
# block-unsafe-push.sh) -- that guard does not split segments and still
# needs them as in-string anchors.
GIT_ANCHOR='(^|&&|;|\||&|\(|\{|`|\bthen\b|\bdo\b|\belse\b|!)\s*'
WRAPPER='(\b(time|command|env|sudo|nohup|xargs)\b\s+|[A-Za-z_][A-Za-z0-9_]*=\S*\s+)*'
BIN_PATH='(\S*/)?'
OPTS='(-C\s+\S+\s+|--git-dir=\S+\s+|--work-tree=\S+\s+|(-[A-Za-z]|--[a-z-]+)(=\S+)?(\s+\S+)?\s+)*'
PREFIX="${GIT_ANCHOR}${WRAPPER}${BIN_PATH}git\s+${OPTS}"

BLOCKED=0
while IFS= read -r seg; do
  [ -z "$seg" ] && continue
  if echo "$seg" | grep -qiE "${PREFIX}restore\b"; then BLOCKED=1; fi
  if echo "$seg" | grep -qiE "${PREFIX}reset\b"; then BLOCKED=1; fi
  if echo "$seg" | grep -qiE "${PREFIX}clean\b"; then BLOCKED=1; fi
  if echo "$seg" | grep -qiE "${PREFIX}revert\b"; then BLOCKED=1; fi
  # `git stash list` / `git stash show` are read-only inspection, not a
  # working-tree mutation -- exempt only those two, keep every mutating
  # stash form (bare, push, pop, apply, drop, clear, save, create, store)
  # blocked. Evaluated per segment, see "Per-occurrence evaluation" above.
  if echo "$seg" | grep -qiE "${PREFIX}stash\b"; then
    if ! echo "$seg" | grep -qiE "${PREFIX}stash\s+(list|show)\b"; then
      BLOCKED=1
    fi
  fi
  # Any `checkout` is destructive-by-pathspec or branch-switch risk EXCEPT
  # `-b <new-branch>` (creates a new branch, touches nothing existing).
  # The exemption is anchored to an actual option position -- only
  # dash-prefixed option tokens (`-[A-Za-z]` or `--[a-z-]+`, same shape as
  # OPTS above; a bare `--` pathspec separator does not qualify) may
  # precede `-b` -- so a `-b` sitting in a trailing comment or in a
  # pathspec after `--` no longer exempts the command (`git checkout main
  # # use -b next time` now blocks). The exemption check is also
  # case-SENSITIVE (no `-i`), unlike the rest of this file: `-B`
  # force-moves an EXISTING branch and is destructive, unlike `-b` which
  # only creates a new one, so it must never be treated as the same safe
  # form -- a case-insensitive match would let `-B` through as if it were
  # `-b`. Evaluated per segment, see "Per-occurrence evaluation" above.
  if echo "$seg" | grep -qiE "${PREFIX}checkout\b"; then
    if ! echo "$seg" | grep -qE "${PREFIX}checkout\s+((-[A-Za-z]|--[a-z-]+)\s+)*-b(\s|=|\$)"; then
      BLOCKED=1
    fi
  fi
  # `git switch -f`/`--force` discards local changes when switching
  # branches -- the same class of destruction as the already-blocked `git
  # checkout -f`. Plain `git switch <branch>` (no force) only moves HEAD
  # and is non-destructive, so it stays allowed; only the force flag
  # blocks. Evaluated per segment, see "Per-occurrence evaluation" above.
  if echo "$seg" | grep -qiE "${PREFIX}switch\s+(\S+\s+)*(-f|--force)\b"; then
    BLOCKED=1
  fi
done <<<"$(printf '%s' "$cmd" | tr '&|;()`' '\n\n\n\n\n\n')"

if [ "$BLOCKED" -eq 0 ]; then
  exit 0
fi

echo 'BLOCKED: Worktree-weite destruktive Git-Befehle (git stash/checkout/switch/restore/reset/clean/revert) sind hier nicht erlaubt. Mehrere Agents teilen sich denselben Working Tree -- so ein Befehl kann fremde, noch ungesicherte Aenderungen zerstoeren. Das ist dem Orchestrator vorbehalten, der das bewusst sequenziert. Read-only Git (git diff, git status, git show, git log) bleibt erlaubt. `git checkout -b <neuer-branch>` und `git switch <branch>` (ohne --force) bleiben erlaubt.' >&2
exit 2
