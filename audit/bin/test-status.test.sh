#!/usr/bin/env bash
# Pins test-status.sh: a running fake run is listed with class, state and progress age; a process group
# whose wrapper died and a playwright orphan inside the scope are both listed and then reaped, an orphan
# outside the scope stays. Fake processes only, temp state dir.
# Usage: bash audit/bin/test-status.test.sh
set -u
HERE=$(cd "$(dirname "$0")" && pwd)
STATUS="$HERE/test-status.sh"
TMP=$(cd "$(mktemp -d "${TMPDIR:-/tmp}/test-status-test.XXXXXX")" && pwd -P)
trap 'for p in $PIDS; do kill "$p" 2>/dev/null; done; pkill -f "$TMP/" 2>/dev/null; rm -rf "$TMP"' EXIT
export TESTRUN_STATE_DIR="$TMP/state" TESTRUN_ORPHAN_AGE=0 TESTRUN_KILL_GRACE=1
FAIL=0; PIDS=""
check() { if [ "$2" = "$3" ]; then echo "ok   $1"; else echo "FAIL $1: expected [$2] got [$3]"; FAIL=$((FAIL + 1)); fi; }
mkdir -p "$TESTRUN_STATE_DIR/runs" "$TMP/scope" "$TMP/other"
NOW=$(date +%s)
ls_start() { ps -o lstart= -p "$1" | sed 's/^ *//;s/ *$//'; }

check "an empty store says so" "no test runs" "$(bash "$STATUS")"

# a live fake run
sleep 300 & LIVE=$!; PIDS="$PIDS $LIVE"
printf 'pid=%s\nstart=%s\nclass=suite\nstate=running\nproject=zeit\ncwd=%s\nsince=%s\nprogress_at=%s\n' \
  "$LIVE" "$(ls_start "$LIVE")" "$TMP" "$((NOW - 125))" "$((NOW - 7))" > "$TESTRUN_STATE_DIR/runs/0000000000000002-$LIVE"
OUT=$(bash "$STATUS")
LINE=$(printf '%s\n' "$OUT" | awk '/^zeit/ { print $1, $2, $3, $4, $5 }')
check "a running run is listed with project, class, state, age and progress age" "yes" \
  "$(printf '%s' "$LINE" | grep -qE '^zeit suite running 2m0[5-9]s [7-9]s$' && echo yes || echo "no: $LINE")"

# a group without a wrapper
perl -e 'setpgrp(0,0); exec "sleep","300"' & GRP=$!; PIDS="$PIDS $GRP"
sleep 0.5
printf 'pid=999999\nstart=Thu Jan  1 00:00:00 1970\nclass=xcode\nstate=running\nproject=ghost\ncwd=/x\nsince=%s\npgid=%s\npgid_start=%s\n' \
  "$NOW" "$GRP" "$(ls_start "$GRP")" > "$TESTRUN_STATE_DIR/runs/0000000000000003-999999"
# playwright orphans: one in the scope, one outside
printf '#!/bin/bash\nsleep 300\n' > "$TMP/scope/playwright"; cp "$TMP/scope/playwright" "$TMP/other/playwright"
orphan() { ( cd "$1" && perl -e 'exit if fork; exec @ARGV' bash "$1/playwright" run-server >/dev/null 2>&1 </dev/null ); }
orphan "$TMP/scope"; orphan "$TMP/other"
sleep 1
OUT=$(bash "$STATUS" --scope "$TMP/scope")
check "the group without a wrapper is shown as orphan" "yes" "$(printf '%s\n' "$OUT" | grep -q '^ghost .*orphan' && echo yes || echo no)"
check "both reapable things are listed" "1 1" "$(printf '%s\n' "$OUT" | grep -c 'dead-wrapper group') $(printf '%s\n' "$OUT" | grep -c "orphan playwright-server.*cwd=$TMP/scope")"
check "the orphan outside the scope is not listed" "0" "$(printf '%s\n' "$OUT" | grep -c "cwd=$TMP/other")"
check "listing alone kills nothing" "alive" "$(kill -0 "$GRP" 2>/dev/null && echo alive || echo dead)"

bash "$STATUS" --reap --scope "$TMP/scope" >/dev/null 2>&1
sleep 0.5
check "--reap kills the group without a wrapper and drops its ticket" "dead 1" "$(kill -0 "$GRP" 2>/dev/null && echo alive || echo dead) $(ls "$TESTRUN_STATE_DIR/runs" | grep -vc '\.')"
check "--reap kills the in-scope playwright orphan, not the outside one" "0 1" "$(pgrep -f "$TMP/scope/playwright" | grep -c .) $(pgrep -f "$TMP/other/playwright" | grep -c .)"
check "the live run survives --reap" "alive" "$(kill -0 "$LIVE" 2>/dev/null && echo alive || echo dead)"

[ "$FAIL" -eq 0 ] && echo "TEST_STATUS_TEST=OK" || { echo "TEST_STATUS_TEST=FAIL ($FAIL)"; exit 1; }
