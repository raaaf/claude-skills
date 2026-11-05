#!/usr/bin/env bash
# Pins the AUDIT_SKIP_TESTS guard of SKILL.md Phase 4: the daemon runs the suite itself, so the audit must not.
# The guard lines are cut out of SKILL.md and run against a stub test-lock.sh.
# Usage: bash audit/bin/audit-skip-tests.test.sh
set -u
HERE=$(cd "$(dirname "$0")" && pwd)
SKILL="$HERE/../SKILL.md"
TMP=$(mktemp -d "${TMPDIR:-/tmp}/audit-skip-test.XXXXXX"); trap 'rm -rf "$TMP"' EXIT
FAIL=0
check() { if [ "$2" = "$3" ]; then echo "ok   $1"; else echo "FAIL $1: expected [$2] got [$3]"; FAIL=$((FAIL + 1)); fi; }
printf '#!/bin/bash\necho ran >> "%s/calls"\n' "$TMP" > "$TMP/test-lock.sh"
GUARD=$(grep -A1 '^if \[ "${AUDIT_SKIP_TESTS:-}" = 1 \]' "$SKILL")
[ -n "$GUARD" ] || { echo "FAIL guard not found in SKILL.md"; exit 1; }
run() { : > "$TMP/calls"; ( AUDIT_BIN="$TMP" TEST_COMMAND="make test" bash -c "$GUARD" ) 2>&1; }
OUT=$(AUDIT_SKIP_TESTS=1 run)
check "AUDIT_SKIP_TESTS=1 runs no test" "0" "$(grep -c ran "$TMP/calls")"
check "the skip is reported" "yes" "$(printf '%s' "$OUT" | grep -q 'TESTS_EXIT=skipped' && echo yes || echo no)"
OUT=$(run)
check "without the flag the suite runs through test-lock" "1" "$(grep -c ran "$TMP/calls")"
[ "$FAIL" -eq 0 ] && echo "AUDIT_SKIP_TESTS_TEST=OK" || { echo "AUDIT_SKIP_TESTS_TEST=FAIL ($FAIL)"; exit 1; }
