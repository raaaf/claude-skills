#!/usr/bin/env bash
# Pins lib-testrun.sh. Everything runs against a temp state dir and fake processes (sleep, bash loops);
# nothing here reads or writes ~/.local/state/claude or ~/.cache/xcodebuild-slot, or kills a real process.
# Part 1a: ticket store, admission (caps, global budget, stagger, FIFO, pressure, dead holders), nesting,
# event log, TESTRUN_DISABLE. Further parts are appended below by the later steps.
# Usage: bash audit/bin/lib-testrun.test.sh
set -u
HERE=$(cd "$(dirname "$0")" && pwd)
LIB="$HERE/lib-testrun.sh"
TMP=$(mktemp -d "${TMPDIR:-/tmp}/lib-testrun-test.XXXXXX")
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

# @@PARTS@@

[ "$FAIL" -eq 0 ] && echo "LIB_TESTRUN_TEST=OK" || { echo "LIB_TESTRUN_TEST=FAIL ($FAIL)"; exit 1; }
