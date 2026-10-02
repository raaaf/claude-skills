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

[ "$FAIL" -eq 0 ] && echo "TEST_LOCK_TEST=OK" || { echo "TEST_LOCK_TEST=FAIL ($FAIL)"; exit 1; }
