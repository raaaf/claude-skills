#!/usr/bin/env bash
#
# Tests for orch_unaudited_record/orch_unaudited_base/orch_unaudited_clear
# (lib-orchestrator.sh): the quick-fix collection mechanism /ship and /audit
# share. Builds a throwaway git repo per case.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/lib-orchestrator.sh"
tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT

init_repo() {
  local repo="$1"
  mkdir -p "$repo"
  (
    cd "$repo"
    git init -q -b main
    git config user.email "test@test.com"
    git config user.name "test"
  )
}

fail() { printf 'FAIL %s\n' "$1" >&2; exit 1; }

# --- Case 1: oldest base wins on a second call ------------------------------
repo="$tmpdir/oldest-wins"
init_repo "$repo"
(
  cd "$repo"
  git commit -q --allow-empty -m c1
  sha1=$(git rev-parse HEAD)
  git update-ref refs/remotes/origin/main "$sha1"
  git config branch.main.remote origin && git config branch.main.merge refs/heads/main
  git commit -q --allow-empty -m c2

  orch_unaudited_record
  first=$(orch_unaudited_base)
  [ "$first" = "$sha1" ] || fail "oldest-wins: first record expected $sha1, got $first"

  # Simulate the upstream moving forward (another quick fix got pushed) before
  # a second quick-fix /ship run in this repo calls record again.
  git update-ref refs/remotes/origin/main "$(git rev-parse HEAD)"
  git commit -q --allow-empty -m c3

  orch_unaudited_record
  second=$(orch_unaudited_base)
  [ "$second" = "$first" ] || fail "oldest-wins: second record overwrote $first with $second"
)
printf 'PASS oldest-wins\n'

# --- Case 2: clear removes the file -----------------------------------------
repo="$tmpdir/clear-removes"
init_repo "$repo"
(
  cd "$repo"
  git commit -q --allow-empty -m c1
  git update-ref refs/remotes/origin/main "$(git rev-parse HEAD)"
  git config branch.main.remote origin && git config branch.main.merge refs/heads/main
  git commit -q --allow-empty -m c2

  orch_unaudited_record
  orch_unaudited_base >/dev/null || fail "clear-removes: expected a base before clearing"

  orch_unaudited_clear
  if orch_unaudited_base >/dev/null 2>&1; then
    fail "clear-removes: orch_unaudited_base still succeeded after clear"
  fi
  f="$(git rev-parse --path-format=absolute --git-common-dir)/claude-unaudited-base"
  [ ! -f "$f" ] || fail "clear-removes: $f still on disk"
)
printf 'PASS clear-removes\n'

# --- Case 3: a rebased-away base is no longer an ancestor -------------------
# /audit's consumption checks `git merge-base --is-ancestor <recorded> HEAD`
# before trusting the recorded base; this pins that the primitive actually
# flips once the recorded commit is rebased/reset away.
repo="$tmpdir/non-ancestor"
init_repo "$repo"
(
  cd "$repo"
  git commit -q --allow-empty -m c1
  git update-ref refs/remotes/origin/main "$(git rev-parse HEAD)"
  git config branch.main.remote origin && git config branch.main.merge refs/heads/main
  git commit -q --allow-empty -m c2

  orch_unaudited_record
  recorded=$(orch_unaudited_base)
  git merge-base --is-ancestor "$recorded" HEAD || fail "non-ancestor: recorded base should start as an ancestor"

  # Rebase the recorded base away: reset to an unrelated orphan history.
  git checkout -q --orphan replaced
  git commit -q --allow-empty -m "replaced history"

  if git merge-base --is-ancestor "$recorded" HEAD 2>/dev/null; then
    fail "non-ancestor: recorded base is still reported as an ancestor after history was replaced"
  fi
)
printf 'PASS non-ancestor\n'

printf 'All unaudited-base tests passed.\n'
