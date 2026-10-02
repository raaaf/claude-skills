#!/usr/bin/env bash
#
# Pins orch_review_worktree_create/remove (2026-10-02): the audit scope (commits since BASE_REF, uncommitted
# changes, new untracked files) shows up as an UNCOMMITTED diff in a temporary worktree at BASE_REF; the
# user's tree stays as it was; remove leaves no worktree entry.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
. "$SCRIPT_DIR/lib-orchestrator.sh"

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
export TMPDIR="$TMP/tmp"; mkdir -p "$TMPDIR"
export GIT_CONFIG_GLOBAL="$TMP/gitconfig"
git config --global user.email t@t; git config --global user.name t; git config --global init.defaultBranch main

expect() {
  local got="$1" expected="$2" label="$3"
  [[ "$got" == "$expected" ]] || { printf 'FAIL %s\nExpected: %s\nGot: %s\n' "$label" "$expected" "$got" >&2; exit 1; }
  printf 'PASS %s\n' "$label"
}

R="$TMP/repo"; git init -q "$R"; cd "$R"
printf 'one\n' > a.txt; printf 'two\n' > b.txt; printf 'ignored.log\n' > .gitignore
git add -A; git commit -qm base
BASE=$(git rev-parse HEAD)
printf 'one changed\n' > a.txt; git commit -qam committed          # committed change since base
printf 'two changed\n' > b.txt                                      # uncommitted tracked change
printf 'new\n' > c.txt; printf 'x\n' > ignored.log; printf 'out\n' > outside.txt   # untracked, ignored, untracked out of scope
BEFORE=$(git status --porcelain; git rev-parse HEAD)

WT=$(orch_review_worktree_create "$BASE" $'a.txt\nb.txt\nc.txt')
expect "$(git -C "$WT" rev-parse HEAD)" "$BASE" 'worktree sits at BASE_REF'
expect "$(git -C "$WT" diff --name-only | tr '\n' ' ')" 'a.txt b.txt c.txt ' 'committed, uncommitted and untracked files all show as uncommitted diff'
expect "$(git -C "$WT" diff -- a.txt | grep -c '^+one changed')" '1' 'the committed change is applied as content'
expect "$(git -C "$WT" diff --cached --name-only | tr '\n' ' ')" '' 'nothing is staged for real'
expect "$([ -e "$WT/ignored.log" ] || [ -e "$WT/outside.txt" ] && echo present || echo absent)" 'absent' 'ignored and out-of-scope untracked files are not copied'
expect "$(git status --porcelain; git rev-parse HEAD)" "$BEFORE" "the user's tree is unchanged"
orch_review_worktree_remove "$WT"
expect "$(git worktree list | wc -l | tr -d ' ')" '1' 'remove leaves no worktree entry'
expect "$([ -e "$WT" ] && echo present || echo gone)" 'gone' 'remove deletes the directory'

WT2=$(orch_review_worktree_create "$BASE")
expect "$(git -C "$WT2" diff --name-only | tr '\n' ' ')" 'a.txt b.txt c.txt outside.txt ' 'no scope list: the whole tree'
orch_review_worktree_remove "$WT2"
