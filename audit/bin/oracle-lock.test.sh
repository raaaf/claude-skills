#!/usr/bin/env bash
# Pins oracle-lock.sh: unchanged OK, edits/deletions/shared-setup edits detected, unknown run NONE,
# run ids isolated, clear removes state.
# Usage: bash audit/bin/oracle-lock.test.sh
set -u
HERE=$(cd "$(dirname "$0")" && pwd)
LOCK="$HERE/oracle-lock.sh"
TMP=$(mktemp -d "${TMPDIR:-/tmp}/oracle-lock-test.XXXXXX")
trap 'rm -rf "$TMP"' EXIT
git -C "$TMP" init -q
cd "$TMP" || exit 1
mkdir -p tests/Unit
printf 'test one\n' > tests/Unit/AlphaTest.php
printf 'test two\n' > tests/Unit/BetaTest.php
printf 'pest setup\n' > tests/Pest.php
FAIL=0
check() { # name expected actual
  if [ "$2" = "$3" ]; then echo "ok   $1"; else echo "FAIL $1: expected [$2] got [$3]"; FAIL=$((FAIL + 1)); fi
}
result() { bash "$LOCK" check --run "$1" | grep '^ORACLE_RESULT='; }
changed() { bash "$LOCK" check --run "$1" | grep '^ORACLE_CHANGED='; }

bash "$LOCK" snapshot --run r1 tests/Unit/AlphaTest.php >/dev/null
check "unchanged files are OK" "ORACLE_RESULT=OK" "$(result r1)"

sed -i.bak 's/one/ONE/' tests/Unit/AlphaTest.php && rm -f tests/Unit/AlphaTest.php.bak
check "a sed edit is detected" "ORACLE_RESULT=CHANGED" "$(result r1)"
check "the changed file is named" "ORACLE_CHANGED=tests/Unit/AlphaTest.php" "$(changed r1)"

printf 'test one\n' > tests/Unit/AlphaTest.php
check "restoring the content is OK again" "ORACLE_RESULT=OK" "$(result r1)"

rm tests/Unit/AlphaTest.php
check "a deletion is detected" "ORACLE_CHANGED=tests/Unit/AlphaTest.php" "$(changed r1)"
printf 'test one\n' > tests/Unit/AlphaTest.php

printf 'pest setup edited\n' > tests/Pest.php
check "a shared setup edit is detected" "ORACLE_CHANGED=tests/Pest.php" "$(changed r1)"
printf 'pest setup\n' > tests/Pest.php

check "an unknown run id is NONE" "ORACLE_RESULT=NONE" "$(result nope)"

bash "$LOCK" snapshot --run r2 tests/Unit/BetaTest.php >/dev/null
printf 'changed\n' > tests/Unit/BetaTest.php
check "two run ids are isolated (r2 changed)" "ORACLE_RESULT=CHANGED" "$(result r2)"
check "two run ids are isolated (r1 untouched)" "ORACLE_RESULT=OK" "$(result r1)"

bash "$LOCK" clear --run r1 >/dev/null
check "clear removes the state" "ORACLE_RESULT=NONE" "$(result r1)"
check "clear leaves other runs alone" "ORACLE_RESULT=CHANGED" "$(result r2)"

[ "$FAIL" -eq 0 ] && echo "ORACLE_LOCK_TEST=OK" || { echo "ORACLE_LOCK_TEST=FAIL ($FAIL)"; exit 1; }
