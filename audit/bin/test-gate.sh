#!/usr/bin/env bash
# Helper of `deploy <app> test` (~/.local/bin/deploy): one machine-wide slot for full suites plus a
# run wrapper that reruns flaky browser tests once. All logic lives here so it can be tested; deploy
# only calls it.
#
# Usage: test-gate.sh slot-acquire <app> [owner-pid]   wait for the slot, then take it (exit 75 after SLOT_WAIT_MAX)
#        test-gate.sh slot-release <pid>               release the slot if <pid> owns it, else no-op
#        test-gate.sh run <test-cmd> <file-cmd>        run <test-cmd>; on red browser failures rerun each file once
# Env:   TEST_GATE_APP (app name for the flake log), TEST_GATE_STATE_DIR (default ~/.local/state/claude),
#        SLOT_WAIT_MAX (900), SLOT_NOTICE_SECONDS (30), SLOT_POLL_SECONDS (2)
#
# Slot: mkdir at $STATE_DIR/full-suite.slot, NOT under $TMPDIR (a sandboxed Claude Code shell sees a
# different TMPDIR, the failure test-lock.sh documents) and not per repo (test-lock.sh is per repo, so
# two projects' suites ran at the same time and overbooked the Mac, 2026-10-05). The slot stores pid,
# app, acquisition time and the owner's process start time (`ps -o lstart=`): a holder counts as alive
# only if the PID exists AND its start time matches, which survives PID reuse. The wait cap (900 s)
# stays below test-lock.sh's 960 s because /audit wraps `deploy events test` in test-lock.sh and
# holds the repo lock while this script waits. Without an owner-pid argument the owner is the caller
# ($PPID), so deploy's `slot-release $$` matches.
#
# Run: the first pass and the reruns share the caller's one test-lock, gtimeout and watchdog, and all
# output goes to the caller's log. A rerun happens only if all of these hold: the Pest summary
# ("Tests: N failed") is present and equals the number of `FAILED  Tests\...` lines, every failure is a
# Tests\Browser class, 1-5 distinct files, and the output has no fatal/worker-crash marker. Each file
# reruns once via `<file-cmd> <path>`. All reruns green: exit 0, one `FLAKY:` line per file, appended to
# $STATE_DIR/test-flakes.jsonl; a file already flaky within FLAKE_DAYS (14) fails hard instead. The test
# key is the class, because Pest truncates the test name to the terminal width. Non-zero exits of the
# test command that name no failure (signals, crashes) pass through unchanged for the caller to report.
# Parsing runs in the C locale: the truncated name line can end inside a UTF-8 character.
#
# bash 3.2 compatible (macOS default).

set -u

STATE_DIR="${TEST_GATE_STATE_DIR:-$HOME/.local/state/claude}"
SLOT="$STATE_DIR/full-suite.slot"
FLAKES="$STATE_DIR/test-flakes.jsonl"
SLOT_WAIT_MAX=${SLOT_WAIT_MAX:-900}
SLOT_NOTICE_SECONDS=${SLOT_NOTICE_SECONDS:-30}
SLOT_POLL_SECONDS=${SLOT_POLL_SECONDS:-2}
FLAKE_DAYS=14
APP="${TEST_GATE_APP:-unknown}"
CAP=""

slot_reap() {  # atomic rename first, so two reapers never delete a slot the other has recreated
  local reap="$SLOT.reap.$$.$RANDOM"
  mv "$SLOT" "$reap" 2>/dev/null && rm -rf "$reap"
}

slot_holder_alive() {
  local pid start cur
  pid=$(cat "$SLOT/pid" 2>/dev/null || true)
  start=$(cat "$SLOT/start" 2>/dev/null || true)
  [ -n "$pid" ] && [ -n "$start" ] || return 1
  cur=$(ps -o lstart= -p "$pid" 2>/dev/null || true)
  [ -n "$cur" ] && [ "$cur" = "$start" ]
}

slot_acquire() {
  local app=${1:-unknown} owner=${2:-$PPID} t0 now waited next_notice=0 holder happ since
  mkdir -p "$STATE_DIR" 2>/dev/null || {
    echo "[deploy] Slot-Verzeichnis nicht schreibbar ($STATE_DIR): Testlauf ohne globalen Slot" >&2
    return 0
  }
  t0=$(date +%s)
  while ! mkdir "$SLOT" 2>/dev/null; do
    [ -d "$SLOT" ] || continue   # released between our mkdir and now
    holder=$(cat "$SLOT/pid" 2>/dev/null || true)
    [ -n "$holder" ] || { sleep 1; holder=$(cat "$SLOT/pid" 2>/dev/null || true); }   # holder is still writing its files
    if [ -z "$holder" ] || ! slot_holder_alive; then
      echo "[deploy] Verwaister Slot (PID ${holder:-?} tot oder wiederverwendet), uebernehme"
      slot_reap
      continue
    fi
    now=$(date +%s); waited=$((now - t0))
    happ=$(cat "$SLOT/app" 2>/dev/null || echo "?")
    if [ "$waited" -ge "$SLOT_WAIT_MAX" ]; then
      echo "[deploy] Slot nach ${waited}s nicht frei, belegt: $happ (PID $holder). Gebe auf." >&2
      return 75
    fi
    if [ "$waited" -ge "$next_notice" ]; then
      since=$((now - $(cat "$SLOT/since" 2>/dev/null || echo "$now")))
      echo "[deploy] Slot belegt: $happ (PID $holder, seit ${since}s), warte"
      next_notice=$((waited + SLOT_NOTICE_SECONDS))
    fi
    sleep "$SLOT_POLL_SECONDS"
  done
  echo "$owner" > "$SLOT/pid"
  echo "$app" > "$SLOT/app"
  date +%s > "$SLOT/since"
  ps -o lstart= -p "$owner" 2>/dev/null > "$SLOT/start" || true
}

slot_release() {
  local pid=${1:-}
  [ -n "$pid" ] && [ "$(cat "$SLOT/pid" 2>/dev/null || true)" = "$pid" ] || return 0
  slot_reap
}

strip_ansi() { sed "s/$(printf '\033')\[[0-9;]*[A-Za-z]//g"; }

prior_flaky() {  # $1=class: flaky for this app within FLAKE_DAYS?
  local esc=${1//\\/\\\\} cutoff
  [ -f "$FLAKES" ] || return 1
  cutoff=$(( $(date +%s) - FLAKE_DAYS * 86400 ))
  grep -F "\"app\":\"$APP\"" "$FLAKES" | grep -F "\"test\":\"$esc\"" \
    | sed -n 's/.*"ts":\([0-9]*\).*/\1/p' | awk -v c="$cutoff" '$1 >= c { f = 1 } END { exit f ? 0 : 1 }'
}

record_flake() {  # $1=class $2=workers
  local esc=${1//\\/\\\\}
  mkdir -p "$STATE_DIR" 2>/dev/null || return 0
  printf '{"ts":%s,"date":"%s","app":"%s","test":"%s","workers":%s}\n' \
    "$(date +%s)" "$(date +%Y-%m-%d)" "$APP" "$esc" "$2" >> "$FLAKES" 2>/dev/null || true
}

# Exit code for a red run we do not recover: a signal-range code passes through so the caller can
# name it, everything else is a plain 1.
red_exit() { [ "$1" -ge 129 ] && [ "$1" -le 159 ] && exit "$1"; exit 1; }

run_gate() {
  local test_cmd=${1:-} file_cmd=${2:-} rc clean fails nfail summary nbrowser classes nfiles why workers
  local class p rrc flaked="" hard="" reruns=0
  [ -n "$test_cmd" ] && [ -n "$file_cmd" ] || { echo "usage: test-gate.sh run <test-cmd> <file-cmd>" >&2; exit 64; }
  CAP=$(mktemp "${TMPDIR:-/tmp}/test-gate-out.XXXXXX" 2>/dev/null) || { bash -c "$test_cmd"; exit $?; }
  trap 'rm -f "$CAP"' EXIT
  bash -c "$test_cmd" 2>&1 | tee "$CAP"
  rc=${PIPESTATUS[0]}
  [ "$rc" -eq 0 ] && exit 0

  export LC_ALL=C
  clean=$(strip_ansi < "$CAP")
  fails=$(printf '%s\n' "$clean" | grep -E '^[[:space:]]*FAILED[[:space:]]' || true)
  [ -n "$fails" ] || red_exit "$rc"   # no named failure: crash, signal or timeout, the caller reports it

  nfail=$(printf '%s\n' "$fails" | grep -c .)
  summary=$(printf '%s\n' "$clean" | grep -E '^[[:space:]]*Tests:' | grep -oE '[0-9]+ failed' | head -1 | cut -d' ' -f1)
  nbrowser=$(printf '%s\n' "$fails" | grep -cE 'FAILED[[:space:]]+Tests\\Browser\\')
  classes=$(printf '%s\n' "$fails" | awk '{ print $2 }' | sort -u)
  nfiles=$(printf '%s\n' "$classes" | grep -c .)
  workers=$(printf '%s\n' "$clean" | sed -n 's/^[[:space:]]*Parallel:[[:space:]]*\([0-9][0-9]*\) processes.*/\1/p' | tail -1)
  workers=${workers:-1}

  why=""
  if [ -z "$summary" ]; then why="keine Pest-Zusammenfassung ('Tests: N failed')"
  elif [ "$nfail" != "$summary" ]; then why="$nfail FAILED-Zeilen, die Zusammenfassung nennt $summary"
  elif [ "$nbrowser" != "$nfail" ]; then why="nicht nur Browser-Tests rot"
  elif [ "$nfiles" -gt 5 ]; then why="$nfiles Browser-Dateien rot (mehr als 5, kein Flake-Muster)"
  elif printf '%s\n' "$clean" | grep -qE 'Fatal error|Segmentation fault|[Ww]orker.*(crash|exited|died|terminated)'; then
    why="Fatal-/Worker-Absturz in der Ausgabe"
  fi
  if [ -n "$why" ]; then
    echo "[test-gate] Kein Rerun: $why"
    printf '%s\n' "$fails" | head -20
    red_exit "$rc"
  fi

  for class in $classes; do
    p=${class//\\//}; p="tests/${p#Tests/}.php"
    echo "[test-gate] Rerun: $p"
    reruns=$((reruns + 1))
    bash -c "$file_cmd $(printf '%q' "$p")"; rrc=$?
    if [ "$rrc" -ne 0 ]; then
      echo "[test-gate] Rerun ROT: $p. Erster Lauf:"
      printf '%s\n' "$fails" | head -20
      exit 1
    fi
    if prior_flaky "$class"; then hard="$hard $class"; fi
    record_flake "$class" "$workers"
    flaked="$flaked $class"
  done
  for class in $flaked; do echo "FLAKY: $class (im ersten Lauf rot, im Rerun gruen, Worker: $workers)"; done
  if [ -n "$hard" ]; then
    for class in $hard; do echo "[test-gate] $class war in den letzten $FLAKE_DAYS Tagen schon flaky: Gate rot"; done
    exit 1
  fi
  exit 0
}

case "${1:-}" in
  slot-acquire) slot_acquire "${2:-}" "${3:-}"; exit $? ;;
  slot-release) slot_release "${2:-}"; exit 0 ;;
  run)          run_gate "${2:-}" "${3:-}" ;;
  *) echo "usage: test-gate.sh slot-acquire <app> [pid] | slot-release <pid> | run <test-cmd> <file-cmd>" >&2; exit 64 ;;
esac
