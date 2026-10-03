#!/usr/bin/env bash
# Pins test-lock.sh's `--cmd "<string>"` form (zsh does not word-split $TEST_COMMAND) and that
# the lock key still carries the -destination id in both the argv and the --cmd form.
# Usage: bash audit/bin/test-lock.test.sh
set -u
HERE=$(cd "$(dirname "$0")" && pwd)
LOCK="$HERE/test-lock.sh"
TMP=$(mktemp -d "${TMPDIR:-/tmp}/test-lock-test.XXXXXX")
trap 'rm -rf "$TMP"' EXIT
git -C "$TMP" init -q
GC="$TMP/.git"
cd "$TMP" || exit 1
FAIL=0
check() { # name expected actual
  if [ "$2" = "$3" ]; then echo "ok   $1"; else echo "FAIL $1: expected [$2] got [$3]"; FAIL=$((FAIL + 1)); fi
}

check "--cmd word-splits a multi-word string" "a b" "$(bash "$LOCK" --cmd "printf '%s %s' a b" 2>&1)"
check "--cmd passes the exit status through" "3" "$(bash "$LOCK" --cmd "exit 3" >/dev/null 2>&1; echo $?)"
check "--cmd without a string is a usage error" "64" "$(bash "$LOCK" --cmd >/dev/null 2>&1; echo $?)"
check "argv form keys on the destination id" "KEYED" \
  "$(bash "$LOCK" bash -c '[ -d "$0/claude-audit-test-lock-AAA" ] && echo KEYED' "$GC" -destination 'platform=iOS Simulator,id=AAA' 2>&1)"
check "--cmd form keys on the destination id inside a quoted string" "KEYED" \
  "$(bash "$LOCK" --cmd "[ -d '$GC/claude-audit-test-lock-BBB' ] && echo KEYED; : xcodebuild test -destination 'platform=iOS Simulator,id=BBB' -scheme X" 2>&1)"
check "--cmd without a destination keys on the repo only" "KEYED" \
  "$(bash "$LOCK" --cmd "[ -d '$GC/claude-audit-test-lock' ] && echo KEYED" 2>&1)"


# A linked worktree shares the main checkout's test database, so it must take the same lock.
git -C "$TMP" -c user.email=t@t -c user.name=t commit -q --allow-empty -m init
git -C "$TMP" worktree add -q "$TMP/wt" 2>/dev/null
check "a linked worktree locks in the main checkout's common git dir" "KEYED" \
  "$(cd "$TMP/wt" && bash "$LOCK" --cmd "[ -d '$GC/claude-audit-test-lock' ] && echo KEYED" 2>&1)"

# A waiter prints a progress line, so a caller's output-stall watchdog (deploy's test gate)
# does not mistake waiting for the lock for a hung test run.
mkdir "$GC/claude-audit-test-lock"
OUT="$TMP/wait.out"
TEST_LOCK_NOTICE_SECONDS=2 bash "$LOCK" --cmd "true" >"$OUT" 2>&1 &
WAITER=$!
sleep 5
rmdir "$GC/claude-audit-test-lock"
wait "$WAITER"
check "a waiter reports that it is waiting" "yes" "$(grep -q 'test-lock: waiting' "$OUT" && echo yes || echo no)"

# A wrapped command that itself goes through test-lock.sh (deploy's test gate does) must not wait
# for the lock its own parent holds: on 2026-10-03 /ship wrapped `deploy zeit test` and the inner
# call waited 960s on itself, then aborted without running a test.
OUT="$TMP/nested.out"
bash "$LOCK" bash "$LOCK" --cmd "echo INNER" >"$OUT" 2>&1 &
NESTED=$!
sleep 4
kill "$NESTED" 2>/dev/null && pkill -f "test-lock.sh --cmd echo INNER" 2>/dev/null
wait "$NESTED" 2>/dev/null
check "a nested call runs under the lock its parent holds" "INNER" "$(grep -x INNER "$OUT")"
check "a nested call leaves the parent's lock to the parent" "gone" "$([ -d "$GC/claude-audit-test-lock" ] && rm -rf "$GC/claude-audit-test-lock" && echo left || echo gone)"

[ "$FAIL" -eq 0 ] && echo "TEST_LOCK_TEST=OK" || { echo "TEST_LOCK_TEST=FAIL ($FAIL)"; exit 1; }
