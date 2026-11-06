#!/usr/bin/env bash
# Pins test-status.sh: a running fake run is listed with class, state and progress age; a process group
# whose wrapper died and a playwright orphan inside the scope are both listed and then reaped, an orphan
# outside the scope stays. Fake processes only, temp state dir.
# Usage: bash audit/bin/test-status.test.sh
set -u
HERE=$(cd "$(dirname "$0")" && pwd)
STATUS="$HERE/test-status.sh"
TMP=$(cd "$(mktemp -d "${TMPDIR:-/tmp}/test-status-test.XXXXXX")" && pwd -P)
# Only PIDs this test started are killed (the detached fakes record theirs in $TMP/pid.*)
# (their `sleep 300` children are killed first: killing the bash alone leaves the sleep behind with parent 1)
trap 'for p in $PIDS $(cat "$TMP"/pid.* 2>/dev/null); do for c in $(pgrep -P "$p" 2>/dev/null); do kill "$c" 2>/dev/null; done; kill "$p" 2>/dev/null; done; rm -rf "$TMP"' EXIT
export TESTRUN_STATE_DIR="$TMP/state" TESTRUN_ORPHAN_AGE=0 TESTRUN_KILL_GRACE=1
FAIL=0; PIDS=""
check() { if [ "$2" = "$3" ]; then echo "ok   $1"; else echo "FAIL $1: expected [$2] got [$3]"; FAIL=$((FAIL + 1)); fi; }
mkdir -p "$TESTRUN_STATE_DIR/runs" "$TMP/scope" "$TMP/other"
NOW=$(date +%s)
ls_start() { ps -o lstart= -p "$1" | sed 's/^ *//;s/ *$//'; }

export TESTRUN_SIMCTL="$HERE/fixtures/fake-simctl" FAKE_SIMCTL_DIR="$TMP/sim"; mkdir -p "$FAKE_SIMCTL_DIR"; : > "$FAKE_SIMCTL_DIR/devices"
export TESTRUN_SWAPUSAGE="total = 1000.00M  used = 900.00M  free = 100.00M  (encrypted)"
check "an empty store says so" "no test runs" "$(bash "$STATUS" --scope "$TMP/scope" | head -1)"
check "no booted simulator says so" "no booted simulators" "$(bash "$STATUS" --scope "$TMP/scope" | grep '^no booted')"
check "swap use is shown" "swap: 900 of 1000 MB used (90%)" "$(bash "$STATUS" --scope "$TMP/scope" | grep '^swap:')"

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
orphan() { local n=$1 d=$2; shift 2; ( cd "$d" && PF="$TMP/pid.$n" perl -e 'exit if fork; exec "bash","-c","echo \$\$ > \"\$PF\"; exec \"\$@\"","x",@ARGV' "$@" >/dev/null 2>&1 </dev/null ); }
orphan scope "$TMP/scope" bash "$TMP/scope/playwright" run-server
orphan other "$TMP/other" bash "$TMP/other/playwright" run-server
sleep 1
OUT=$(bash "$STATUS" --scope "$TMP/scope")
check "the group without a wrapper is shown as orphan" "yes" "$(printf '%s\n' "$OUT" | grep -q '^ghost .*orphan' && echo yes || echo no)"
check "both reapable things are listed" "1 1" "$(printf '%s\n' "$OUT" | grep -c 'dead-wrapper group') $(printf '%s\n' "$OUT" | grep -c "orphan playwright-server.*cwd=$TMP/scope")"
check "the orphan outside the scope is not listed" "0" "$(printf '%s\n' "$OUT" | grep -c "cwd=$TMP/other")"
check "the default scope (/) finds the in-scope orphan too" "1" "$(bash "$STATUS" | grep -c "orphan playwright-server.*cwd=$TMP/scope")"
U1=AAAAAAAA-0000-0000-0000-000000000001; U2=BBBBBBBB-0000-0000-0000-000000000002
printf '    zeit-test (%s) (Booted) \n    iPhone Air (%s) (Booted) \n' "$U1" "$U2" > "$FAKE_SIMCTL_DIR/devices"
printf 'udid=%s\n' "$U1" >> "$TESTRUN_STATE_DIR/runs/0000000000000002-$LIVE"
export TESTRUN_SIM_AGES="$U1 3725
$U2 82800"
OUT=$(bash "$STATUS" --scope "$TMP/scope")
check "a booted simulator is listed with age and the run that holds it" "yes" "$(printf '%s\n' "$OUT" | grep -q "^$U1 *zeit-test *1h02m *zeit pid $LIVE" && echo yes || echo no)"
check "a booted simulator without a run says so" "yes" "$(printf '%s\n' "$OUT" | grep -q "^$U2 *iPhone Air *23h00m *no active run" && echo yes || echo no)"
LINK="$TMP/bin/test-status"; mkdir -p "$TMP/bin"; ln -s "$STATUS" "$LINK"
check "invoked through a symlink (~/.local/bin/test-status) it still finds the lib" "yes" "$(bash "$LINK" 2>&1 | grep -q '^zeit ' && echo yes || echo no)"
check "listing alone kills nothing" "alive" "$(kill -0 "$GRP" 2>/dev/null && echo alive || echo dead)"

bash "$STATUS" --reap --scope "$TMP/scope" >/dev/null 2>&1
sleep 0.5
check "--reap kills the group without a wrapper and drops its ticket" "dead 1" "$(kill -0 "$GRP" 2>/dev/null && echo alive || echo dead) $(ls "$TESTRUN_STATE_DIR/runs" | grep -vc '\.')"
check "--reap kills the in-scope playwright orphan, not the outside one" "0 1" "$(pgrep -f "$TMP/scope/playwright" | grep -c .) $(pgrep -f "$TMP/other/playwright" | grep -c .)"
check "the live run survives --reap" "alive" "$(kill -0 "$LIVE" 2>/dev/null && echo alive || echo dead)"

[ "$FAIL" -eq 0 ] && echo "TEST_STATUS_TEST=OK" || { echo "TEST_STATUS_TEST=FAIL ($FAIL)"; exit 1; }
