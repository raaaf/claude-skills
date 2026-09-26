#!/usr/bin/env bash
#
# Boundary tests for diff-size-gate.sh's SMALL/OK/LARGE/HUGE thresholds.
# Builds a throwaway git repo per case, commits a base, then creates
# untracked files whose combined line/file counts hit the boundary under
# test, and runs the gate against that base via AUDIT_BASE_REF.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SCRIPT="$SCRIPT_DIR/diff-size-gate.sh"
tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT

# make_files <dir> <total_lines> <total_files>
# Writes <total_files> untracked files: the first absorbs all <total_lines>
# lines, the rest are empty (still counted as changed files, contribute no
# lines). Keeps line count and file count independently controllable.
make_files() {
  local dir="$1" lines="$2" files="$3"
  if [ "$lines" -gt 0 ]; then
    seq 1 "$lines" > "$dir/file0.txt"
  else
    : > "$dir/file0.txt"
  fi
  local rest=$((files - 1))
  local i
  for ((i = 1; i <= rest; i++)); do
    : > "$dir/file$i.txt"
  done
}

run_case() {
  local label="$1" lines="$2" files="$3" expected="$4"
  local repo="$tmpdir/$label"
  mkdir -p "$repo"
  (
    cd "$repo"
    git init -q
    git config user.email "test@test.com"
    git config user.name "test"
    echo "base" > base.txt
    git add base.txt
    git commit -q -m base
  )
  make_files "$repo" "$lines" "$files"
  local base_sha
  base_sha=$(cd "$repo" && git rev-parse HEAD)
  local output
  output=$(cd "$repo" && AUDIT_BASE_REF="$base_sha" bash "$SCRIPT")
  local result
  result=$(printf '%s\n' "$output" | grep -oE 'DIFF_SIZE_RESULT=[A-Z]+' | cut -d= -f2)
  if [ "$result" != "$expected" ]; then
    printf 'FAIL %s: expected %s, got %s\n%s\n' "$label" "$expected" "$result" "$output" >&2
    exit 1
  fi
  printf 'PASS %s (lines=%s files=%s -> %s)\n' "$label" "$lines" "$files" "$result"
}

run_case "small-lines-boundary" 950 5 SMALL
run_case "small-lines-just-over" 951 5 OK
run_case "small-files-boundary" 10 28 SMALL
run_case "small-files-just-over" 10 29 LARGE
run_case "large-lines-boundary" 2000 5 OK
run_case "large-lines-just-over" 2001 5 LARGE
run_case "huge-lines-boundary" 5000 5 LARGE
run_case "huge-lines-just-over" 5001 5 HUGE

printf 'All diff-size-gate.sh boundary tests passed.\n'
