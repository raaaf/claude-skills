#!/usr/bin/env bash
# Pins lib-testrun.sh. Everything runs against a temp state dir and fake processes (sleep, bash loops);
# nothing here reads or writes ~/.local/state/claude or ~/.cache/xcodebuild-slot, or kills a real process.
# Part 1a: ticket store, admission (caps, global budget, stagger, FIFO, pressure, dead holders), nesting,
# event log, TESTRUN_DISABLE. Further parts are appended below by the later steps.
# Usage: bash audit/bin/lib-testrun.test.sh
set -u
HERE=$(cd "$(dirname "$0")" && pwd)
LIB="$HERE/lib-testrun.sh"
TMP=$(cd "$(mktemp -d "${TMPDIR:-/tmp}/lib-testrun-test.XXXXXX")" && pwd -P)
SLEEPERS=""
trap 'for p in $SLEEPERS; do kill "$p" 2>/dev/null; done; rm -rf "$TMP"' EXIT
FAIL=0
check() { # name expected actual
  if [ "$2" = "$3" ]; then echo "ok   $1"; else echo "FAIL $1: expected [$2] got [$3]"; FAIL=$((FAIL + 1)); fi
}
sleeper() { sleep 300 & SLEEPERS="$SLEEPERS $!"; LAST=$!; }

fresh_state() {
  rm -rf "$TMP/state"
  export TESTRUN_STATE_DIR="$TMP/state"
  unset TEST_GATE_STATE_DIR TESTRUN_DISABLE TESTRUN_ID TESTRUN_PRESSURE TESTRUN_FREE_PCT
  export TESTRUN_PRESSURE=1 TESTRUN_FREE_PCT=50 TESTRUN_STAGGER=0 TESTRUN_ADMIT_POLL=0.2 TESTRUN_WAIT_MAX=2 TESTRUN_NOTICE=1
}
# adm <class> <project> <owner-pid>: admit in a subshell, print the exit code and the ticket id
adm() { ( . "$LIB"; tr_admit "$1" "$2" "$3" 2>>"$TMP/stderr"; rc=$?; echo "$rc ${TESTRUN_ID:-}" ); }
rc_of() { echo "${1%% *}"; }
id_of() { echo "${1#* }"; }
tickets() { ls "$TESTRUN_STATE_DIR/runs" 2>/dev/null | grep -vc '\.' ; }
lib() { ( . "$LIB"; "$@" ); }

# --- caps: class ceiling, global budget -----------------------------------------------------------
fresh_state
sleeper; O1=$LAST; sleeper; O2=$LAST; sleeper; O3=$LAST
R1=$(adm suite zeit "$O1"); R2=$(adm suite events "$O2"); R3=$(adm suite shop "$O3")
check "two suite runs of different apps are admitted" "0 0" "$(rc_of "$R1") $(rc_of "$R2")"
check "a third suite run waits and gives up with 75" "75" "$(rc_of "$R3")"
check "a failed waiter leaves no ticket behind" "2" "$(tickets)"
check "the give-up names the holders" "yes" "$(grep -q 'no slot for suite' "$TMP/stderr" && grep -q 'zeit (suite' "$TMP/stderr" && echo yes || echo no)"

fresh_state
sleeper; X1=$LAST; sleeper; X2=$LAST; sleeper; S1=$LAST; sleeper; S2=$LAST
adm xcode a "$X1" >/dev/null; adm xcode b "$X2" >/dev/null; adm suite c "$S1" >/dev/null
check "xcode and suite together stop at the global budget of 3" "75" "$(rc_of "$(adm suite d "$S2")")"
check "a third xcode run is stopped by the class ceiling" "75" "$(rc_of "$(adm xcode e "$S2")")"

# --- release frees the slot, a waiter takes it ----------------------------------------------------
fresh_state
export TESTRUN_CAP_SUITE=1
sleeper; A=$LAST; sleeper; B=$LAST
RA=$(adm suite zeit "$A")
( sleep 1; lib tr_release "$(id_of "$RA")" ) &
REL=$!
RB=$(TESTRUN_WAIT_MAX=10 adm suite events "$B")
wait "$REL"
check "a waiter is admitted once the holder releases" "0" "$(rc_of "$RB")"
unset TESTRUN_CAP_SUITE

# --- dead holder: slot and ticket are reclaimed -----------------------------------------------------
fresh_state
export TESTRUN_CAP_SUITE=1
sleeper; D=$LAST; sleeper; E=$LAST
adm suite zeit "$D" >/dev/null
kill "$D"; wait "$D" 2>/dev/null
check "a slot whose holder died is reclaimed" "0" "$(rc_of "$(adm suite events "$E")")"
unset TESTRUN_CAP_SUITE

# --- FIFO: the older waiter goes first -------------------------------------------------------------
fresh_state
export TESTRUN_CAP_SUITE=1 TESTRUN_WAIT_MAX=12
sleeper; F1=$LAST; sleeper; F2=$LAST; sleeper; F3=$LAST
RF1=$(adm suite one "$F1")
( adm suite two "$F2" > "$TMP/w2" ) &
W2=$!
sleep 1
( adm suite three "$F3" > "$TMP/w3" ) &
W3=$!
sleep 1
lib tr_release "$(id_of "$RF1")"
sleep 1.5
check "the older waiter is admitted first" "yes" "$([ -s "$TMP/w2" ] && [ ! -s "$TMP/w3" ] && echo yes || echo no)"
lib tr_release "$(id_of "$(cat "$TMP/w2")")"
wait "$W2" "$W3"
check "the younger waiter follows" "0" "$(rc_of "$(cat "$TMP/w3")")"
unset TESTRUN_CAP_SUITE; export TESTRUN_WAIT_MAX=2

# --- stagger: a later candidate waits after an admission --------------------------------------------
fresh_state
export TESTRUN_STAGGER=3 TESTRUN_WAIT_MAX=10
sleeper; G1=$LAST; sleeper; G2=$LAST
adm suite zeit "$G1" >/dev/null
T0=$(date +%s)
adm suite events "$G2" >/dev/null
check "the second candidate waits for the stagger window" "yes" "$([ $(( $(date +%s) - T0 )) -ge 2 ] && echo yes || echo no)"
export TESTRUN_STAGGER=0 TESTRUN_WAIT_MAX=2

# --- pressure -------------------------------------------------------------------------------------
pok() { ( . "$LIB"; tr_pressure_ok "$1" && echo yes || echo no ); }
fresh_state
check "level 1 admits with two heavy runs active" "yes" "$(TESTRUN_PRESSURE=1 pok 2)"
check "level 2 with 40% free admits next to one heavy run" "yes" "$(TESTRUN_PRESSURE=2 TESTRUN_FREE_PCT=40 pok 1)"
check "level 2 with 40% free refuses next to two heavy runs" "no" "$(TESTRUN_PRESSURE=2 TESTRUN_FREE_PCT=40 pok 2)"
check "level 2 with 10% free refuses next to one heavy run" "no" "$(TESTRUN_PRESSURE=2 TESTRUN_FREE_PCT=10 pok 1)"
check "level 2 with 10% free admits into an idle machine" "yes" "$(TESTRUN_PRESSURE=2 TESTRUN_FREE_PCT=10 pok 0)"
check "level 4 refuses even on an idle machine" "no" "$(TESTRUN_PRESSURE=4 pok 0)"
check "unreadable pressure admits one heavy run only" "yes no" "$(TESTRUN_PRESSURE= pok 0) $(TESTRUN_PRESSURE= pok 1)"
sleeper; P1=$LAST
check "a run waits under level 4 and gives up" "75" "$(rc_of "$(TESTRUN_PRESSURE=4 adm suite zeit "$P1")")"

# --- xcode ceiling guard file ------------------------------------------------------------------------
fresh_state
mkdir -p "$TESTRUN_STATE_DIR"
echo $(( $(date +%s) + 600 )) > "$TESTRUN_STATE_DIR/xcode-cap-until"
check "an active guard pins the xcode ceiling to 1" "1 2" "$(lib tr_cap xcode) $(lib tr_cap suite)"
echo $(( $(date +%s) - 5 )) > "$TESTRUN_STATE_DIR/xcode-cap-until"
check "an expired guard no longer applies" "2" "$(lib tr_cap xcode)"

# --- nesting: the inner layer does not admit again ---------------------------------------------------
fresh_state
sleeper; N1=$LAST
OUTER=$(adm suite zeit "$N1")
check "an inner layer under a live TESTRUN_ID adds no ticket" "1" "$(TESTRUN_ID=$(id_of "$OUTER") adm suite zeit "$N1" >/dev/null; tickets)"
check "an inner layer only refreshes progress_at" "yes" "$(
  ( . "$LIB"; export TESTRUN_ID=$(id_of "$OUTER"); _tr_set "$TESTRUN_ID" progress_at 1; tr_progress
    [ "$(_tr_field progress_at "$(_tr_ticket "$TESTRUN_ID")")" -gt 1000 ] && echo yes || echo no ))"

# --- event log and disable switch ---------------------------------------------------------------------
fresh_state
sleeper; V1=$LAST; sleeper; V2=$LAST
export TESTRUN_CAP_SUITE=1
adm suite zeit "$V1" >/dev/null
adm suite events "$V2" >/dev/null
unset TESTRUN_CAP_SUITE
EV="$TESTRUN_STATE_DIR/test-events.jsonl"
check "waiting is logged as an event with project and pressure" "yes" "$(grep -q '"event":"wait".*"class":"suite".*"pressure":"1"' "$EV" && echo yes || echo no)"
check "giving up is logged" "yes" "$(grep -q '"event":"giveup"' "$EV" && echo yes || echo no)"
check "every event is also a TESTRUN line on stderr" "yes" "$(grep -q '^TESTRUN wait waited=0 class=suite' "$TMP/stderr" && echo yes || echo no)"

fresh_state
export TESTRUN_DISABLE=1 TESTRUN_CAP_SUITE=0
sleeper; Z1=$LAST
check "TESTRUN_DISABLE admits at once even when no slot exists" "0 " "$(adm suite zeit "$Z1")"
check "TESTRUN_DISABLE writes no ticket and no event" "none" "$([ -e "$TESTRUN_STATE_DIR/runs" ] || [ -e "$TESTRUN_STATE_DIR/test-events.jsonl" ] && echo some || echo none)"
unset TESTRUN_DISABLE TESTRUN_CAP_SUITE

# ===== Part 1b: watchdog, kill, restart, orphans =====================================================
cd "$TMP" || exit 1
# Only PIDs this test started are killed: sleepers, plus every detached fake that records its pid in $TMP/pid.*
trap 'for p in $SLEEPERS $(cat "$TMP"/pid.* 2>/dev/null); do kill "$p" 2>/dev/null; done; rm -rf "$TMP"' EXIT
wd_env() {
  fresh_state
  export TESTRUN_WATCH_POLL=1 TEST_STALL_SECONDS=4 TEST_STALL_SECONDS_XCODE=4 TESTRUN_CPU_DELTA=1 TESTRUN_KILL_GRACE=1
  export TESTRUN_XCODE_EXTRA_RE='no-such-process-xyz' TESTRUN_STAGGER=0 TESTRUN_WAIT_MAX=5
  export TESTRUN_PSQL="$TMP/fake-psql" TESTRUN_SIMCTL="$TMP/fake-simctl"
  : > "$TMP/psql.log"; : > "$TMP/simctl.log"
}
cat > "$TMP/fake-psql" <<'FEOF'
#!/bin/bash
echo "$*" >> "$(dirname "$0")/psql.log"
FEOF
cat > "$TMP/fake-simctl" <<'FEOF'
#!/bin/bash
echo "$*" >> "$(dirname "$0")/simctl.log"
FEOF
chmod +x "$TMP/fake-psql" "$TMP/fake-simctl"
# run <class> cmd...: tr_run in a subshell; prints rc, stderr goes to $TMP/err
run() { local class=$1; shift; ( . "$LIB"; tr_run "$class" fakeproj "$@" ) >"$TMP/out" 2>"$TMP/err"; echo $?; }
count() { grep -c "$1" "$2" 2>/dev/null; }
HANG_ONCE="n=\$(cat $TMP/hc 2>/dev/null || echo 0); echo \$((n+1)) > $TMP/hc; if [ \$n = 0 ]; then sleep 300; else echo second-try-ok; fi"

wd_env; rm -f "$TMP/hc"
check "a hung suite is restarted once and then succeeds" "0 1 yes" "$(R=$(run suite bash -c "$HANG_ONCE"); echo "$R $(count '^TEST_RESTART' "$TMP/err") $(grep -q second-try-ok "$TMP/out" && echo yes || echo no)")"
check "stall and restart are written to the event log" "yes" "$(grep -q '"event":"stall"' "$TESTRUN_STATE_DIR/test-events.jsonl" && grep -q '"event":"restart"' "$TESTRUN_STATE_DIR/test-events.jsonl" && echo yes || echo no)"
check "a finished run leaves no ticket and no slot" "0 0" "$(tickets) $(ls "$TESTRUN_STATE_DIR/slots" | grep -c '\.')"

wd_env
check "a second stall ends with 124 and TEST_STALLED_TWICE after exactly one restart" "124 1 1" "$(R=$(run suite sleep 300); echo "$R $(count '^TEST_RESTART' "$TMP/err") $(count '^TEST_STALLED_TWICE' "$TMP/err")")"

# burn <seconds>: a command string with 16 parallel busy loops. One loop gets too little CPU to cross the stall
# window's CPU delta when the machine is heavily loaded (load ~170 on 12 cores, 2026-10-13); the sum of sixteen does.
burn() { echo 'end=$((SECONDS+'"$1"')); for i in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16; do (while [ $SECONDS -lt $end ]; do :; done) & done; wait'; }

wd_env
export TESTRUN_CPU_DELTA=0 TEST_STALL_SECONDS=12   # any whole CPU second counts as progress, over a wider window; wd_env resets both
check "a silent run that burns CPU is not a stall" "0 0" "$(R=$(run suite bash -c "$(burn 16)"); echo "$R $(count '^TEST_RESTART' "$TMP/err")")"

wd_env; rm -f "$TMP/pf"
R=$(run xcode bash -c "set -m; sleep 302 & echo \$! > $TMP/pf; set +m; sleep 300" build)
CHILD=$(cat "$TMP/pf" 2>/dev/null)
check "a stalled build is killed without a restart" "124 0" "$R $(count '^TEST_RESTART' "$TMP/err")"
check "a child that left the process group is killed too" "dead" "$(kill -0 "$CHILD" 2>/dev/null && echo alive || echo dead)"

cat > "$TMP/nested.sh" <<NEOF
. "$LIB"
tr_run suite inner bash -c 'ls "\$TESTRUN_STATE_DIR/runs" | grep -vc "\\."'
NEOF
wd_env
R=$(run suite bash "$TMP/nested.sh")
check "a nested tr_run adds no ticket and no second watchdog" "0 1" "$R $(tr -d ' \n' < "$TMP/out")"

# xcode: testmanagerd/simulator CPU counts as progress; the warning comes before the kill
wd_env
export TEST_WARN_SECONDS_XCODE=3 TESTRUN_XCODE_EXTRA_RE='fake-sim-busy' TESTRUN_CPU_DELTA=0
bash -c "$(burn 11)" fake-sim-busy "$TMP/" &
BUSY=$!
check "a quiet xcode run survives while the simulator side is busy" "0" "$(run xcode bash -c 'sleep 9' build)"
check "an xcode run silent for the warn threshold logs a warning, not a kill" "1 0" "$(count 'TESTRUN warn' "$TMP/err") $(count 'TESTRUN stall' "$TMP/err")"
kill "$BUSY" 2>/dev/null; wait "$BUSY" 2>/dev/null
wd_env
check "the same quiet run without simulator activity is stalled" "124" "$(run xcode bash -c 'sleep 30' build)"

# restart cleanup: result bundle, simulator reboot, own-worktree DB sessions
wd_env
mkdir -p "$TMP/r.xcresult" "$TESTRUN_STATE_DIR"
SLUG=$(. "$LIB"; tr_slug "$(pwd)")
printf 'zeit_testing_%s\nother_testing_deadbeef\n' "$SLUG" > "$TESTRUN_STATE_DIR/test-dbs.list"
rm -f "$TMP/hc"
R=$(run xcode bash -c "$HANG_ONCE" test -resultBundlePath "$TMP/r.xcresult" -destination "platform=iOS Simulator,id=ABC-123")
check "a restarted xcode test run succeeds on the second try" "0 1" "$R $(count '^TEST_RESTART' "$TMP/err")"
check "the half-written result bundle is removed" "gone" "$([ -e "$TMP/r.xcresult" ] && echo there || echo gone)"
check "the target simulator is shut down and booted" "shutdown ABC-123 boot ABC-123" "$(tr '\n' ' ' < "$TMP/simctl.log" | sed 's/ $//')"
check "only the worktree's own databases lose their sessions" "1 0" "$(count "datname = 'zeit_testing_$SLUG'" "$TMP/psql.log") $(count other_testing "$TMP/psql.log")"
check "the paratest workers of that database are covered by an exact regex" "yes" "$(grep -q "datname ~ '^zeit_testing_${SLUG}_test_\[0-9\]+\$'" "$TMP/psql.log" && echo yes || echo no)"

# xcode guard: a simulator-bootstrap error during a parallel run caps xcode at 1 for 24 h
wd_env
sleeper; GP=$LAST
adm xcode other "$GP" >/dev/null
run xcode bash -c 'sleep 2; echo "Testing failed: Channel disconnected" >&2; exit 1' build >/dev/null
check "a simulator error in a parallel run pins the xcode ceiling to 1" "1" "$(lib tr_cap xcode)"
check "the guard is logged" "yes" "$(grep -q '"event":"guard"' "$TESTRUN_STATE_DIR/test-events.jsonl" && echo yes || echo no)"
wd_env
sleeper; GP2=$LAST
run xcode bash -c 'sleep 2; echo "Channel disconnected" >&2; exit 1' build >/dev/null
check "the same error in a solo run does not pin the ceiling" "2" "$(lib tr_cap xcode)"

# orphans: scoped, aged, not while a real pest/phpunit run shares the cwd
wd_env
export TESTRUN_ORPHAN_AGE=0
mkdir -p "$TMP/wt/bin" "$TMP/other"
SCOPE=$(cd "$TMP/wt" && pwd -P); OTHER=$(cd "$TMP/other" && pwd -P)
printf '#!/bin/bash\nsleep 300\n' > "$SCOPE/playwright"; cp "$SCOPE/playwright" "$OTHER/playwright"
cp "$(command -v bash)" "$TMP/php"   # a process whose comm is `php`
# orphan <pidfile-name> <dir> cmd...: start cmd in dir, detached so launchd (pid 1) becomes its parent;
# the command records its own pid in $TMP/pid.<name> before it execs
orphan() { local n=$1 d=$2; shift 2; ( cd "$d" && PF="$TMP/pid.$n" perl -e 'exit if fork; exec "bash","-c","echo \$\$ > \"\$PF\"; exec \"\$@\"","x",@ARGV' "$@" >/dev/null 2>&1 </dev/null ); }
orphan pw1 "$SCOPE" bash "$SCOPE/playwright" run-server
orphan pw2 "$OTHER" bash "$OTHER/playwright" run-server
sleep 1
check "an orphan server in scope is listed, one outside the scope is not" "1" "$(lib tr_reap_orphans "$SCOPE" --dry | grep -c "cwd=$SCOPE")"
check "scope / means everywhere (not the pattern //*)" "1" "$(lib tr_reap_orphans / --dry | grep -c "cwd=$SCOPE")"
orphan wrap "$SCOPE" bash -c 'sleep 300; :' "artisan test"
sleep 0.5
check "a wrapper that merely carries 'artisan test' does not keep the orphan alive" "1" "$(lib tr_reap_orphans "$SCOPE" --dry | grep -c orphan)"
orphan php "$SCOPE" "$TMP/php" -c 'sleep 300; :' "$SCOPE/bin/phpunit"
sleep 1
check "an orphan next to a live php/phpunit process is left alone" "0" "$(lib tr_reap_orphans "$SCOPE" --dry | grep -c orphan)"
kill "$(cat "$TMP/pid.php")"; sleep 0.5
check "without the php process the orphan is found again" "1" "$(lib tr_reap_orphans "$SCOPE" --dry | grep -c orphan)"
lib tr_reap_orphans "$SCOPE" >/dev/null 2>&1
sleep 0.5
check "reaping kills the in-scope orphan only" "0 1" "$(pgrep -f "$SCOPE/playwright" | grep -c .) $(lib tr_reap_orphans "$OTHER" --dry | grep -c orphan)"

# dead wrapper, live group
wd_env
mkdir -p "$TESTRUN_STATE_DIR/runs"
perl -e 'setpgrp(0,0); exec "sleep","300"' & DG=$!; SLEEPERS="$SLEEPERS $DG"
sleep 0.5
printf 'pid=999999\nstart=Thu Jan  1 00:00:00 1970\nclass=suite\nstate=running\nproject=ghost\ncwd=/x\nsince=1\npgid=%s\npgid_start=%s\n' "$DG" "$(ps -o lstart= -p "$DG" | sed 's/^ *//;s/ *$//')" > "$TESTRUN_STATE_DIR/runs/0000000000000001-999999"
check "a group whose wrapper died stays a live ticket" "1" "$(lib _tr_prune; tickets)"
check "the dead-wrapper group is listed" "1" "$(lib tr_reap_dead_groups --dry | grep -c ghost)"
lib tr_reap_dead_groups >/dev/null 2>&1
check "reaping kills the group and drops the ticket" "dead 0" "$(kill -0 "$DG" 2>/dev/null && echo alive || echo dead) $(tickets)"

# an orphaned xcode group must not keep its slot: the waiter reaps it during admission (cap 1)
wd_env
export TESTRUN_CAP_XCODE=1
mkdir -p "$TESTRUN_STATE_DIR/runs" "$TESTRUN_STATE_DIR/slots/xcode.1"
perl -e 'setpgrp(0,0); exec "sleep","300"' & DG2=$!; SLEEPERS="$SLEEPERS $DG2"
sleep 0.5
GID=0000000000000009-999998
printf 'pid=999998\nstart=Thu Jan  1 00:00:00 1970\nclass=xcode\nstate=running\nproject=ghost\ncwd=/x\nsince=1\nadmitted_at=1\npgid=%s\npgid_start=%s\n' "$DG2" "$(ps -o lstart= -p "$DG2" | sed 's/^ *//;s/ *$//')" > "$TESTRUN_STATE_DIR/runs/$GID"
echo "$GID" > "$TESTRUN_STATE_DIR/slots/xcode.1/id"
sleeper; WAITER=$LAST
check "a waiter reaps an orphaned group and takes its slot" "0 dead" "$(R=$(TESTRUN_WAIT_MAX=8 adm xcode real "$WAITER"); echo "$(rc_of "$R") $(kill -0 "$DG2" 2>/dev/null && echo alive || echo dead)")"
unset TESTRUN_CAP_XCODE

# pruning a dead ticket also removes its output files
wd_env
mkdir -p "$TESTRUN_STATE_DIR/runs"
printf 'pid=999997\nstart=Thu Jan  1 00:00:00 1970\nclass=suite\nstate=running\nproject=x\ncwd=/x\nsince=1\n' > "$TESTRUN_STATE_DIR/runs/0000000000000007-999997"
: > "$TESTRUN_STATE_DIR/runs/0000000000000007-999997.out"; : > "$TESTRUN_STATE_DIR/runs/0000000000000007-999997.out.1"
lib _tr_prune
check "pruning a dead ticket removes its .out and fifo files" "0" "$(ls "$TESTRUN_STATE_DIR/runs" | wc -l | tr -d ' ')"

# the watch loop notices an exit within a tick, not after a full sample interval
wd_env
export TESTRUN_WATCH_POLL=15
T0=$(date +%s); R=$(run suite sleep 2); T1=$(date +%s)
check "a short run returns long before one sample interval (15 s) has passed" "0 yes" "$R $([ $((T1 - T0)) -lt 8 ] && echo yes || echo "no ($((T1 - T0)) s)")"
export TESTRUN_WATCH_POLL=1

# extra CPU is attributed to the run's own device: A idles, B burns, so counting B for A would show
unset TESTRUN_XCODE_EXTRA_RE
bash -c 'sleep 8; :' "CoreSimulator/Devices/AAAA-A/launchd_sim" & SLEEPERS="$SLEEPERS $!"
bash -c "$(burn 8); :" "CoreSimulator/Devices/BBBB-B/launchd_sim" & SLEEPERS="$SLEEPERS $!"
sleep 4
EA=$(lib tr_extra_cpu AAAA-A); EB=$(lib tr_extra_cpu BBBB-B); EN=$(lib tr_extra_cpu)
check "extra CPU counts the run's own device only (A idle, B busy; no UDID counts nothing)" "yes yes 0" "$([ "$EA" -le 1 ] && echo yes || echo "no $EA") $([ "$EB" -ge 2 ] && echo yes || echo "no $EB") $EN"
export TESTRUN_XCODE_EXTRA_RE='no-such-process-xyz'

# ===== Part 1c: cache, database names, cleanup ========================================================
export TESTRUN_TOOL_VERSIONS="php-fixed xcode-fixed"
REPO="$TMP/repo"
mkdir -p "$REPO/docs" "$REPO/src" "$REPO/.claude"
git -C "$REPO" init -q
printf 'a\n' > "$REPO/src/a.php"; printf 'doc\n' > "$REPO/docs/readme.md"
git -C "$REPO" add -A; git -C "$REPO" -c user.email=t@t -c user.name=t commit -q -m init
chit() { ( . "$LIB"; tr_cache_hit "$REPO" "${1:-composer test}" ); }
cput() { ( . "$LIB"; tr_cache_put "$REPO" "${1:-composer test}" "${2:-0}" "${3:-}" ) 2>/dev/null; }
cfile() { ls "$TESTRUN_STATE_DIR"/test-cache/* 2>/dev/null | head -1; }
reset_files() { printf 'a\n' > "$REPO/src/a.php"; printf 'doc\n' > "$REPO/docs/readme.md"; rm -f "$REPO/.claude/ship.md"; }

fresh_state
check "an empty cache misses" "miss" "$(chit >/dev/null && echo hit || echo miss)"
cput
check "an identical tree and command hit" "TEST_CACHE_HIT" "$(chit | cut -d' ' -f1)"
check "a hit is logged as an event" "yes" "$(grep -q '"event":"cache_hit"' "$TESTRUN_STATE_DIR/test-events.jsonl" && echo yes || echo no)"
check "a different test command misses" "miss" "$(chit 'composer test:parallel' >/dev/null && echo hit || echo miss)"
printf 'b\n' > "$REPO/src/a.php"
check "an edited file misses" "miss" "$(chit >/dev/null && echo hit || echo miss)"
reset_files
check "restoring the tree hits again" "hit" "$(chit >/dev/null && echo hit || echo miss)"
mkdir -p "$REPO/vendor/composer"; echo '{}' > "$REPO/vendor/composer/installed.json"
check "a changed lockfile misses" "miss" "$(chit >/dev/null && echo hit || echo miss)"
rm -rf "$REPO/vendor"
check "a changed tool version misses" "miss" "$(TESTRUN_TOOL_VERSIONS="php-other" chit >/dev/null && echo hit || echo miss)"

# expiry: the stored timestamp is 31 minutes old
F=$(cfile); awk '{ $1 = $1 - 1860; print }' "$F" > "$F.x" && mv "$F.x" "$F"
check "an entry older than 30 minutes misses" "miss" "$(chit >/dev/null && echo hit || echo miss)"

# flaky runs are never cached
fresh_state
printf 'FLAKY: Tests.Browser.X (rerun green)\n' > "$TMP/flaky.log"
cput "composer test" 0 "$TMP/flaky.log"
check "a run with a FLAKY line is not cached" "none" "$([ -n "$(cfile)" ] && echo some || echo none)"
mkdir -p "$TESTRUN_STATE_DIR"; printf '{"ts":%s,"app":"x","test":"t"}\n' "$(( $(date +%s) + 5 ))" > "$TESTRUN_STATE_DIR/test-flakes.jsonl"
cput "composer test" "$(date +%s)"
check "a flake recorded since the run started is not cached" "none" "$([ -n "$(cfile)" ] && echo some || echo none)"
cput "composer test" "$(( $(date +%s) + 60 ))"
check "an older flake record does not block caching" "some" "$([ -n "$(cfile)" ] && echo some || echo none)"

# opt-in delta rules
fresh_state
printf 'test-cache-ignore: docs/*\n' > "$REPO/.claude/ship.md"
cput
printf 'changed\n' >> "$REPO/docs/readme.md"
check "a delta inside test-cache-ignore still hits" "hit" "$(chit >/dev/null && echo hit || echo miss)"
printf 'changed\n' >> "$REPO/src/a.php"
check "a delta outside the ignore globs misses" "miss" "$(chit >/dev/null && echo hit || echo miss)"
reset_files
printf 'test-cache-prose: true\n' > "$REPO/.claude/ship.md"; printf 'changed\n' >> "$REPO/docs/readme.md"
check "a prose-only delta hits with test-cache-prose" "hit" "$(chit >/dev/null && echo hit || echo miss)"
printf 'changed\n' >> "$REPO/src/a.php"
check "a code delta misses with test-cache-prose" "miss" "$(chit >/dev/null && echo hit || echo miss)"
reset_files; printf 'changed\n' >> "$REPO/docs/readme.md"
check "without opt-in a prose delta misses" "miss" "$(chit >/dev/null && echo hit || echo miss)"
reset_files
F=$(cfile); awk '{ $2 = "0000000000000000000000000000000000000000"; print }' "$F" > "$F.x" && mv "$F.x" "$F"
printf 'test-cache-prose: true\n' > "$REPO/.claude/ship.md"; printf 'x\n' >> "$REPO/docs/readme.md"
check "a cached tree that no longer exists misses" "miss" "$(chit >/dev/null && echo hit || echo miss)"
reset_files

# disable switch
fresh_state; cput
check "TESTRUN_DISABLE turns the cache off" "miss" "$(TESTRUN_DISABLE=1 chit >/dev/null && echo hit || echo miss)"

# database names
fresh_state
TOP="$TMP/some-worktree"; mkdir -p "$TOP"
SLUG2=$(lib tr_slug "$TOP")
check "a test database name gets the worktree slug" "zeit_testing_$SLUG2" "$(lib tr_db_name zeit_testing "$TOP")"
check "an already suffixed name is not suffixed twice" "zeit_testing_$SLUG2" "$(lib tr_db_name "zeit_testing_$SLUG2" "$TOP")"
check "a name that is not a test database aborts" "1" "$(lib tr_db_name zeit_production "$TOP" >/dev/null 2>&1; echo $?)"
check "a production-like name never gets a suffix" "1" "$(lib tr_db_name events "$TOP" >/dev/null 2>&1; echo $?)"
lib tr_db_register "zeit_testing_$SLUG2"; lib tr_db_register "zeit_testing_$SLUG2"; lib tr_db_register "other_testing_aaaaaaaa"
check "registering is idempotent" "2" "$(grep -c . "$TESTRUN_STATE_DIR/test-dbs.list")"
check "a name with odd characters is refused" "1" "$(lib tr_db_register 'a";drop' >/dev/null 2>&1; echo $?)"

# cleanup drops only listed names and their paratest workers
cat > "$TMP/fake-psql" <<'FEOF'
#!/bin/bash
echo "$*" >> "$(dirname "$0")/psql.log"
case "$*" in
  *"from pg_database"*) printf '%s\n' $FAKE_PG_ROWS ;;
esac
FEOF
: > "$TMP/psql.log"
export TESTRUN_PSQL="$TMP/fake-psql"
export FAKE_PG_ROWS="zeit_testing_$SLUG2 zeit_testing_${SLUG2}_test_1 zeit_testing_${SLUG2}_test_2 zeit_testing_${SLUG2}_testing_x zeit_production"
lib tr_worktree_cleanup "$TOP"
check "cleanup drops the listed database and its two workers only" "3" "$(grep -c 'DROP DATABASE' "$TMP/psql.log")"
check "the drop uses WITH (FORCE) and quotes the name" "yes" "$(grep -q "DROP DATABASE IF EXISTS \"zeit_testing_$SLUG2\" WITH (FORCE)" "$TMP/psql.log" && echo yes || echo no)"
check "a database the registry does not list is never dropped" "0" "$(grep 'DROP' "$TMP/psql.log" | grep -c 'zeit_production\|testing_x\|other_testing')"
check "the cleaned names leave the registry, other worktrees stay" "other_testing_aaaaaaaa" "$(cat "$TESTRUN_STATE_DIR/test-dbs.list")"
unset FAKE_PG_ROWS

# @@PARTS@@

[ "$FAIL" -eq 0 ] && echo "LIB_TESTRUN_TEST=OK" || { echo "LIB_TESTRUN_TEST=FAIL ($FAIL)"; exit 1; }
