#!/usr/bin/env bash
# Tests for orch_tidy_branches in lib-orchestrator.sh (oracle-mode tests, written from the contract).
# Every case builds its own fixture in a temp dir: a bare repo as origin plus a clone as the work repo.
# No real repo is touched; HOME points into the temp dir.
# Each case also asserts the function is read-only: branch list, status and all refs (so no fetch)
# are identical before and after, and the return code is 0.
# Usage: bash audit/bin/orch-tidy-branches.test.sh
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
TMP="$(cd "$(mktemp -d "${TMPDIR:-/tmp}/tidy-branches-test.XXXXXX")" && pwd -P)"
trap 'rm -rf "$TMP"' EXIT
export HOME="$TMP/home"
mkdir -p "$HOME"
# shellcheck source=lib-orchestrator.sh
. "$HERE/lib-orchestrator.sh"

PASS=0
FAIL=0
N=0
check() { # name, expected, actual
  if [ "$2" = "$3" ]; then
    echo "ok   $1"
    PASS=$((PASS + 1))
  else
    echo "FAIL $1: expected [$2] got [$3]"
    FAIL=$((FAIL + 1))
  fi
}
need() { # fixture precondition: silent when true, a FAIL line when the fixture is broken
  if [ "$2" != "$3" ]; then
    echo "FAIL precondition $1: expected [$2] got [$3]"
    FAIL=$((FAIL + 1))
  fi
}

G() { git -c commit.gpgsign=false "$@"; }
cm() { G -C "$W" commit -q --allow-empty -m "$1"; }
co() { G -C "$W" checkout -q "$@"; }
pushdef() { G -C "$W" push -q origin "$DEF" 2> /dev/null; }
anc() { G -C "$W" merge-base --is-ancestor "$1" "$2" 2> /dev/null && echo yes || echo no; }
snap() { # everything the function must leave alone
  git -C "$1" branch --list 2> /dev/null
  git -C "$1" status --porcelain 2> /dev/null
  git -C "$1" for-each-ref 2> /dev/null
}

# mkfix <default branch> [parent dir]: sets BASE, O (bare origin), W (work clone) and DEF.
# The default branch carries three pushed commits and origin/HEAD points to it.
mkfix() {
  DEF="$1"
  N=$((N + 1))
  BASE="${2:-$TMP}/fix$N"
  mkdir -p "$BASE"
  O="$BASE/origin.git"
  W="$BASE/work"
  git init -q --bare "$O"
  git clone -q "$O" "$W" 2> /dev/null
  git -C "$W" config user.email t@t
  git -C "$W" config user.name t
  git -C "$O" symbolic-ref HEAD "refs/heads/$DEF"
  git -C "$W" symbolic-ref HEAD "refs/heads/$DEF"
  cm c1
  cm c2
  cm c3
  pushdef
  git -C "$W" remote set-head origin "$DEF" > /dev/null
  need "fixture $N: origin/HEAD points at $DEF" "refs/remotes/origin/$DEF" "$(git -C "$W" symbolic-ref refs/remotes/origin/HEAD 2> /dev/null)"
  need "fixture $N: origin/$DEF holds the three commits" "3" "$(git -C "$W" rev-list --count "origin/$DEF")"
}

# merged_branch <name>: a branch with one own commit, merged into the default branch with a merge commit and pushed.
merged_branch() {
  co -q -b "$1"
  cm "work on $1"
  co "$DEF"
  G -C "$W" merge -q --no-ff -m "merge $1" "$1"
  pushdef
  need "merged_branch $1: tip is on origin/$DEF" "yes" "$(anc "$1" "origin/$DEF")"
}

# tidy <case name> <expected stdout, each line followed by a comma> <root>
tidy() {
  local name="$1" want="$2" root="$3" before after out rc lines state
  before=$(snap "$root")
  out=$(orch_tidy_branches "$root" 2> /dev/null)
  rc=$?
  after=$(snap "$root")
  lines=""
  [ -n "$out" ] && lines=$(printf '%s\n' "$out" | tr '\n' ',')
  state=same
  [ "$before" = "$after" ] || state=changed
  check "$name" "$want|rc=0|same" "$lines|rc=$rc|$state"
}

check "orch_tidy_branches is defined by lib-orchestrator.sh" "function" "$(type -t orch_tidy_branches || echo missing)"

# a. merged into origin/<default> and pushed, not checked out: listed
mkfix main
merged_branch feat-a
tidy "a. merged and pushed branch is listed" "feat-a," "$W"

# b. one commit that is not on origin/<default>: not listed
mkfix main
co -q -b feat-b
cm "unmerged"
co main
need "b: tip is not on origin/main" "no" "$(anc feat-b origin/main)"
tidy "b. branch with a commit missing on origin/default is not listed" "" "$W"

# c. merged into the local default only, origin/<default> not updated
mkfix main
co -q -b feat-c
cm "local merge only"
co main
G -C "$W" merge -q --no-ff -m "merge feat-c" feat-c
need "c: tip is on local main" "yes" "$(anc feat-c main)"
need "c: tip is not on origin/main" "no" "$(anc feat-c origin/main)"
tidy "c. merged into local default only (not pushed) is not listed" "" "$W"

# d. the default branch itself is never listed, also when it is not checked out and fully merged
mkfix main
co -q -b other
need "d: main is not checked out anywhere" "other" "$(G -C "$W" branch --show-current)"
tidy "d. default branch is not listed when it is not checked out (only the checked-out other branch exists)" "" "$W"

# e. the currently checked-out branch, even if fully merged
mkfix main
co -q -b cur
need "e: cur sits on origin/main's tip" "yes" "$(anc cur origin/main)"
tidy "e. checked-out branch is not listed even when fully merged" "" "$W"

# f. fully merged branch checked out in a linked worktree
mkfix main
G -C "$W" branch wt-b main
G -C "$W" worktree add -q "$BASE/wt" wt-b
need "f: wt-b is checked out in the linked worktree" "wt-b" "$(G -C "$BASE/wt" branch --show-current)"
need "f: wt-b is on origin/main" "yes" "$(anc wt-b origin/main)"
tidy "f. branch checked out in a linked worktree is not listed" "" "$W"

# g. created at an older commit of the default branch, no own commits: listed
mkfix main
G -C "$W" branch old main~2
need "g: old is strictly behind origin/main" "yes/no" "$(anc old origin/main)/$([ "$(G -C "$W" rev-parse old)" = "$(G -C "$W" rev-parse origin/main)" ] && echo yes || echo no)"
tidy "g. branch at an older default commit is listed" "old," "$W"

# h. points exactly at origin/<default>'s tip while the local default is ahead
mkfix main
cm "local only, unpushed"
G -C "$W" branch --no-track same origin/main
need "h: same equals origin/main and differs from local main" "yes/no" "$([ "$(G -C "$W" rev-parse same)" = "$(G -C "$W" rev-parse origin/main)" ] && echo yes || echo no)/$([ "$(G -C "$W" rev-parse same)" = "$(G -C "$W" rev-parse main)" ] && echo yes || echo no)"
tidy "h. branch exactly at origin/default's tip is listed" "same," "$W"

# i. two deletable branches, created in reverse sort order, one with a slash: sorted, one per line
mkfix main
merged_branch fix/login
co main
merged_branch a-first
need "i: both branches exist" "2" "$(G -C "$W" branch --list 'a-first' 'fix/login' | grep -c .)"
tidy "i. two deletable branches are printed sorted, slash name included" "a-first,fix/login," "$W"

# j. no origin remote: prints nothing, rc 0
mkfix main
G -C "$W" branch old main~2
G -C "$W" remote remove origin
need "j: no remote left" "" "$(G -C "$W" remote)"
tidy "j. no origin remote prints nothing" "" "$W"

# k. root is a plain directory, not a repo: prints nothing, rc 0
mkdir -p "$TMP/plain"
need "k: plain dir is not a repo" "no" "$(git -C "$TMP/plain" rev-parse --git-dir > /dev/null 2>&1 && echo yes || echo no)"
tidy "k. non-repo root prints nothing" "" "$TMP/plain"

# l. squash-merged: content is on origin/main, commits are not ancestors: not listed
mkfix main
co -q -b feat-l
echo l > "$W/l.txt"
G -C "$W" add l.txt
cm "add l.txt"
co main
G -C "$W" merge -q --squash feat-l > /dev/null
G -C "$W" commit -q -m "squash feat-l"
pushdef
need "l: the content is on origin/main" "yes" "$(G -C "$W" cat-file -e origin/main:l.txt 2> /dev/null && echo yes || echo no)"
need "l: the tip is not an ancestor of origin/main" "no" "$(anc feat-l origin/main)"
tidy "l. squash-merged branch is not listed" "" "$W"

# default branch comes from origin/HEAD: trunk. A local branch named main is then an ordinary branch.
mkfix trunk
merged_branch feat-t
G -C "$W" branch main trunk~1
tidy "default branch is read from origin/HEAD (trunk); a local main at an old trunk commit is listed" "feat-t,main," "$W"

# origin/HEAD missing: falls back to main
mkfix main
merged_branch feat-n
git -C "$W" symbolic-ref --delete refs/remotes/origin/HEAD
need "n: origin/HEAD is gone" "no" "$(git -C "$W" rev-parse --verify -q refs/remotes/origin/HEAD > /dev/null && echo yes || echo no)"
tidy "origin/HEAD missing falls back to main" "feat-n," "$W"

# root omitted: uses the repository of the current directory
mkfix main
merged_branch feat-o
OUT=$(cd "$W" && orch_tidy_branches 2> /dev/null)
RC=$?
check "root omitted uses the current directory's repository" "feat-o/0" "$OUT/$RC"

# root containing a space
mkdir -p "$TMP/dir with space"
mkfix main "$TMP/dir with space"
merged_branch feat-p
tidy "root path containing a space works" "feat-p," "$W"

# does not fetch: origin moves on, the stale origin/main stays and decides
mkfix main
merged_branch feat-q
git clone -q "$O" "$BASE/other" 2> /dev/null
git -C "$BASE/other" checkout -q main 2> /dev/null
git -C "$BASE/other" config user.email t@t
git -C "$BASE/other" config user.name t
G -C "$BASE/other" commit -q --allow-empty -m "someone else pushes"
G -C "$BASE/other" push -q origin main 2> /dev/null
need "q: origin is ahead of the local origin/main" "no" "$([ "$(git -C "$O" rev-parse main)" = "$(G -C "$W" rev-parse origin/main)" ] && echo yes || echo no)"
tidy "no fetch: stale origin/main still decides and no ref changes" "feat-q," "$W"

echo "ORCH_TIDY_BRANCHES_TEST: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] || exit 1
exit 0
