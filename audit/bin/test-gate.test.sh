#!/usr/bin/env bash
# Pins test-gate.sh: admission through lib-testrun.sh (two suites at once, a third waits, handover, dead holder,
# PID reuse, non-owner release, wait timeout) and `run` (green, browser flake with rerun, repeated flake within 14 days,
# no rerun on count mismatch / non-browser failure / more than 5 files, signal exit passthrough).
# The parse fixtures are the FAILED and summary lines of a real parallel Pest run (Pest 4, events,
# 2026-10-06, one assertion deliberately broken), ANSI codes kept as <ESC>; the class name and the
# failed count are varied per case.
# Usage: bash audit/bin/test-gate.test.sh
set -u
HERE=$(cd "$(dirname "$0")" && pwd)
GATE="$HERE/test-gate.sh"
TMP=$(mktemp -d "${TMPDIR:-/tmp}/test-gate-test.XXXXXX")
SLEEPERS=""
trap 'for p in $SLEEPERS; do kill "$p" 2>/dev/null; done; rm -rf "$TMP"' EXIT
export TEST_GATE_STATE_DIR="$TMP/state"
export TEST_GATE_APP=events
export SLOT_POLL_SECONDS=1
FAIL=0
check() { # name expected actual
  if [ "$2" = "$3" ]; then echo "ok   $1"; else echo "FAIL $1: expected [$2] got [$3]"; FAIL=$((FAIL + 1)); fi
}
sleeper() { sleep 300 & SLEEPERS="$SLEEPERS $!"; LAST=$!; }
export TESTRUN_PRESSURE=1 TESTRUN_FREE_PCT=50 TESTRUN_STAGGER=0 TESTRUN_ADMIT_POLL=0.2
unset TESTRUN_STATE_DIR TESTRUN_DISABLE TESTRUN_ID
runs() { ls "$TEST_GATE_STATE_DIR/runs" 2>/dev/null | grep -vc '\.' ; }
holders() { cat "$TEST_GATE_STATE_DIR"/runs/*-* 2>/dev/null | sed -n 's/^pid=//p' | sort | tr '\n' ' '; }

# --- admission (two suites of different apps run at once, a third waits) ---
sleeper; A=$LAST; sleeper; B=$LAST; sleeper; C=$LAST
check "a free machine admits the first suite" "0 1" "$(bash "$GATE" slot-acquire events "$A" >/dev/null 2>&1; echo "$? $(runs)")"
check "a second suite of another app is admitted at once" "0 2" "$(bash "$GATE" slot-acquire zeit "$B" >/dev/null 2>&1; echo "$? $(runs)")"
OUT=$(SLOT_WAIT_MAX=2 bash "$GATE" slot-acquire shop "$C" 2>&1); RC=$?
check "a third suite waits and gives up with exit 75" "75" "$RC"
check "a waiter names the holders" "yes" "$(printf '%s' "$OUT" | grep -q 'events (suite, pid '"$A" && echo yes || echo no)"
check "a failed waiter leaves no ticket" "2" "$(runs)"
bash "$GATE" slot-release "$C"
check "release by a non-owner is a no-op" "2" "$(runs)"

SLOT_WAIT_MAX=20 bash "$GATE" slot-acquire shop "$C" >/dev/null 2>&1 &
WAITER=$!
sleep 2
bash "$GATE" slot-release "$A"
wait "$WAITER"
check "a waiter takes the freed place" "0 $(echo "$B $C" | tr ' ' '\n' | sort | tr '\n' ' ')" "$? $(holders)"

kill "$B"; wait "$B" 2>/dev/null
sleeper; D=$LAST
OUT=$(bash "$GATE" slot-acquire zeit "$D" 2>&1)
check "a dead holder no longer counts" "0" "$?"
check "its ticket is gone, the new owner is registered" "yes" "$(holders | grep -q "$D" && ! holders | grep -q "$B" && echo yes || echo no)"

for f in "$TEST_GATE_STATE_DIR"/runs/*-"$C"; do sed -i '' 's/^start=.*/start=Thu Jan  1 00:00:00 1970/' "$f"; done
sleeper; E=$LAST
bash "$GATE" slot-acquire shop "$E" >/dev/null 2>&1
check "a live PID with a different start time (PID reuse) no longer counts" "yes" "$(holders | grep -q "$E" && ! holders | grep -q "$C" && echo yes || echo no)"
bash "$GATE" slot-release "$E"; bash "$GATE" slot-release "$D"
check "release by the owner frees its place" "0" "$(runs)"

# --- run ---
ESC=$(printf '\033')
FAILED_T='  <ESC>[41;1m FAILED <ESC>[49;22m <ESC>[1mCLASS<ESC>[22m <ESC>[90m><ESC>[39m it hides the descript…   '
SUMMARY_T='  <ESC>[90mTests:<ESC>[39m    <ESC>[31;1m1 failed<ESC>[39;22m<ESC>[90m,<ESC>[39m<ESC>[39m <ESC>[39m<ESC>[32;1m7 passed<ESC>[39;22m<ESC>[90m (20 assertions)<ESC>[39m'
TAIL_T='  <ESC>[90mDuration:<ESC>[39m <ESC>[39m20.54s<ESC>[39m

<ESC>[1A  <ESC>[90mParallel:<ESC>[39m <ESC>[39m6 processes<ESC>[39m'
mk_fixture() { # outfile summary-count class...
  local out=$1 n=$2 c; shift 2
  : > "$out"
  for c in "$@"; do printf '%s\n' "${FAILED_T//CLASS/$c}" >> "$out"; done
  { printf '%s\n' "${SUMMARY_T//1 failed/$n failed}"; printf '%s\n' "$TAIL_T"; } >> "$out"
  # shellcheck disable=SC1003
  { LC_ALL=C sed "s/<ESC>/$ESC/g" "$out" > "$out.x"; mv "$out.x" "$out"; }
}
cat > "$TMP/filecmd.sh" <<'EOF'
echo "$1" >> "$TEST_GATE_RERUNS"
exit "${FILE_RC:-0}"
EOF
export TEST_GATE_RERUNS="$TMP/reruns.log"
FILECMD="bash $TMP/filecmd.sh"
BROWSER=Tests\\Browser\\Event\\DescriptionToggleTest
mk_fixture "$TMP/one.out" 1 "$BROWSER"
mk_fixture "$TMP/mismatch.out" 2 "$BROWSER"
mk_fixture "$TMP/feature.out" 1 'Tests\Feature\FooTest'
mk_fixture "$TMP/six.out" 6 'Tests\Browser\A1Test' 'Tests\Browser\A2Test' 'Tests\Browser\A3Test' 'Tests\Browser\A4Test' 'Tests\Browser\A5Test' 'Tests\Browser\A6Test'
run_gate() { # fixture [file-rc]; echoes "rc reruns"
  rm -f "$TEST_GATE_RERUNS"
  FILE_RC=${2:-0} bash "$GATE" run "cat $1; exit 2" "$FILECMD" > "$TMP/run.out" 2>&1
  echo "$? $(grep -c . "$TEST_GATE_RERUNS" 2>/dev/null || echo 0)"
}

check "a green run exits 0 without reruns" "0 0" "$(rm -f "$TEST_GATE_RERUNS"; bash "$GATE" run "true" "$FILECMD" >/dev/null 2>&1; echo "$? $(grep -c . "$TEST_GATE_RERUNS" 2>/dev/null || echo 0)")"
check "a signal exit without a named failure passes through" "143" "$(bash "$GATE" run "exit 143" "$FILECMD" >/dev/null 2>&1; echo $?)"

rm -rf "$TEST_GATE_STATE_DIR"
check "a browser flake (rerun green) exits 0 after one rerun" "0 1" "$(run_gate "$TMP/one.out" 0)"
check "the rerun targets the failed file" "tests/Browser/Event/DescriptionToggleTest.php" "$(cat "$TEST_GATE_RERUNS")"
check "the flake is reported" "yes" "$(grep -q '^FLAKY: Tests.Browser.Event.DescriptionToggleTest' "$TMP/run.out" && echo yes || echo no)"
check "the flake is logged with app and workers" "yes" "$(grep -q '"app":"events","test":"Tests\\\\Browser\\\\Event\\\\DescriptionToggleTest","workers":6' "$TEST_GATE_STATE_DIR/test-flakes.jsonl" && echo yes || echo no)"
check "the same test flaky again within 14 days fails hard" "1 1" "$(run_gate "$TMP/one.out" 0)"

rm -rf "$TEST_GATE_STATE_DIR"; mkdir -p "$TEST_GATE_STATE_DIR"
OLD=$(( $(date +%s) - 15 * 86400 ))
printf '{"ts":%s,"date":"old","app":"events","test":"Tests\\\\Browser\\\\Event\\\\DescriptionToggleTest","workers":6}\n' "$OLD" > "$TEST_GATE_STATE_DIR/test-flakes.jsonl"
check "a flake older than 14 days does not fail the gate" "0 1" "$(run_gate "$TMP/one.out" 0)"

rm -rf "$TEST_GATE_STATE_DIR"
check "a rerun that stays red fails" "1 1" "$(run_gate "$TMP/one.out" 1)"
check "a count mismatch against the summary fails without a rerun" "1 0" "$(run_gate "$TMP/mismatch.out")"
check "a Feature failure fails without a rerun" "1 0" "$(run_gate "$TMP/feature.out")"
check "six red browser files fail without a rerun" "1 0" "$(run_gate "$TMP/six.out")"
check "a failure without rerun still lists the FAILED lines" "6" "$(grep -c '^ *FAILED ' "$TMP/run.out")"

[ "$FAIL" -eq 0 ] && echo "TEST_GATE_TEST=OK" || { echo "TEST_GATE_TEST=FAIL ($FAIL)"; exit 1; }
