#!/usr/bin/env bash
# Pins the simulator and swap budget of lib-testrun.sh and the direct-run routing of test-lock.sh:
# shutdown after the last run (test devices only; not while another run uses the device; not with an unreadable
# registry), the cap of booted test simulators (idle ones make room, a physical device or a hung simctl is not
# capped, a blocked head does not hold up runs on booted devices), the swap gate (needs memory pressure too; waits,
# then admits; admits at the limit), and that only real runner calls are heavy: a filtered run of a few files stays
# free, a browser or parallel run gets a ticket and its workers, streams and exit code stay exact.
# Fake simctl, fake processes, temp state dir; nothing touches ~/.local/state/claude or a real simulator.
# Usage: bash audit/bin/sim-budget.test.sh
set -u
HERE=$(cd "$(dirname "$0")" && pwd)
LIB="$HERE/lib-testrun.sh"
TMP=$(cd "$(mktemp -d "${TMPDIR:-/tmp}/sim-budget-test.XXXXXX")" && pwd -P)
SLEEPERS=""
trap 'chmod -R u+rwx "$TMP" 2>/dev/null; for p in $SLEEPERS; do kill "$p" 2>/dev/null; done; rm -rf "$TMP"' EXIT
FAIL=0
check() { if [ "$2" = "$3" ]; then echo "ok   $1"; else echo "FAIL $1: expected [$2] got [$3]"; FAIL=$((FAIL + 1)); fi; }

U1=AAAAAAAA-0000-0000-0000-000000000001; U2=BBBBBBBB-0000-0000-0000-000000000002; U3=CCCCCCCC-0000-0000-0000-000000000003
PHYS=00008150-000E4391010A401C
export FAKE_SIMCTL_DIR="$TMP/sim"; export TESTRUN_SIMCTL="$HERE/fixtures/fake-simctl"
fresh() {
  rm -rf "$TMP/state" "$FAKE_SIMCTL_DIR"; mkdir -p "$FAKE_SIMCTL_DIR" "$TMP/state/runs"
  export TESTRUN_STATE_DIR="$TMP/state"
  unset TEST_GATE_STATE_DIR TESTRUN_DISABLE TESTRUN_ID TESTRUN_SIM_AGES FAKE_SIMCTL_HANG TESTRUN_SIMCTL_TIMEOUT TESTRUN_CAP_XCODE TESTRUN_CAP_GLOBAL TESTRUN_SWAP_WAIT
  export TESTRUN_PRESSURE=1 TESTRUN_FREE_PCT=50 TESTRUN_STAGGER=0 TESTRUN_ADMIT_POLL=0.2 TESTRUN_WAIT_MAX=2 TESTRUN_NOTICE=1 TESTRUN_SIM_GRACE=1
  export TESTRUN_SWAPUSAGE="total = 1000.00M  used = 0.00M  free = 1000.00M  (encrypted)"   # not this Mac's swap
  : > "$FAKE_SIMCTL_DIR/devices"; : > "$FAKE_SIMCTL_DIR/log"
}
dev() { printf '    %s (%s) (%s) \n' "$1" "$2" "$3" >> "$FAKE_SIMCTL_DIR/devices"; }   # name udid state
sleeper() { sleep 300 & SLEEPERS="$SLEEPERS $!"; LAST=$!; }
# a live ticket: ticket <class> <state> <project> <udid> [seconds since it started]
ticket() {
  sleeper
  printf 'pid=%s\nstart=%s\nclass=%s\nstate=%s\nproject=%s\ncwd=%s\nsince=%s\nadmitted_at=%s\nudid=%s\n' "$LAST" \
    "$(ps -o lstart= -p "$LAST" | sed 's/^ *//;s/ *$//')" "$1" "$2" "$3" "$TMP" "$(( $(date +%s) - ${5:-0} ))" "$(date +%s)" "$4" > "$TESTRUN_STATE_DIR/runs/0000000000000001-$LAST"
}
shutdowns() { grep -c "shutdown $1" "$FAKE_SIMCTL_DIR/log"; }
# reaped <udid>: block until the detached reaper of that device is gone (max 30 s)
reaped() {
  local p i=0
  p=$(cat "$TESTRUN_STATE_DIR/sims/$1.reaper" 2>/dev/null)
  while [ -n "$p" ] && kill -0 "$p" 2>/dev/null && [ "$i" -lt 300 ]; do sleep 0.1; i=$((i + 1)); done
}
# until_file <path>: block until the file exists (max 30 s)
until_file() { local i=0; while [ ! -e "$1" ] && [ "$i" -lt 300 ]; do sleep 0.1; i=$((i + 1)); done; }
adm() { ( . "$LIB"; tr_admit "$1" proj "$$" "${2:-}" 2>>"$TMP/stderr"; echo "$?" ); }
lib() { ( . "$LIB"; "$@" ); }
events() { cat "$TESTRUN_STATE_DIR/test-events.jsonl" 2>/dev/null; }

# --- shutdown after the last run -------------------------------------------------------------------
fresh; dev t-test "$U1" Booted
lib tr_sim_release "$U1"; reaped "$U1"
check "the simulator is shut down after the grace period when no run uses it" "1" "$(shutdowns $U1)"
check "the shutdown is logged" "1" "$(events | grep -c '"event":"sim_shutdown"')"

fresh; dev "iPhone Air" "$U1" Booted
lib tr_sim_release "$U1"
check "a device that is not a -test simulator gets no reaper" "none 0" "$([ -e "$TESTRUN_STATE_DIR/sims/$U1.reaper" ] && echo reaper || echo none) $(shutdowns $U1)"

fresh; dev t-test "$U1" Booted
ticket xcode running other "$U1"
lib tr_sim_release "$U1"; reaped "$U1"
check "no shutdown while another run uses the device" "0" "$(shutdowns $U1)"
check "the kept device is logged with its reason" "1" "$(events | grep -c '"reason":"in-use"')"

fresh; dev t-test "$U1" Booted
ticket xcode running other ""
lib tr_sim_release "$U1"; reaped "$U1"
check "a recent running xcode run without a known device blocks the shutdown" "0" "$(shutdowns $U1)"
fresh; dev t-test "$U1" Booted
ticket xcode running other "" 7200
lib tr_sim_release "$U1"; reaped "$U1"
check "a run without a known device blocks no longer than its age limit" "1" "$(shutdowns $U1)"

fresh; dev t-test "$U1" Booted
chmod 000 "$TESTRUN_STATE_DIR/runs"
check "an unreadable registry means no shutdown" "1 0" "$(lib tr_sim_shutdown_if_idle "$U1" test; echo -n "$? "; shutdowns $U1)"
chmod 755 "$TESTRUN_STATE_DIR/runs"
check "a readable empty registry shuts the device down" "0 1" "$(lib tr_sim_shutdown_if_idle "$U1" test; echo -n "$? "; shutdowns $U1)"

fresh; dev t-test "$U1" Booted
lib tr_sim_release "$U1"; sleep 0.3; lib tr_sim_release "$U1"; reaped "$U1"
check "two run ends of one device schedule one shutdown" "1" "$(shutdowns $U1)"

# --- cap of booted test simulators -------------------------------------------------------------------
fresh; dev a-test "$U1" Booted; dev b-test "$U2" Booted; dev c-test "$U3" Shutdown; ticket xcode running o1 "$U1"; ticket xcode running o2 "$U2"
check "a third booted test simulator waits and finally gives up" "75" "$(adm xcode "$U3")"
check "the wait event names the cap" "yes" "$(events | grep -q '"event":"wait".*"reason":"sim-cap"' && echo yes || echo no)"
fresh; dev a-test "$U1" Booted; dev b-test "$U2" Booted; dev c-test "$U3" Shutdown; ticket xcode running o1 "$U1"; ticket xcode running o2 "$U2"
check "a run on an already booted device passes at the cap" "0" "$(adm xcode "$U1")"
fresh; dev a-test "$U1" Booted; dev b-test "$U2" Booted; dev c-test "$U3" Shutdown
check "idle unowned test simulators are shut down to make room" "0 1" "$(adm xcode "$U3") $(( $(shutdowns $U1) + $(shutdowns $U2) ))"
fresh; dev a-test "$U1" Booted; dev b-test "$U2" Booted; ticket xcode running o1 "$U1"; ticket xcode running o2 "$U2"
check "a physical device that simctl does not list is not capped" "0" "$(adm xcode "$PHYS")"
fresh; dev a-test "$U1" Booted; dev b-test "$U2" Booted; dev c-test "$U3" Shutdown; ticket xcode running o1 "$U1"; ticket xcode running o2 "$U2"
export FAKE_SIMCTL_HANG=1 TESTRUN_SIMCTL_TIMEOUT=1
check "a hung simctl lifts the cap for that pass" "0" "$(adm xcode "$U3")"
fresh; dev "iPhone Air" "$U1" Booted; dev "iPhone Duo" "$U2" Booted; dev a-test "$U3" Booted; dev d-test DDDDDDDD-0000-0000-0000-000000000004 Shutdown
check "booted simulators that are not test devices do not count" "0" "$(adm xcode DDDDDDDD-0000-0000-0000-000000000004)"
fresh; dev a-test "$U1" Booted; dev b-test "$U2" Booted
check "a run without a known device is not capped" "0" "$(adm xcode "")"
# a cap-blocked head does not hold up a run on a booted device
fresh; dev a-test "$U1" Booted; dev b-test "$U2" Booted; dev c-test "$U3" Shutdown; ticket xcode running o1 "$U1"; ticket xcode running o2 "$U2"
export TESTRUN_CAP_XCODE=5 TESTRUN_CAP_GLOBAL=5 TESTRUN_WAIT_MAX=8
adm xcode "$U3" > "$TMP/x.rc" & XW=$!
i=0; while ! grep -qs 'capblocked=1' "$TESTRUN_STATE_DIR"/runs/*-"$$" 2>/dev/null && [ "$i" -lt 100 ]; do sleep 0.1; i=$((i + 1)); done
check "the blocked head is flagged" "yes" "$(grep -qs 'capblocked=1' "$TESTRUN_STATE_DIR"/runs/*-"$$" && echo yes || echo no)"
check "a run on a booted device passes the blocked head" "0" "$(adm xcode "$U1")"
wait "$XW"; check "the blocked head itself still waits out its time" "75" "$(cat "$TMP/x.rc")"

# --- swap gate ---------------------------------------------------------------------------------------
fresh; ticket suite running other ""
export TESTRUN_SWAPUSAGE="total = 1000.00M  used = 900.00M  free = 100.00M  (encrypted)"
check "swap above the limit alone does not hold a run back" "0" "$(TESTRUN_SWAP_WAIT=100 adm suite)"
fresh; ticket suite running other ""; export TESTRUN_PRESSURE=2
export TESTRUN_SWAPUSAGE="total = 1000.00M  used = 900.00M  free = 100.00M  (encrypted)"
check "swap above the limit plus memory pressure holds a heavy run back" "75" "$(TESTRUN_SWAP_WAIT=100 adm suite)"
check "the wait event names swap" "yes" "$(events | grep -q '"event":"wait".*"reason":"swap"' && echo yes || echo no)"
fresh; ticket suite running other ""; export TESTRUN_PRESSURE=2 TESTRUN_SWAPUSAGE="total = 1000.00M  used = 900.00M  free = 100.00M  (encrypted)"
check "after the swap wait it is admitted anyway" "0" "$(TESTRUN_SWAP_WAIT=1 adm suite)"
check "the override is logged" "1" "$(events | grep -c '"event":"swap_override"')"
fresh; ticket suite running other ""; export TESTRUN_PRESSURE=2 TESTRUN_SWAPUSAGE="total = 1000.00M  used = 800.00M  free = 200.00M  (encrypted)"
check "swap exactly at the limit is admitted at once" "0" "$(TESTRUN_SWAP_WAIT=100 adm suite)"
fresh; export TESTRUN_PRESSURE=2 TESTRUN_SWAPUSAGE="total = 1000.00M  used = 990.00M  free = 10.00M  (encrypted)"
check "high swap does not hold back a run on an otherwise idle machine" "0" "$(TESTRUN_SWAP_WAIT=100 adm suite)"
fresh; ticket suite running other ""; export TESTRUN_FREE_PCT=10 TESTRUN_SWAPUSAGE="total = 1000.00M  used = 900.00M  free = 100.00M  (encrypted)"
check "low free memory counts as pressure too" "75" "$(TESTRUN_SWAP_WAIT=100 TESTRUN_PRESSURE=1 adm suite)"

# --- which calls are runner calls, which runs are heavy ----------------------------------------------------
fresh
runner() { lib tr_is_runner_call "$@" && echo runner || echo other; }
check "php artisan test is a runner call" "runner" "$(runner php artisan test)"
check "php vendor/bin/pest is a runner call" "runner" "$(runner php ./vendor/bin/pest --parallel)"
check "php vendor/bin/paratest is a runner call" "runner" "$(runner php vendor/bin/paratest)"
check "npx playwright test is a runner call" "runner" "$(runner npx -y playwright test)"
check "composer require paratest is not" "other" "$(runner php /usr/local/bin/composer require brianium/paratest)"
check "php -S is not" "other" "$(runner php -S localhost:8000)"
check "php artisan migrate is not" "other" "$(runner php artisan migrate)"
check "php artisan tinker is not" "other" "$(runner php artisan tinker)"
check "php -r with the word pest in the code is not" "other" "$(runner php -r 'echo "vendor/bin/pest --parallel";')"
check "a script given a string argument with pest is not" "other" "$(runner php script.php "vendor/bin/pest --parallel")"
check "npx something else is not" "other" "$(runner npx vite build)"
heavy() { lib tr_is_heavy_direct "$@" && echo heavy || echo free; }
check "a filtered run of one test file is free" "free" "$(heavy php artisan test tests/Feature/FooTest.php)"
check "a browser run of one named file is free" "free" "$(heavy php artisan test tests/Browser/FooTest.php)"
check "a run of tests/Browser is heavy" "heavy" "$(heavy php artisan test tests/Browser)"
check "pest --parallel is heavy" "heavy" "$(heavy vendor/bin/pest --parallel)"
check "pest --parallel with a single file is still heavy" "heavy" "$(heavy vendor/bin/pest --parallel tests/Feature/FooTest.php)"
check "a bare playwright run is heavy" "heavy" "$(heavy npx playwright test)"
check "a playwright run of one spec is free" "free" "$(heavy npx playwright test e2e/a.spec.ts)"
check "four browser files are heavy" "heavy" "$(heavy php artisan test tests/Browser/ATest.php tests/Browser/BTest.php tests/Browser/CTest.php tests/Browser/DTest.php)"
check "composer require paratest is free" "free" "$(heavy composer require brianium/paratest)"
check "--list-tests is free" "free" "$(heavy vendor/bin/pest --parallel --list-tests)"
check "playwright --ui is free" "free" "$(heavy npx playwright test --ui)"
check "--help is not a full run" "no" "$(lib tr_is_full_run php artisan test --help && echo yes || echo no)"

# --- test-lock.sh routing ------------------------------------------------------------------------------
fresh; git -C "$TMP" init -q 2>/dev/null; cd "$TMP" || exit 1
export TESTRUN_WORKERS_ALONE=5
tickets() { ls "$TESTRUN_STATE_DIR/runs" 2>/dev/null | grep -vc '\.'; }
rm -f "$TMP/started"
bash "$HERE/test-lock.sh" --cmd "touch $TMP/started; sleep 3 # php artisan test tests/Browser/FooTest.php" >/dev/null 2>&1 & W2=$!
until_file "$TMP/started"
check "a filtered browser run of one file has no ticket" "0" "$(tickets)"
wait "$W2" 2>/dev/null
rm -f "$TMP/started"
bash "$HERE/test-lock.sh" --cmd "touch $TMP/started; sleep 3 # php artisan test tests/Browser" >/dev/null 2>&1 & W1=$!
until_file "$TMP/started"
check "a browser run of the whole directory has a suite ticket" "1 suite" "$(tickets) $(sed -n 's/^class=//p' "$TESTRUN_STATE_DIR/runs/$(ls "$TESTRUN_STATE_DIR/runs" | grep -v '\.' | head -1)" 2>/dev/null)"
wait "$W1" 2>/dev/null
check "--parallel gets the admitted worker count" "vendor/bin/pest --parallel --processes=5" "$(bash "$HERE/test-lock.sh" --cmd "echo vendor/bin/pest --parallel" 2>/dev/null)"
check "--parallel keeps the caller's --processes" "vendor/bin/pest --parallel --processes=2" "$(bash "$HERE/test-lock.sh" --cmd "echo vendor/bin/pest --parallel --processes=2" 2>/dev/null)"
check "playwright test gets --workers" "npx playwright test --workers=5" "$(bash "$HERE/test-lock.sh" --cmd "echo npx playwright test" 2>/dev/null)"
check "argv form: --parallel gets the worker count" "vendor/bin/pest --parallel --processes=5" "$(bash "$HERE/test-lock.sh" echo vendor/bin/pest --parallel 2>/dev/null)"
check "TESTRUN_DISABLE=1 leaves the command alone" "vendor/bin/pest --parallel" "$(TESTRUN_DISABLE=1 bash "$HERE/test-lock.sh" --cmd "echo vendor/bin/pest --parallel" 2>/dev/null)"
check "a heavy run keeps stdout clean of stderr" "out" "$(bash "$HERE/test-lock.sh" --cmd "echo out; echo err >&2 # vendor/bin/pest --parallel" 2>/dev/null)"
check "a heavy run keeps its stderr on stderr" "err" "$(bash "$HERE/test-lock.sh" --cmd "echo out; echo err >&2 # vendor/bin/pest --parallel" 2>&1 >/dev/null | grep -v '^TESTRUN')"
check "a heavy run keeps the exit code" "7" "$(bash "$HERE/test-lock.sh" --cmd "exit 7 # vendor/bin/pest --parallel" >/dev/null 2>&1; echo $?)"

[ "$FAIL" -eq 0 ] && echo "SIM_BUDGET_TEST=OK" || { echo "SIM_BUDGET_TEST=FAIL ($FAIL)"; exit 1; }
