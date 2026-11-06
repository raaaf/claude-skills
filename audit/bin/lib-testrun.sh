#!/usr/bin/env bash
# Shared test-run infrastructure, sourced (never executed) by test-lock.sh, test-gate.sh, test-status.sh,
# mutate.sh, ~/.local/bin/deploy and the xcodebuild shim. All functions carry the prefix `tr_` (public)
# or `_tr_` (internal) because the shim already defines `cleanup`, `field` and `nap`.
# Plan: docs/plans/2026-10-13-test-infra-parallel.md. bash 3.2 compatible, no jq.
#
# State (never under $TMPDIR: a sandboxed shell sees a different TMPDIR, see test-gate.sh history):
#   $STATE/runs/<id>      ticket, key=value: pid start class state project cwd args since admitted_at
#                         progress_at pgid pgid_start. id = <microsecond stamp>-<pid>, so names sort FIFO.
#                         A run is alive while its wrapper (pid + `ps -o lstart=`) OR its process group lives.
#   $STATE/slots/<c>.<n>  numbered mkdir slots (c = xcode | suite | global), file `id` names the holder
#   $STATE/test-events.jsonl   one line per event, same shape as run-log.sh, plus a `TESTRUN <event> k=v`
#                         line on stderr so a background run can be followed with the Monitor tool
# $STATE = $TESTRUN_STATE_DIR, else $TEST_GATE_STATE_DIR, else ~/.local/state/claude.
#
# Layers: the outermost layer (deploy, test-lock, test-gate or the shim) admits the run and exports
# TESTRUN_ID; inner layers see a live ticket for that id and only refresh progress_at.
# Emergency switch: TESTRUN_DISABLE=1 turns every function into a no-op / plain pass-through, and the
# callers fall back to their pre-lib behaviour.
#
# Env (all optional, mostly for tests):
#   TESTRUN_CAP_XCODE (2) TESTRUN_CAP_SUITE (2) TESTRUN_CAP_GLOBAL (3)   admission ceilings
#   TESTRUN_WAIT_MAX (900) TESTRUN_NOTICE (30) TESTRUN_ADMIT_POLL (2)    waiting
#   TESTRUN_STAGGER (30)        seconds a later candidate waits after any admission
#   TESTRUN_PRESSURE, TESTRUN_FREE_PCT   override kern.memorystatus_vm_pressure_level / `memory_pressure -Q`
#   TESTRUN_WORKERS_ALONE (8)   worker budget of a heavy run that runs alone; see tr_workers
#   TESTRUN_NICE (10)           nice increment for admitted `suite` runs (0 = off); TESTRUN_NICE_XCODE (0) for `xcode`
#   TESTRUN_SIM_CAP (2)         booted test simulators machine-wide; a third xcode run waits (see _tr_sim_cap_ok)
#   TESTRUN_SIM_GRACE (300)     seconds a simulator stays booted after its last test run, then it is shut down
#   TESTRUN_SWAP_LIMIT_PCT (80) TESTRUN_SWAP_WAIT (120)   swap gate, see _tr_extra_gate
#   TESTRUN_SIMCTL (xcrun simctl)  TESTRUN_SIM_AGES, TESTRUN_SWAPUSAGE   test overrides
# Exported to the admitted command: TESTRUN_WORKERS (parallel test processes), TESTRUN_BROWSER_WORKERS (browser
# processes, at most 6). Pest/Paratest has no env var for the process count, so a project script passes them on
# (`--processes=${TESTRUN_WORKERS:-...}`); TESTRUN_BAIL=1 (set by the deploy gate) asks for stop-on-first-failure.

_TR_LIB_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)

tr_enabled() { [ "${TESTRUN_DISABLE:-}" != 1 ]; }

_tr_state() { printf '%s' "${TESTRUN_STATE_DIR:-${TEST_GATE_STATE_DIR:-$HOME/.local/state/claude}}"; }
_tr_runs() { printf '%s/runs' "$(_tr_state)"; }
_tr_slots() { printf '%s/slots' "$(_tr_state)"; }
_tr_now() { date +%s; }
_tr_lstart() { ps -o lstart= -p "$1" 2>/dev/null | sed 's/^ *//;s/ *$//'; }
_tr_field() { sed -n "s/^$1=//p" "$2" 2>/dev/null | head -1; }
_tr_nap() { sleep "$1" & wait $! 2>/dev/null; }

# Repo name for display and event rows: the main checkout's directory, also from a linked worktree.
tr_project() {
  local c
  c=$(cd "${1:-.}" 2>/dev/null && git rev-parse --path-format=absolute --git-common-dir 2>/dev/null) || c=""
  if [ -n "$c" ]; then basename "$(dirname "$c")"; else basename "$(cd "${1:-.}" 2>/dev/null && pwd)"; fi
}

# Value of `<key>:` in <root>/.claude/ship.md (same rule as orch_ship_value), rc 1 when absent.
tr_ship_value() {
  local v
  v=$(sed -n "s/^$1:[[:space:]]*//p" "${2:-.}/.claude/ship.md" 2>/dev/null | head -1 | sed 's/[[:space:]]*$//')
  [ -n "$v" ] || return 1
  printf '%s' "$v"
}

# --- event log ---------------------------------------------------------------------------------
# tr_event <name> [k=v ...]
tr_event() {
  tr_enabled || return 0
  local name=$1 kv k v line="" extra="" state
  shift
  local proj=${TESTRUN_PROJECT:-}
  for kv in "$@"; do
    k=${kv%%=*}; v=${kv#*=}
    if [ "$k" = project ]; then proj=$v; line="$line project=$v"; continue; fi
    v=${v//\\/\\\\}; v=${v//\"/\\\"}; v=$(printf '%s' "$v" | tr '\n\t' '  ')
    extra="$extra,\"$k\":\"$v\""
    line="$line $k=$v"
  done
  printf 'TESTRUN %s%s\n' "$name" "$line" >&2
  state=$(_tr_state)
  mkdir -p "$state" 2>/dev/null || return 0
  printf '{"ts":%s,"date":"%s","event":"%s","id":"%s","project":"%s"%s}\n' \
    "$(_tr_now)" "$(date +%Y-%m-%d)" "$name" "${TESTRUN_ID:-}" "$proj" "$extra" \
    >> "$state/test-events.jsonl" 2>/dev/null || true
}

# --- tickets -----------------------------------------------------------------------------------
_tr_ticket() { printf '%s/%s' "$(_tr_runs)" "$1"; }

# _tr_set <id> <key> <value>: atomic rewrite of one ticket line (only the owner writes its ticket)
_tr_set() {
  local f tmp
  f=$(_tr_ticket "$1"); [ -f "$f" ] || return 1
  tmp="$f.tmp.$$"
  { grep -v "^$2=" "$f"; printf '%s=%s\n' "$2" "$3"; } > "$tmp" 2>/dev/null && mv "$tmp" "$f"
}

_tr_group_alive() {  # <pgid> <leader-start>: group has members and its pid was not reused by a stranger
  local cur
  [ -n "${1:-}" ] && kill -0 -- "-$1" 2>/dev/null || return 1
  cur=$(_tr_lstart "$1")
  [ -z "$cur" ] || [ "$cur" = "${2:-}" ]
}

_tr_wrapper_alive() {  # <ticket file>
  local pid start
  pid=$(_tr_field pid "$1"); start=$(_tr_field start "$1")
  [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null && [ "$(_tr_lstart "$pid")" = "$start" ]
}

_tr_alive() {  # <ticket file>: wrapper OR process group lives
  _tr_wrapper_alive "$1" || _tr_group_alive "$(_tr_field pgid "$1")" "$(_tr_field pgid_start "$1")"
}

# Remove tickets that are dead (atomic mv first, so two pruners never race on a recreated name).
_tr_prune() {
  local f name
  for f in "$(_tr_runs)"/*-*; do
    [ -f "$f" ] || continue
    name=${f##*/}
    case "$name" in *.*) continue ;; esac
    _tr_alive "$f" || { mv "$f" "$f.dead.$$" 2>/dev/null && rm -f "$f.dead.$$" "$f.out" "$f.out.1" "$f.out.2"; }
  done
}

_tr_live_ids() {  # oldest first
  local f name
  for f in "$(_tr_runs)"/*-*; do
    [ -f "$f" ] || continue
    name=${f##*/}
    case "$name" in *.*) continue ;; esac
    echo "$name"
  done | sort
}

_tr_nested() {
  [ -n "${TESTRUN_ID:-}" ] && [ -f "$(_tr_ticket "$TESTRUN_ID")" ] && _tr_alive "$(_tr_ticket "$TESTRUN_ID")"
}

# Inner layers call this: only progress_at moves, no admission, watchdog or restart.
tr_progress() { [ -n "${TESTRUN_ID:-}" ] && _tr_set "$TESTRUN_ID" progress_at "$(_tr_now)"; return 0; }

# --- pressure and caps ---------------------------------------------------------------------------
_tr_pressure_level() {  # 1 | 2 | 4 ... | "" (unreadable)
  local v
  if [ -n "${TESTRUN_PRESSURE+x}" ]; then printf '%s' "$TESTRUN_PRESSURE"; return; fi
  v=$(sysctl -n kern.memorystatus_vm_pressure_level 2>/dev/null)
  case "$v" in ''|*[!0-9]*) ;; *) printf '%s' "$v" ;; esac
}

_tr_free_pct() {  # integer percent, 0 when unreadable
  local v
  if [ -n "${TESTRUN_FREE_PCT+x}" ]; then printf '%s' "$TESTRUN_FREE_PCT"; return; fi
  v=$(memory_pressure -Q 2>/dev/null | sed -n 's/.*free percentage:[[:space:]]*\([0-9]*\)%.*/\1/p' | head -1)
  printf '%s' "${v:-0}"
}

# tr_pressure_ok <heavy runs already active>. Level 1 admits; level 2 (flips with level 1 every minute on
# this Mac, even with 39 % free and no simulator booted) admits next to two active heavy runs with
# >= 35 % free, next to one with >= 25 % free, otherwise only into an idle machine; level 4 and above
# waits; unreadable behaves like level 2 with 0 % free. 35 % was set 2026-10-27 after 14 days without a
# swap incident, when 1.646 of 2.258 wait/admit events fell on level 2.
tr_pressure_ok() {
  local level free active=${1:-0} max
  level=$(_tr_pressure_level)
  case "$level" in
    1) return 0 ;;
    '') max=0 ;;
    2|3) free=$(_tr_free_pct)
         if [ "${free:-0}" -ge 35 ]; then max=2; elif [ "${free:-0}" -ge 25 ]; then max=1; else max=0; fi ;;
    *) return 1 ;;
  esac
  [ "$active" -le "$max" ]
}

# Ceiling for a class. A guard file (written by _tr_xcode_guard) pins xcode to 1 for 24 h.
tr_cap() {
  local until
  case "$1" in
    xcode)
      until=$(cat "$(_tr_state)/xcode-cap-until" 2>/dev/null)
      if [ -n "$until" ] && [ "$until" -gt "$(_tr_now)" ] 2>/dev/null; then echo 1; else echo "${TESTRUN_CAP_XCODE:-2}"; fi ;;
    suite)  echo "${TESTRUN_CAP_SUITE:-2}" ;;
    global) echo "${TESTRUN_CAP_GLOBAL:-3}" ;;
    *)      echo 1 ;;
  esac
}

# tr_workers <heavy runs active, this one included>: parallel test processes for a run, decided once at admission.
# 12 cores: 8 alone, 4 with two heavy runs, 3 with three, never below 2 (a full-suite --parallel run used all 12
# cores per suite, so two suites oversubscribed the Mac).
tr_workers() {
  local n=${1:-1}
  if [ "$n" -le 1 ]; then echo "${TESTRUN_WORKERS_ALONE:-8}"
  elif [ "$n" -eq 2 ]; then echo 4
  elif [ "$n" -eq 3 ]; then echo 3
  else echo 2; fi
}
tr_browser_workers() {  # <workers>: browser processes are heavier (Playwright), capped at 6
  if [ "${1:-8}" -gt 6 ]; then echo 6; else echo "${1:-8}"; fi
}

_tr_active() {  # <class|"heavy"> [exclude id]: running tickets of a class (heavy = xcode + suite)
  local id f c n=0
  for id in $(_tr_live_ids); do
    [ "$id" = "${2:-}" ] && continue
    f=$(_tr_ticket "$id")
    [ "$(_tr_field state "$f")" = running ] || continue
    c=$(_tr_field class "$f")
    if [ "$1" = heavy ]; then case "$c" in xcode|suite) n=$((n + 1)) ;; esac
    elif [ "$c" = "$1" ]; then n=$((n + 1)); fi
  done
  echo "$n"
}

# --- slots -------------------------------------------------------------------------------------
_tr_slot_reap() { mv "$1" "$1.reap.$$.$RANDOM" 2>/dev/null && rm -rf "$1".reap.* 2>/dev/null; return 0; }

_tr_slot_try() {  # <class> <n> <id>: take slot, reaping it first when its holder is gone
  local d holder
  d="$(_tr_slots)/$1.$2"
  mkdir "$d" 2>/dev/null && { echo "$3" > "$d/id"; return 0; }
  holder=$(cat "$d/id" 2>/dev/null)
  if [ -z "$holder" ]; then
    [ $(( $(_tr_now) - $(stat -f %m "$d" 2>/dev/null || echo "$(_tr_now)") )) -gt 10 ] || return 1
  elif [ -f "$(_tr_ticket "$holder")" ]; then
    return 1
  fi
  _tr_slot_reap "$d"
  mkdir "$d" 2>/dev/null && { echo "$3" > "$d/id"; return 0; }
  return 1
}

_tr_slot_take() {  # <class> <id>: class slot plus global slot, or nothing
  local n cap gcap g=0
  cap=$(tr_cap "$1"); gcap=$(tr_cap global)
  n=1
  while [ "$n" -le "$cap" ]; do
    if _tr_slot_try "$1" "$n" "$2"; then
      g=1
      while [ "$g" -le "$gcap" ]; do
        _tr_slot_try global "$g" "$2" && return 0
        g=$((g + 1))
      done
      _tr_slot_reap "$(_tr_slots)/$1.$n"
      return 1
    fi
    n=$((n + 1))
  done
  return 1
}

_tr_slots_free() {  # <id>: drop every slot the id holds
  local d
  for d in "$(_tr_slots)"/*; do
    [ -d "$d" ] || continue
    case "$d" in *.reap.*) continue ;; esac
    [ "$(cat "$d/id" 2>/dev/null)" = "$1" ] && _tr_slot_reap "$d"
  done
  return 0
}

_tr_holders() {  # one line per running heavy ticket, for the give-up message
  local id f
  for id in $(_tr_live_ids); do
    f=$(_tr_ticket "$id")
    [ "$(_tr_field state "$f")" = running ] || continue
    printf '  %s (%s, pid %s, %ss) in %s\n' "$(_tr_field project "$f")" "$(_tr_field class "$f")" \
      "$(_tr_field pid "$f")" "$(( $(_tr_now) - $(_tr_field since "$f") ))" "$(_tr_field cwd "$f")"
  done
}

# --- simulators and swap -------------------------------------------------------------------------
# A booted simulator costs 1-5 GB. Three things keep them from piling up: the cap below (a third xcode run waits),
# the shutdown after the last run (tr_sim_release), and mac-cleanup.sh --reconcile as the safety net. All three
# read the same registry (the tickets): a device with any live ticket is in use and is never shut down. When the
# registry cannot be read, nothing is shut down.

# tr_udid_of <word...>: the simulator id of a `-destination ...id=<UDID>` argument, empty when there is none
tr_udid_of() {
  local a u
  for a in "$@"; do
    case "$a" in *id=*) u=$(printf '%s' "$a" | grep -oE 'id=[0-9A-Fa-f-]+' | head -1 | cut -c4-); [ -n "$u" ] && { printf '%s' "$u"; return 0; } ;; esac
  done
  return 0
}

# _tr_simctl <timeout seconds> args...: simctl under an alarm (a stuck CoreSimulatorService must not stall the
# admission loop or a reaper). TESTRUN_SIMCTL is a path only: zsh does not word-split.
_tr_simctl() {
  local t=$1; shift
  if [ -n "${TESTRUN_SIMCTL:-}" ]; then perl -e 'alarm shift; exec @ARGV or exit 127' "$t" "$TESTRUN_SIMCTL" "$@"
  else perl -e 'alarm shift; exec @ARGV or exit 127' "$t" xcrun simctl "$@"; fi
}
# _tr_devices: "name|udid|state" for every simulator; rc 1 when simctl failed or timed out (TESTRUN_SIMCTL_TIMEOUT, 15)
_tr_devices() {
  local out
  out=$(_tr_simctl "${TESTRUN_SIMCTL_TIMEOUT:-15}" list devices 2>/dev/null) || return 1
  printf '%s\n' "$out" | sed -n 's/^ *\(.*\) (\([0-9A-Fa-f-]\{36\}\)) (\([A-Za-z ]*\)) *$/\1|\2|\3/p'
}
_tr_booted_sims() { _tr_devices | awk -F'|' '$3 == "Booted" { print $2 "|" $1 }'; }
_tr_sim_name() { _tr_devices | awk -F'|' -v u="$1" '$2 == u { print $1; exit }'; }
_tr_sim_is_test() { case "$1" in *-test|*-test-[0-9]|*-test-[0-9][0-9]) return 0 ;; esac; return 1; }
_tr_registry_ok() { local d; d=$(_tr_runs); [ -d "$d" ] && [ -r "$d" ] && [ -x "$d" ]; }

# The device of a ticket: its `udid` field, else the id in the wrapper's own command line (tickets written before the
# field existed, or by a layer that never saw the arguments).
_tr_ticket_udid() {
  local u
  u=$(_tr_field udid "$1")
  [ -n "$u" ] || u=$(tr_udid_of "$(ps -o command= -p "$(_tr_field pid "$1")" 2>/dev/null)")
  printf '%s' "$u"
}

# tr_sim_owner <udid> [exclude id]: "<project> pid <pid>" of the first live run on that device, rc 0 when there is one
tr_sim_owner() {
  local id f
  for id in $(_tr_live_ids); do
    [ "$id" = "${2:-}" ] && continue
    f=$(_tr_ticket "$id")
    _tr_alive "$f" || continue
    [ "$(_tr_ticket_udid "$f")" = "$1" ] || continue
    printf '%s pid %s' "$(_tr_field project "$f")" "$(_tr_field pid "$f")"; return 0
  done
  return 1
}

# A running xcode run whose destination carried no id (by name, or hidden in a script): it may use any device.
_tr_sim_unknown_run() {
  local id f
  for id in $(_tr_live_ids); do
    [ "$id" = "${1:-}" ] && continue
    f=$(_tr_ticket "$id")
    _tr_alive "$f" || continue
    [ "$(_tr_field class "$f")" = xcode ] && [ "$(_tr_field state "$f")" = running ] && [ -z "$(_tr_ticket_udid "$f")" ] || continue
    # a script-wrapped run hides its device; it blocks shutdowns only for TESTRUN_UNKNOWN_RUN_MAX (3600) s, so a stuck
    # ticket cannot keep every simulator booted for good. Until then mac-cleanup.sh --reconcile is the fallback.
    [ $(( $(_tr_now) - $(_tr_field since "$f") )) -lt "${TESTRUN_UNKNOWN_RUN_MAX:-3600}" ] && return 0
  done
  return 1
}
tr_sim_busy() { tr_sim_owner "$@" >/dev/null || _tr_sim_unknown_run "${2:-}"; }

# tr_sim_age <udid>: seconds the simulator has been booted (age of its launchd_sim), empty when unknown
tr_sim_age() {
  local pid
  if [ -n "${TESTRUN_SIM_AGES+x}" ]; then printf '%s\n' "$TESTRUN_SIM_AGES" | awk -v u="$1" '$1 == u { print $2 }'; return 0; fi
  pid=$(pgrep -f "launchd_sim.*Devices/$1/" 2>/dev/null | head -1)
  [ -n "$pid" ] && _tr_etime_s "$pid"
  return 0
}

# tr_sim_shutdown_if_idle <udid> <reason> [exclude id]: shut the device down unless the registry is unreadable or a run uses it
tr_sim_shutdown_if_idle() {
  _tr_registry_ok || { tr_event sim_keep udid="$1" reason=registry-unreadable; return 1; }
  _tr_prune
  if tr_sim_busy "$1" "${3:-}"; then tr_event sim_keep udid="$1" reason=in-use; return 1; fi
  _tr_simctl "${TESTRUN_SIMCTL_SHUTDOWN_TIMEOUT:-30}" shutdown "$1" >/dev/null 2>&1 || return 1
  tr_event sim_shutdown udid="$1" reason="$2"
}

_tr_sim_reaper() {  # <udid> [exclude id]: wait out the grace period (a newer run end extends it), then shut down if idle
  local dir ended wait
  dir="$(_tr_state)/sims"
  while :; do
    ended=$(cat "$dir/$1.ended" 2>/dev/null); [ -n "$ended" ] || break
    wait=$(( ended + ${TESTRUN_SIM_GRACE:-300} - $(_tr_now) ))
    [ "$wait" -gt 0 ] || { tr_sim_shutdown_if_idle "$1" after-run "${2:-}"; break; }
    _tr_nap "$wait"
  done
  rm -f "$dir/$1.reaper"
}

# tr_sim_release <udid> [exclude id]: a test run on that device ended. One detached reaper per device shuts it
# down after TESTRUN_SIM_GRACE seconds unless a run uses it by then, so an agent's next filtered run reuses the
# booted device and only an idle one is paid for. Its output is closed: it must not hold the caller's pipe.
tr_sim_release() {
  tr_enabled && [ -n "${1:-}" ] || return 0
  local dir pid
  _tr_sim_is_test "$(_tr_sim_name "$1")" || return 0   # only -test devices get a reaper; the others are left to mac-cleanup.sh --reconcile
  dir="$(_tr_state)/sims"
  mkdir -p "$dir" 2>/dev/null || return 0
  _tr_now > "$dir/$1.ended"
  pid=$(cat "$dir/$1.reaper" 2>/dev/null)
  [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null && return 0
  { set -m; ( _tr_sim_reaper "$1" "${2:-}" ) >/dev/null 2>&1 </dev/null & pid=$!; set +m; } 2>/dev/null
  echo "$pid" > "$dir/$1.reaper"
}

# _tr_sim_cap_check <udid> <own id>: sets _TR_CAP_BLOCK=1 when a run on that device would be the third booted test
# simulator (TESTRUN_SIM_CAP, 2). Runs before the admission mutex, so a slow simctl never holds it up. Counted are
# booted "*-test" / "*-test-<n>" devices plus those of running xcode tickets (a device that is still booting). No cap
# for a device simctl does not list (a physical iPhone), one that is already booted, or when simctl fails or times out.
# Idle booted test devices that no ticket uses are shut down first to make room.
_tr_sim_cap_check() {
  local devs n u st running others="" cnt=0 listed=0 mine=0 id f
  _TR_CAP_BLOCK=0
  devs=$(_tr_devices) && [ -n "$devs" ] || return 0
  running=""
  for id in $(_tr_live_ids); do
    [ "$id" = "$2" ] && continue
    f=$(_tr_ticket "$id")
    [ "$(_tr_field class "$f")" = xcode ] && [ "$(_tr_field state "$f")" = running ] && running="$running $(_tr_ticket_udid "$f")"
  done
  while IFS='|' read -r n u st; do
    [ -n "$u" ] || continue
    if [ "$u" = "$1" ]; then listed=1; [ "$st" = Booted ] && mine=1; continue; fi
    _tr_sim_is_test "$n" || continue
    case " $running " in *" $u "*) others="$others$u:$st "; cnt=$((cnt + 1)); continue ;; esac
    [ "$st" = Booted ] && { others="$others$u:$st "; cnt=$((cnt + 1)); }
  done <<<"$devs"
  [ "$listed" = 1 ] && [ "$mine" = 0 ] && [ "$cnt" -ge "${TESTRUN_SIM_CAP:-2}" ] || return 0
  for n in $others; do
    [ "$cnt" -ge "${TESTRUN_SIM_CAP:-2}" ] || break
    [ "${n#*:}" = Booted ] || continue
    tr_sim_shutdown_if_idle "${n%%:*}" cap-room "$2" && cnt=$((cnt - 1))
  done
  [ "$cnt" -ge "${TESTRUN_SIM_CAP:-2}" ] && _TR_CAP_BLOCK=1
  return 0
}

_tr_swap_raw() { if [ -n "${TESTRUN_SWAPUSAGE+x}" ]; then printf '%s' "$TESTRUN_SWAPUSAGE"; else sysctl -n vm.swapusage 2>/dev/null; fi; }
_SWAP_AWK='{ for (i = 1; i < NF; i++) { if ($i == "total") t = $(i + 2) + 0; if ($i == "used") u = $(i + 2) + 0 } }'
_tr_swap_pct() { _tr_swap_raw | awk "$_SWAP_AWK END { if (t > 0) printf \"%d\", u * 100 / t }"; }
_tr_swap_over() { _tr_swap_raw | awk -v lim="${TESTRUN_SWAP_LIMIT_PCT:-80}" "$_SWAP_AWK END { exit !(t > 0 && u * 100 > t * lim) }"; }

# _tr_extra_gate <class> <udid> <other heavy runs active> <seconds waited>: the two admission rules on top of the
# slots. Sets _TR_WHY (sim-cap | swap) when it says wait, _TR_OVERRIDE=1 when it lets a run through despite swap.
#  - sim-cap: _TR_CAP_BLOCK from _tr_sim_cap_check (xcode runs with a known simulator id only).
#  - swap: swap use above TESTRUN_SWAP_LIMIT_PCT (80) % of the current swap total plus memory stress holds a heavy run back, but only
#    while another heavy run is active (waiting helps only when something will finish: this Mac sits near 95 %
#    swap even when idle) and only for TESTRUN_SWAP_WAIT (120) seconds, far below TESTRUN_WAIT_MAX, so swap alone
#    never ends in a give-up.
# Swap alone is not a reason to wait (it stays high on a calm Mac): memory pressure level 2 or above, or free memory
# under TESTRUN_SWAP_FREE_PCT (25) %, has to say so too.
_tr_swap_stress() {
  case "$(_tr_pressure_level)" in ''|1) [ "$(_tr_free_pct)" -lt "${TESTRUN_SWAP_FREE_PCT:-25}" ] ;; *) return 0 ;; esac
}

_tr_extra_gate() {
  case "$1" in xcode|suite) ;; *) return 0 ;; esac
  if [ "$1" = xcode ] && [ "${_TR_CAP_BLOCK:-0}" = 1 ]; then _TR_WHY=sim-cap; return 1; fi
  if [ "${3:-0}" -ge 1 ] && _tr_swap_over && _tr_swap_stress; then
    if [ "${4:-0}" -lt "${TESTRUN_SWAP_WAIT:-120}" ]; then _TR_WHY=swap; return 1; fi
    _TR_OVERRIDE=1
  fi
  return 0
}

# --- admission ---------------------------------------------------------------------------------
# One decision at a time: the check-and-take below runs under a short mkdir mutex, otherwise two
# candidates both pass the stagger test and start together.
_tr_gate_enter() {
  local g age
  g="$(_tr_slots)/gate"
  mkdir "$g" 2>/dev/null && return 0
  age=$(( $(_tr_now) - $(stat -f %m "$g" 2>/dev/null || echo "$(_tr_now)") ))
  [ "$age" -gt 20 ] && _tr_slot_reap "$g"
  return 1
}
_tr_gate_leave() { rmdir "$(_tr_slots)/gate" 2>/dev/null; return 0; }

_tr_is_head() {  # <id> <class>: oldest live waiting ticket of the class (FIFO by stamp)
  local id f
  for id in $(_tr_live_ids); do
    f=$(_tr_ticket "$id")
    [ "$(_tr_field state "$f")" = waiting ] && [ "$(_tr_field class "$f")" = "$2" ] || continue
    # a waiter held back by the simulator cap does not block the FIFO for runs on booted devices (capblocked, see tr_admit)
    [ "$id" != "$1" ] && [ "$(_tr_field capblocked "$f")" = 1 ] && continue
    [ "$id" = "$1" ]; return $?
  done
  return 1
}

_tr_staggered() {  # <id>: another run was admitted less than TESTRUN_STAGGER seconds ago
  local id f at now
  now=$(_tr_now)
  for id in $(_tr_live_ids); do
    [ "$id" = "$1" ] && continue
    f=$(_tr_ticket "$id")
    [ "$(_tr_field state "$f")" = running ] || continue
    at=$(_tr_field admitted_at "$f")
    [ -n "$at" ] && [ $((now - at)) -lt "${TESTRUN_STAGGER:-30}" ] && return 0
  done
  return 1
}

_tr_stamp() { perl -MTime::HiRes=gettimeofday -e '($s,$u)=gettimeofday; printf "%010d%06d",$s,$u' 2>/dev/null || printf '%010d000000' "$(_tr_now)"; }

# tr_admit <class> <project> [owner-pid] [udid]: wait for admission, then export TESTRUN_ID. Returns 0 when
# admitted (also when nested, disabled or the state dir is unwritable), 75 after TESTRUN_WAIT_MAX.
tr_admit() {
  tr_enabled || return 0
  _tr_nested && return 0
  local class=$1 project=$2 owner=${3:-$$} udid=${4:-} id t0 now waited next_notice=0 active level
  mkdir -p "$(_tr_runs)" "$(_tr_slots)" 2>/dev/null || { echo "testrun: state dir not writable, running without admission" >&2; return 0; }
  id="$(_tr_stamp)-$owner"
  {
    printf 'pid=%s\nstart=%s\nclass=%s\nstate=waiting\nproject=%s\ncwd=%s\nargs=%s\nsince=%s\nudid=%s\n' \
      "$owner" "$(_tr_lstart "$owner")" "$class" "$project" "$PWD" "$(printf '%s' "${TESTRUN_ARGS:-}" | tr '\n' ' ')" "$(_tr_now)" "$udid"
  } > "$(_tr_ticket "$id").tmp.$$" && mv "$(_tr_ticket "$id").tmp.$$" "$(_tr_ticket "$id")"
  export TESTRUN_ID=$id TESTRUN_PROJECT=$project TESTRUN_OWNER_PID=$owner
  _tr_install_traps
  t0=$(_tr_now)
  while :; do
    tr_reap_dead_groups >/dev/null   # an orphaned group (wrapper died) must not keep its slot for good
    _tr_prune
    _TR_WHY=""; _TR_OVERRIDE=0; _TR_CAP_BLOCK=0
    if [ "$class" = xcode ] && [ -n "$udid" ]; then _tr_sim_cap_check "$udid" "$id"; _tr_set "$id" capblocked "$_TR_CAP_BLOCK"; fi
    if _tr_gate_enter; then
      active=$(_tr_active heavy "$id")
      if _tr_is_head "$id" "$class" && ! _tr_staggered "$id" && tr_pressure_ok "$active" \
         && _tr_extra_gate "$class" "$udid" "$active" "$(( $(_tr_now) - t0 ))" && _tr_slot_take "$class" "$id"; then
        now=$(_tr_now)
        _tr_set "$id" admitted_at "$now"; _tr_set "$id" progress_at "$now"; _tr_set "$id" state running
        TESTRUN_WORKERS=$(tr_workers "$(_tr_active heavy)"); TESTRUN_BROWSER_WORKERS=$(tr_browser_workers "$TESTRUN_WORKERS")
        export TESTRUN_WORKERS TESTRUN_BROWSER_WORKERS
        _tr_gate_leave
        level=$(_tr_pressure_level)
        [ "$now" -gt "$t0" ] && tr_event admit waited="$((now - t0))" class="$class" pressure="${level:-unreadable}" free="$(_tr_free_pct)" swap="$(_tr_swap_pct)"
        [ "$_TR_OVERRIDE" = 1 ] && tr_event swap_override waited="$((now - t0))" class="$class" swap="$(_tr_swap_pct)"
        return 0
      fi
      _tr_gate_leave
    fi
    now=$(_tr_now); waited=$((now - t0))
    if [ "$waited" -ge "${TESTRUN_WAIT_MAX:-900}" ]; then
      tr_event giveup waited="$waited" class="$class"
      echo "testrun: no slot for $class after ${waited}s, running:" >&2
      _tr_holders >&2
      tr_release
      return 75
    fi
    if [ "$waited" -ge "$next_notice" ]; then
      level=$(_tr_pressure_level)
      tr_event wait waited="$waited" class="$class" pressure="${level:-unreadable}" free="$(_tr_free_pct)" heavy="$(_tr_active heavy "$id")" reason="$_TR_WHY" swap="$(_tr_swap_pct)"
      next_notice=$((waited + ${TESTRUN_NOTICE:-30}))
    fi
    _tr_nap "${TESTRUN_ADMIT_POLL:-2}"
  done
}

# tr_release [id]: free the slots and delete the ticket (idempotent)
tr_release() {
  local id=${1:-${TESTRUN_ID:-}}
  [ -n "$id" ] || return 0
  _tr_slots_free "$id"
  rm -f "$(_tr_ticket "$id")" "$(_tr_ticket "$id").out" "$(_tr_ticket "$id").out.1" "$(_tr_ticket "$id").out.2"
  [ "$id" = "${TESTRUN_ID:-}" ] && unset TESTRUN_ID
  return 0
}

# tr_release_pid <pid>: release the run whose owner is <pid> (test-gate.sh slot-release)
tr_release_pid() {
  local id f
  for id in $(_tr_live_ids); do
    f=$(_tr_ticket "$id")
    [ "$(_tr_field pid "$f")" = "$1" ] && tr_release "$id"
  done
  return 0
}

# Signals during the admission wait: leave no ticket behind. tr_exec replaces this handler while a
# child runs (it forwards the signal to the child's group instead).
_TR_CHILD_PGID=""; _TR_SIG=0
_tr_on_signal() {
  _TR_SIG=$1
  if [ -n "$_TR_CHILD_PGID" ]; then
    kill -TERM -- "-$_TR_CHILD_PGID" 2>/dev/null
  else
    tr_release
    exit $((128 + $1))
  fi
}
_tr_install_traps() {
  trap '_tr_on_signal 2' INT
  trap '_tr_on_signal 15' TERM
  trap '_tr_on_signal 1' HUP
}

# ==================================================================================================
# Part 1b: process tree, watchdog, kill, restart
# Env: TEST_STALL_SECONDS (300, suites) TEST_STALL_SECONDS_XCODE (900) TEST_WARN_SECONDS_XCODE (600)
#      TESTRUN_WATCH_POLL (15, sampling interval) TESTRUN_TICK (1, exit detection) TESTRUN_CPU_DELTA (5) TESTRUN_KILL_GRACE (10)
#      TESTRUN_XCODE_EXTRA_RE (extra processes whose CPU counts as xcode progress)
#      TESTRUN_ORPHAN_AGE (600) TESTRUN_PSQL (psql) TESTRUN_PG_HOST (127.0.0.1) TESTRUN_SIMCTL (xcrun simctl)
# ==================================================================================================

tr_slug() { printf '%s' "$1" | shasum 2>/dev/null | cut -c1-8; }

# <pgid>: "pid cpu-seconds" for the group's members and all their descendants (children that left
# the group via setsid or set -m stay found through the parent chain).
_tr_ps_tree() {
  ps -ax -o pid=,ppid=,pgid=,cputime= 2>/dev/null | awk -v g="$1" '
    function sec(t,  a, n, i, s) { n = split(t, a, ":"); s = 0; for (i = 1; i <= n; i++) s = s * 60 + a[i]; return s }
    { pid[NR] = $1; ppid[NR] = $2; cpu[NR] = sec($4); if ($3 == g) mem[$1] = 1 }
    END {
      do { ch = 0; for (i = 1; i <= NR; i++) if (!mem[pid[i]] && mem[ppid[i]]) { mem[pid[i]] = 1; ch = 1 } } while (ch)
      for (i = 1; i <= NR; i++) if (mem[pid[i]]) printf "%s %d\n", pid[i], cpu[i]
    }'
}
tr_group_cpu() { _tr_ps_tree "$1" | awk '{ s += $2 } END { print s + 0 }'; }
tr_tree_pids() { _tr_ps_tree "$1" | awk '{ print $1 }'; }

# CPU seconds of the target simulator: the processes whose command line mentions
# CoreSimulator/Devices/<UDID> (its launchd_sim) and all their descendants, which includes the testmanagerd
# and the xctest runner of THAT device. xctest runs under the simulator's launchd, outside the xcodebuild
# group, so a quiet UI test looks dead without it. A machine-wide `testmanagerd` match is NOT used: it
# would count other devices' test runs as progress. Without a UDID there is nothing to attribute: 0.
# TESTRUN_XCODE_EXTRA_RE replaces the root pattern (tests).
tr_extra_cpu() {
  local re=${TESTRUN_XCODE_EXTRA_RE:-}
  [ -n "$re" ] || { [ -n "${1:-}" ] || { echo 0; return; }; re="CoreSimulator/Devices/$1"; }
  ps -ax -o pid=,ppid=,cputime=,command= 2>/dev/null | awk -v re="$re" '
    function sec(t,  a, n, i, s) { n = split(t, a, ":"); s = 0; for (i = 1; i <= n; i++) s = s * 60 + a[i]; return s }
    { pid[NR] = $1; ppid[NR] = $2; cpu[NR] = sec($3); if ($0 !~ /awk -v re=/ && $0 ~ re) mem[$1] = 1 }
    END {
      do { ch = 0; for (i = 1; i <= NR; i++) if (!mem[pid[i]] && mem[ppid[i]]) { mem[pid[i]] = 1; ch = 1 } } while (ch)
      for (i = 1; i <= NR; i++) if (mem[pid[i]]) s += cpu[i]
      print int(s)
    }'
}

# tr_kill_tree <pgid> [reason]: group plus descendants, TERM, KILL after the grace period
tr_kill_tree() {
  local g=$1 pids t=0 own p alive
  own=$(ps -o pgid= -p $$ 2>/dev/null | tr -d ' ')
  [ -n "$g" ] && [ "$g" -gt 1 ] 2>/dev/null && [ "$g" != "$own" ] || return 0
  pids=$(tr_tree_pids "$g" | tr '\n' ' ')   # one line: zsh does not split an unquoted $var, $(echo "$pids") does in both
  tr_event kill pgid="$g" reason="${2:-}" pids="${pids% }"
  kill -TERM -- "-$g" $(echo "$pids") 2>/dev/null
  while [ "$t" -lt "$(( ${TESTRUN_KILL_GRACE:-10} * 5 ))" ]; do
    alive=0
    for p in $(echo "$pids"); do kill -0 "$p" 2>/dev/null && alive=1; done
    kill -0 -- "-$g" 2>/dev/null && alive=1
    [ "$alive" = 0 ] && return 0
    sleep 0.2; t=$((t + 1))
  done
  # shellcheck disable=SC2086
  kill -KILL -- "-$g" $pids 2>/dev/null
  return 0
}

# <pid>: the pid and all its descendants, one per line (parent chain, so children that left the group stay found)
_tr_descendants() {
  ps -ax -o pid=,ppid= 2>/dev/null | awk -v r="$1" '
    { pid[NR] = $1; ppid[NR] = $2 }
    END {
      mem[r] = 1
      do { ch = 0; for (i = 1; i <= NR; i++) if (mem[pid[i]] != 1 && mem[ppid[i]] == 1) { mem[pid[i]] = 1; ch = 1 } } while (ch)
      for (i = 1; i <= NR; i++) if (mem[pid[i]] == 1) print pid[i]
    }'
}

# tr_kill_orphan <pid> [reason]: end one orphaned process. Its process group is killed only when the process leads
# it (pgid == pid): `Shell.run` and plain shells put children into the caller's group, so a group kill could hit the
# daemon or another session. Otherwise the pid and its descendants are signalled one by one, TERM then KILL.
tr_kill_orphan() {
  local pid=$1 g pids p t=0 alive own
  [ -n "$pid" ] && [ "$pid" -gt 1 ] 2>/dev/null || return 0
  g=$(ps -o pgid= -p "$pid" 2>/dev/null | tr -d ' ')
  [ -n "$g" ] || return 0
  if [ "$g" = "$pid" ]; then tr_kill_tree "$pid" "${2:-orphan}"; return 0; fi
  own=$$
  pids=$(_tr_descendants "$pid" | grep -vx "$own" | tr '\n' ' ')
  tr_event kill pid="$pid" reason="${2:-orphan}" pids="${pids% }"
  # shellcheck disable=SC2086
  kill -TERM $pids 2>/dev/null
  while [ "$t" -lt "$(( ${TESTRUN_KILL_GRACE:-10} * 5 ))" ]; do
    alive=0
    for p in $(echo "$pids"); do kill -0 "$p" 2>/dev/null && alive=1; done
    [ "$alive" = 0 ] && return 0
    sleep 0.2; t=$((t + 1))
  done
  # shellcheck disable=SC2086
  kill -KILL $pids 2>/dev/null
  return 0
}

# --- orphans -----------------------------------------------------------------------------------
_tr_cwd() { lsof -a -p "$1" -d cwd -Fn 2>/dev/null | sed -n 's/^n//p' | head -1; }
_tr_etime_s() {  # ps etime [[dd-]hh:]mm:ss -> seconds
  ps -o etime= -p "$1" 2>/dev/null | tr -d ' ' | awk '{ d = 0; t = $0; if (index(t, "-")) { split(t, x, "-"); d = x[1]; t = x[2] }
    n = split(t, a, ":"); s = 0; for (i = 1; i <= n; i++) s = s * 60 + a[i]; print d * 86400 + s }'
}

# tr_reap_orphans <scope-dir> [--dry]: `playwright run-server` with ppid 1, older than TESTRUN_ORPHAN_AGE,
# cwd inside <scope-dir> and no pest/phpunit process with the same cwd. Never per name, never global.
tr_reap_orphans() {
  local scope=$1 dry=${2:-} pid cwd age pc busy found=0
  scope=${scope%/}   # "/" or "" means everywhere
  for pid in $(pgrep -f 'playwright.*run-server' 2>/dev/null); do
    [ "$(ps -o ppid= -p "$pid" 2>/dev/null | tr -d ' ')" = 1 ] || continue
    age=$(_tr_etime_s "$pid"); [ "${age:-0}" -ge "${TESTRUN_ORPHAN_AGE:-600}" ] || continue
    cwd=$(_tr_cwd "$pid"); [ -n "$cwd" ] || continue
    case "$cwd/" in "$scope"/*) ;; *) continue ;; esac
    busy=0
    # Only real test binaries count: the wrappers (test-lock --cmd "... artisan test", gtimeout, deploy) carry
    # the same words on their command line and sit in the same cwd, which would keep every orphan alive.
    for pc in $(pgrep -f 'bin/(pest|phpunit)|artisan test' 2>/dev/null); do
      case "$(ps -o comm= -p "$pc" 2>/dev/null)" in php|*/php|php[0-9]*|*/php[0-9]*|pest|*/pest|phpunit|*/phpunit) ;; *) continue ;; esac
      [ "$(_tr_cwd "$pc")" = "$cwd" ] && busy=1
    done
    [ "$busy" = 0 ] || continue
    found=$((found + 1))
    echo "orphan playwright-server pid=$pid cwd=$cwd age=${age}s"
    if [ "$dry" != --dry ]; then tr_event reap kind=playwright pid="$pid" cwd="$cwd"; tr_kill_orphan "$pid" orphan-playwright >/dev/null 2>&1; fi
  done
  return 0
}

# tr_reap_dead_groups [--dry]: tickets whose wrapper died while the process group still runs
tr_reap_dead_groups() {
  local id f
  for id in $(_tr_live_ids); do
    f=$(_tr_ticket "$id")
    _tr_wrapper_alive "$f" && continue
    _tr_group_alive "$(_tr_field pgid "$f")" "$(_tr_field pgid_start "$f")" || continue
    echo "dead-wrapper group id=$id project=$(_tr_field project "$f") pgid=$(_tr_field pgid "$f")"
    if [ "${1:-}" != --dry ]; then tr_event reap kind=group id="$id"; tr_kill_tree "$(_tr_field pgid "$f")" dead-wrapper; tr_release "$id"; fi
  done
  return 0
}

# --- restart cleanup ---------------------------------------------------------------------------
_tr_psql() { "${TESTRUN_PSQL:-psql}" -h "${TESTRUN_PG_HOST:-127.0.0.1}" -d postgres -Atq "$@"; }
_tr_dbs_of() {  # <toplevel>: exact names from the registry that belong to that worktree
  local slug; slug=$(tr_slug "$1")
  grep -E "_${slug}(_|\$)" "$(_tr_state)/test-dbs.list" 2>/dev/null | grep -E '^[A-Za-z0-9_]+$'
}

# Sessions of this worktree's own test databases (and their paratest workers <name>_test_N)
_tr_pg_sessions_kill() {
  local db
  for db in $(_tr_dbs_of "$1"); do
    _tr_psql -c "select pg_terminate_backend(pid) from pg_stat_activity where datname = '$db' or datname ~ '^${db}_test_[0-9]+\$'" >/dev/null 2>&1
  done
  return 0
}

_tr_restart_cleanup() {  # <class> <udid> <resultBundlePath> <toplevel>
  tr_reap_orphans "$4" >/dev/null
  _tr_pg_sessions_kill "$4"
  [ -n "$3" ] && rm -rf "$3"
  if [ "$1" = xcode ] && [ -n "$2" ]; then
    ${TESTRUN_SIMCTL:-xcrun simctl} shutdown "$2" >/dev/null 2>&1
    ${TESTRUN_SIMCTL:-xcrun simctl} boot "$2" >/dev/null 2>&1
  fi
  return 0
}

# --- xcode helpers -----------------------------------------------------------------------------
# -jobs for a build: 6 alone, 3 when a second xcode run is active. If the new build system ignores
# -jobs, set TESTRUN_COMPILE_TASKS=1 and the shim also passes the concurrent-compile-task default.
tr_xcode_jobs() { if [ "$(_tr_active xcode)" -ge 2 ]; then echo 3; else echo 6; fi; }

# After a failed xcode run that overlapped another one: simulator-bootstrap errors pin the ceiling to 1 for 24 h.
_tr_xcode_guard() {
  grep -qE 'testmanagerd.*invalidated|Channel disconnected|never finished bootstrapping' "$1" 2>/dev/null || return 0
  echo $(( $(_tr_now) + 86400 )) > "$(_tr_state)/xcode-cap-until" 2>/dev/null || return 0
  tr_event guard reason=simulator-error cap=1 until=24h
}

# Admitted suites run niced so interactive work (editor, Orca, the owner's own tests) wins CPU contention.
# `nice` and not `taskpolicy -b`: the background QoS confines a process to the efficiency cores on Apple Silicon
# and throttles its I/O, which can slow a suite enough to look stalled to the watchdog below. nice only lowers the
# scheduling priority; an idle machine still gives the suite every core, and the CPU time the watchdog samples keeps
# growing. xcode runs stay at normal priority by default: the simulator and testmanagerd run outside this group
# (under the simulator's launchd), so niceing xcodebuild alone would only slow the build half. TESTRUN_NICE_XCODE
# switches it on.
tr_nice_for() {
  case "$1" in
    suite) echo "${TESTRUN_NICE:-10}" ;;
    xcode) echo "${TESTRUN_NICE_XCODE:-0}" ;;
    *) echo 0 ;;
  esac
}

# --- the run -----------------------------------------------------------------------------------
# _tr_attempt <class> <udid> cmd...: one try in its own process group; sets _TR_RC, _TR_STALLED.
# Output goes through two FIFOs and tee into $runs/<id>.out, so growth of that file is the output signal.
_tr_attempt() {
  local class=$1 udid=$2; shift 2
  local out pid t1 t2 nice next_sample stall warn now size lastsize=0 cpu maxcpu=0 extra maxextra=0 last_prog outchg warned=0 delta
  out="$(_tr_ticket "$TESTRUN_ID").out"
  delta=${TESTRUN_CPU_DELTA:-5}
  if [ "$class" = xcode ]; then stall=${TEST_STALL_SECONDS_XCODE:-900}; else stall=${TEST_STALL_SECONDS:-300}; fi
  warn=${TEST_WARN_SECONDS_XCODE:-600}
  _TR_STALLED=0
  : > "$out"; rm -f "$out.1" "$out.2"
  if ! mkfifo "$out.1" "$out.2" 2>/dev/null; then "$@"; _TR_RC=$?; return; fi
  tee -a "$out" < "$out.1" & t1=$!
  tee -a "$out" < "$out.2" >&2 & t2=$!
  nice=$(tr_nice_for "$class")
  if [ "$nice" -gt 0 ]; then
    { set -m; nice -n "$nice" "$@" > "$out.1" 2> "$out.2" & pid=$!; set +m; } 2>/dev/null
  else
    { set -m; "$@" > "$out.1" 2> "$out.2" & pid=$!; set +m; } 2>/dev/null
  fi
  _TR_CHILD_PGID=$pid
  _tr_set "$TESTRUN_ID" pgid "$pid"; _tr_set "$TESTRUN_ID" pgid_start "$(_tr_lstart "$pid")"
  last_prog=$(_tr_now); outchg=$last_prog
  next_sample=$(( $(_tr_now) + ${TESTRUN_WATCH_POLL:-15} ))
  while kill -0 "$pid" 2>/dev/null; do
    _tr_nap "${TESTRUN_TICK:-1}"   # exit detection every tick; the expensive sampling only every WATCH_POLL
    kill -0 "$pid" 2>/dev/null || break
    now=$(_tr_now)
    [ "$now" -ge "$next_sample" ] || continue
    next_sample=$((now + ${TESTRUN_WATCH_POLL:-15}))
    size=$(wc -c < "$out" | tr -d ' ')
    if [ "$size" -gt "$lastsize" ]; then lastsize=$size; last_prog=$now; outchg=$now; warned=0; fi
    cpu=$(tr_group_cpu "$pid")
    if [ $((cpu - maxcpu)) -gt "$delta" ]; then maxcpu=$cpu; last_prog=$now; fi
    if [ "$class" = xcode ]; then
      extra=$(tr_extra_cpu "$udid")
      if [ $((extra - maxextra)) -gt "$delta" ]; then maxextra=$extra; last_prog=$now; fi
      [ "$(_tr_active xcode)" -ge 2 ] && _TR_PARALLEL=1
      if [ $((now - outchg)) -ge "$warn" ] && [ "$warned" = 0 ]; then
        warned=1; tr_event warn silent_s="$((now - outchg))" class=xcode
      fi
    fi
    [ "$last_prog" = "$now" ] && _tr_set "$TESTRUN_ID" progress_at "$now"
    if [ $((now - last_prog)) -ge "$stall" ]; then
      _TR_STALLED=1
      tr_event stall idle_s="$((now - last_prog))" class="$class" pgid="$pid"
      echo "[testrun] no progress for $((now - last_prog)) s, last output:" >&2
      tail -n 3 "$out" >&2
      tr_kill_tree "$pid" stall
      break
    fi
  done
  { wait "$pid"; } 2>/dev/null; _TR_RC=$?
  wait "$t1" "$t2" 2>/dev/null
  _TR_CHILD_PGID=""
  rm -f "$out.1" "$out.2"
}

# tr_exec <class> <project> cmd...: run under the watchdog; the run must already be admitted.
# A stalled test run is cleaned up and restarted exactly once (TEST_RESTART); a second stall ends
# with exit 124 and TEST_STALLED_TWICE. build/archive runs are killed, never restarted.
tr_exec() {
  local class=$1 project=$2; shift 2
  local attempt=1 rc a prev udid="" bundle="" restartable=0 top
  if ! tr_enabled || [ -z "${TESTRUN_ID:-}" ]; then "$@"; return $?; fi
  prev=""
  udid=$(tr_udid_of "$@")
  [ -n "$udid" ] && _tr_set "$TESTRUN_ID" udid "$udid"
  for a in "$@"; do
    [ "$prev" = -resultBundlePath ] && bundle=$a
    case "$a" in test|test-without-building) [ "$class" = xcode ] && restartable=1 ;; esac
    prev=$a
  done
  [ "$class" = suite ] && restartable=1
  # test-lock.sh sets TESTRUN_RESTARTABLE=1 for what it wraps: a test command by construction, also when a
  # script around xcodebuild hides the `test` word. A direct xcodebuild build/archive never restarts.
  [ "${TESTRUN_RESTARTABLE:-}" = 1 ] && restartable=1
  top=$(git rev-parse --show-toplevel 2>/dev/null || pwd)
  [ "$class" = suite ] && tr_reap_orphans "$top" >/dev/null
  _TR_PARALLEL=0; _TR_SIG=0
  while :; do
    _tr_attempt "$class" "$udid" "$@"
    rc=$_TR_RC
    if [ "$_TR_SIG" != 0 ]; then rc=$((128 + _TR_SIG)); break; fi
    if [ "$_TR_STALLED" = 1 ]; then
      if [ "$restartable" = 1 ] && [ "$attempt" = 1 ]; then
        echo TEST_RESTART >&2
        tr_event restart class="$class" project="$project"
        _tr_restart_cleanup "$class" "$udid" "$bundle" "$top"
        attempt=2; continue
      fi
      [ "$restartable" = 1 ] && { echo TEST_STALLED_TWICE >&2; tr_event stalled_twice class="$class" project="$project"; }
      rc=124
    fi
    break
  done
  [ "$class" = xcode ] && [ "$restartable" = 1 ] && tr_sim_release "$udid" "$TESTRUN_ID"
  if [ "$class" = xcode ] && [ "$rc" -ne 0 ] && [ "${_TR_PARALLEL:-0}" = 1 ]; then
    _tr_xcode_guard "$(_tr_ticket "$TESTRUN_ID").out"
  fi
  return "$rc"
}

# tr_run <class> <project> cmd...: admit, run under the watchdog, release. Inner layers under a live
# TESTRUN_ID just run the command and refresh progress.
tr_run() {
  local class=$1 project=$2 rc; shift 2
  tr_enabled || { "$@"; return $?; }
  if _tr_nested; then tr_progress; "$@"; return $?; fi
  tr_admit "$class" "$project" "" "$([ "$class" = xcode ] && tr_udid_of "$@")" || return $?
  tr_exec "$class" "$project" "$@"; rc=$?
  tr_release
  return "$rc"
}

# ==================================================================================================
# Part 1c: result cache, test database registry, worktree cleanup
# Env: TESTRUN_CACHE_TTL (1800) TESTRUN_TOOL_VERSIONS (fixed string instead of `php -v`/`xcodebuild -version`)
# ==================================================================================================

# --- result cache ------------------------------------------------------------------------------
# A green, unfiltered, flake-free run is remembered per repo as "<ts> <tree> <envkey>". tree is
# tree-hash.sh (working tree incl. untracked files), envkey is sha1 over the test command, tool
# versions, lockfiles and the built asset manifest. A lookup hits on the same tree and envkey inside
# the TTL; a different tree only hits when the delta since the cached tree touches nothing but files
# matching `test-cache-ignore:` globs, or, with `test-cache-prose: true`, is prose-only by classify-diff.sh.
# keyed on the physical toplevel: git reports /private/var/..., a caller may pass /var/... or a symlinked path
_tr_cache_file() { printf '%s/test-cache/%s' "$(_tr_state)" "$(cd "$1" 2>/dev/null && pwd -P | shasum | cut -c1-16)"; }
tr_tree() { ( cd "$1" && bash "$_TR_LIB_DIR/tree-hash.sh" 2>/dev/null ); }
_tr_tree() { tr_tree "$@"; }

tr_cache_envkey() {  # <toplevel> <command>
  local top=$1 f
  {
    printf '%s\n' "$2"
    if [ -n "${TESTRUN_TOOL_VERSIONS+x}" ]; then printf '%s\n' "$TESTRUN_TOOL_VERSIONS"
    else
      command -v php >/dev/null 2>&1 && php -v 2>/dev/null | head -1
      command -v xcodebuild >/dev/null 2>&1 && xcodebuild -version 2>/dev/null
    fi
    for f in vendor/composer/installed.json package-lock.json bun.lock public/build/manifest.json; do
      [ -f "$top/$f" ] && cat "$top/$f"
    done
  } | shasum | cut -d' ' -f1
}

_tr_cache_delta_ok() {  # <toplevel> <cached tree> <tree>
  local top=$1 files rest g ignore keep="" f skip
  ( cd "$top" && git cat-file -e "$2^{tree}" 2>/dev/null ) || return 1
  files=$(cd "$top" && git diff-tree -r --name-only "$2" "$3" 2>/dev/null) || return 1
  ignore=$(tr_ship_value test-cache-ignore "$top") || ignore=""
  if [ -n "${ZSH_VERSION:-}" ]; then setopt localoptions globsubst; fi   # zsh: a case pattern from $g is literal otherwise
  ignore=$(printf '%s' "$ignore" | tr ' ' '\n')   # one pattern per line; read, not for, so no glob expansion either
  while IFS= read -r f; do   # here-string: zsh does not split an unquoted $var
    [ -n "$f" ] || continue
    skip=0
    while IFS= read -r g; do
      [ -n "$g" ] || continue
      case "$f" in $g) skip=1 ;; esac
    done <<<"$ignore"
    [ "$skip" = 1 ] || keep="$keep$f
"
  done <<<"$files"
  [ -n "$keep" ] || return 0
  [ "$(tr_ship_value test-cache-prose "$top")" = true ] || return 1
  [ "$(printf '%s' "$keep" | ( cd "$top" && bash "$_TR_LIB_DIR/classify-diff.sh" --paths ) | sed -n 's/^DIFF_CLASS=//p')" = prose ]
}

# tr_cache_lookup <toplevel> <command>: rc 0 on hit and sets TR_CACHE_KEY, silent
tr_cache_lookup() {
  tr_enabled || return 1
  local top=$1 file tree env ts ct ce now
  file=$(_tr_cache_file "$top"); [ -f "$file" ] || return 1
  tree=$(_tr_tree "$top") && [ -n "$tree" ] || return 1
  env=$(tr_cache_envkey "$top" "$2"); now=$(_tr_now)
  while read -r ts ct ce; do
    [ "$ce" = "$env" ] && [ $((now - ts)) -lt "${TESTRUN_CACHE_TTL:-1800}" ] || continue
    if [ "$ct" = "$tree" ] || _tr_cache_delta_ok "$top" "$ct" "$tree"; then TR_CACHE_KEY="${tree}:${env}"; return 0; fi
  done < "$file"
  return 1
}

# tr_cache_hit <toplevel> <command>: lookup, then announce `TEST_CACHE_HIT <key>` on stdout
tr_cache_hit() {
  tr_cache_lookup "$@" || return 1
  echo "TEST_CACHE_HIT $TR_CACHE_KEY"
  tr_event cache_hit key="$TR_CACHE_KEY" project="$(tr_project "$1")"
}

# tr_cache_put <toplevel> <command> <run-start-ts> [logfile] [tree-before-the-run]: remember a green run unless it flaked
tr_cache_put() {
  tr_enabled || return 0
  local top=$1 file tree env flakes since=$3 log=${4:-} pre=${5:-}
  [ -n "$log" ] && grep -q '^FLAKY: ' "$log" 2>/dev/null && { tr_event cache_skip reason=flaky; return 0; }
  flakes="$(_tr_state)/test-flakes.jsonl"
  if [ -f "$flakes" ] && sed -n 's/.*"ts":\([0-9]*\).*/\1/p' "$flakes" | awk -v s="$since" '$1 >= s { f = 1 } END { exit f ? 0 : 1 }'; then
    tr_event cache_skip reason=flaky; return 0
  fi
  tree=$pre
  [ -n "$tree" ] || tree=$(_tr_tree "$top")
  [ -n "$tree" ] || return 0
  env=$(tr_cache_envkey "$top" "$2")
  file=$(_tr_cache_file "$top")
  mkdir -p "$(dirname "$file")" 2>/dev/null || return 0
  # newest first: keep the 19 newest old lines (head), tail dropped the previous put once the file was full
  { printf '%s %s %s\n' "$(_tr_now)" "$tree" "$env"; head -n 19 "$file" 2>/dev/null || true; } > "$file.tmp.$$" && mv "$file.tmp.$$" "$file"
  tr_event cache_put key="${tree}:${env}" project="$(tr_project "$top")"
}

# --- test database registry ----------------------------------------------------------------------
# $STATE/test-dbs.list holds one exact database name per line. Cleanup drops only listed names plus
# their paratest workers <name>_test_<N>, matched by an exact regex, never by LIKE.

# tr_db_name <base> <toplevel>: <base>_<slug>; refuses a base that is not a test database
tr_db_name() {
  local slug base; slug=$(tr_slug "$2")
  base=${1%_"$slug"}
  case "$base" in
    *_test|*_testing) ;;
    *) echo "testrun: refusing database '$1': a test database name must end in _test or _testing" >&2; return 1 ;;
  esac
  printf '%s_%s' "$base" "$slug"
}

tr_db_register() {
  local list="$(_tr_state)/test-dbs.list"
  printf '%s' "$1" | grep -qE '^[A-Za-z0-9_]+$' || return 1
  mkdir -p "$(dirname "$list")" 2>/dev/null || return 1
  grep -qxF "$1" "$list" 2>/dev/null || echo "$1" >> "$list"
}

# tr_db_drop_listed <toplevel>: DROP the worktree's listed databases and their workers, unlist them
tr_db_drop_listed() {
  local db
  for db in $(_tr_dbs_of "$1"); do tr_db_drop_name "$db"; done
  return 0
}

# tr_worktree_cleanup <toplevel>: at the end of a worktree. Drops its test databases. The per-project
# simulator (<project>-test) is shared by all worktrees of the project and stays.
tr_worktree_cleanup() { tr_db_drop_listed "$1"; }

# tr_calls_xcodebuild <word...>: any word mentions xcodebuild, or is a script file (<= 256 KB) that does
tr_calls_xcodebuild() {
  local w
  for w in "$@"; do
    case "$w" in *xcodebuild*) return 0 ;; esac
    [ -f "$w" ] && [ "$(wc -c < "$w" 2>/dev/null | tr -d ' ')" -le 262144 ] && grep -q xcodebuild "$w" 2>/dev/null && return 0
  done
  return 1
}

# tr_db_drop_name <name>: DROP one registered database and its paratest workers, unlist it. Refuses (rc 1) a name
# the registry does not list, so a reconcile can never touch a dev database.
tr_db_drop_name() {
  local db=$1 list found d keep
  list="$(_tr_state)/test-dbs.list"
  printf '%s' "$db" | grep -qE '^[A-Za-z0-9_]+$' && grep -qxF "$db" "$list" 2>/dev/null || return 1
  _tr_psql -c "select pg_terminate_backend(pid) from pg_stat_activity where datname = '$db' or datname ~ '^${db}_test_[0-9]+\$'" >/dev/null 2>&1
  found=$(_tr_psql -c "select datname from pg_database where datname = '$db' or datname ~ '^${db}_test_[0-9]+\$'" 2>/dev/null)
  while IFS= read -r d; do
    [ -n "$d" ] || continue
    if [ "$d" = "$db" ] || printf '%s' "$d" | grep -qE "^${db}_test_[0-9]+\$"; then
      _tr_psql -c "DROP DATABASE IF EXISTS \"$d\" WITH (FORCE)" >/dev/null 2>&1
      tr_event db_drop name="$d"
    fi
  done <<<"$found"
  keep=$(grep -vxF "$db" "$list" 2>/dev/null)
  printf '%s\n' "$keep" | sed '/^$/d' > "$list.tmp.$$" && mv "$list.tmp.$$" "$list"
  return 0
}

# tr_is_full_run <word...>: true for a direct, unfiltered run of a whole suite (what an agent types when it skips
# `deploy <app> test`), so test-lock.sh can answer a repeat from the result cache. Filters, test paths and test
# names mean a partial run: never cached. Only commands whose runner is known are recognised.
tr_is_full_run() {
  local line=" $* "
  _tr_info_run "$@" && return 1
  # The configured gate scripts are full runs by definition: their partial-looking flags (--exclude-group=marketing, --testsuite)
  # live inside composer.json, not on this command line.
  case "$line" in *" composer test "|*" composer test:parallel ") return 0 ;; esac
  case "$line" in
    *" artisan test "*|*" composer test "*|*" composer test:parallel "*|*"vendor/bin/pest "*|*"vendor/bin/phpunit "*|*" swift test "*|*" bun test "*|*" npm test "*|*" npm run test "*|*" pnpm test "*|*" vitest run "*) ;;
    *) return 1 ;;
  esac
  case "$line" in
    *" --filter"*|*" --group"*|*" --testsuite"*|*" --only"*|*" --dirty"*|*" -k "*|*" -t "*|*" --test-name"*|*" tests/"*|*" test/"*|*".php "*|*".ts "*|*".tsx "*|*".js "*|*".swift "*|*"Test "*|*"Tests "*|*" --bail"*|*" --exclude-group"*|*" --grep"*|*" --testPathPattern"*|*" --shard"*|*" --changed"*|*" --mutate"*|*" --coverage"*|*" --class"*|*" --path"*) return 1 ;;
  esac
  return 0
}

# _tr_info_run <word...>: --list, --help, --ui and the like only print or open a UI: never a heavy or full run
_tr_info_run() {
  local a
  for a in "$@"; do case "$a" in --list|--list-tests|--help|-h|--ui|--version|-V|--init|--show-report) return 0 ;; esac; done
  return 1
}

# tr_is_runner_call <tool> <arg...>: the call IS a test runner in command position, not a mention of one. tool php:
# the first argument after php's own options is `artisan test|dusk` or a script named pest, paratest or phpunit;
# tool npx: `playwright test`. `php -r/-S/-f ...`, `php composer.phar require paratest` and a string argument that
# merely contains "pest" are not.
tr_is_runner_call() {
  local tool=${1##*/} a skip=0 first="" second=""
  shift
  for a in "$@"; do
    if [ "$skip" = 1 ]; then skip=0; continue; fi
    if [ -z "$first" ]; then
      case "$tool:$a" in
        php:-d|php:-c|npx:-p|npx:--package) skip=1; continue ;;
        php:-r|php:-R|php:-B|php:-E|php:-S|php:-f|php:-t|php:-i|npx:-c|npx:--call) return 1 ;;
        *:-*) continue ;;
      esac
      first=$a; continue
    fi
    second=$a; break
  done
  case "$tool" in
    php) case "$first" in
           artisan|*/artisan) case "$second" in test|dusk) return 0 ;; esac ;;
           pest|*/pest|paratest|*/paratest|phpunit|*/phpunit) return 0 ;;
         esac ;;
    npx) [ "$first" = playwright ] && [ "$second" = test ] && return 0 ;;
  esac
  return 1
}

# tr_is_heavy_direct <word...>: a direct browser or parallel run that is not a full run (those are tr_is_full_run) but
# still starts many processes. The words must contain a runner invocation (`artisan test|dusk`, vendor/bin/pest,
# paratest, phpunit, `playwright test`); then `--parallel`, `--processes` are heavy always, tests/Browser and a bare
# `playwright test` unless they name at most TESTRUN_FREE_FILES (3) test files. test-lock.sh and the php/npx shim
# admit such runs as `suite`, so test-status lists them and the workers come from the budget (tr_with_workers).
tr_is_heavy_direct() {
  local line=" $* " w files=0
  _tr_info_run "$@" && return 1
  case "$line" in
    *" artisan test "*|*" artisan dusk "*|*"vendor/bin/pest "*|*"vendor/bin/paratest "*|*"vendor/bin/phpunit "*|*"playwright test"*) ;;
    *) return 1 ;;
  esac
  case "$line" in
    *" --parallel "*|*" --parallel="*|*" --processes"*) return 0 ;;
    *"tests/Browser"*|*"playwright test"*|*"artisan dusk"*) ;;
    *) return 1 ;;
  esac
  while IFS= read -r w; do
    case "$w" in *Test.php|*.spec.[jt]s|*.spec.[jt]sx|*.test.[jt]s|*.test.[jt]sx) files=$((files + 1)) ;; esac
  done <<<"$(printf '%s\n' "$line" | tr ' ' '\n')"
  [ "$files" -lt 1 ] || [ "$files" -gt "${TESTRUN_FREE_FILES:-3}" ]
}

# tr_with_workers cmd...: run the command with the worker counts of the admitted budget (TESTRUN_WORKERS,
# TESTRUN_BROWSER_WORKERS): `--parallel` gets `--processes=N`, `playwright test` gets `--workers=N`, unless the
# caller set them. Also works on a command string handed to `bash -c`.
tr_with_workers() {
  local n=${TESTRUN_WORKERS:-4} b=${TESTRUN_BROWSER_WORKERS:-4} a prev="" proc=0 wk=0 out=()
  for a in "$@"; do case "$a" in *--processes*) proc=1 ;; *--workers*) wk=1 ;; esac; done
  for a in "$@"; do
    case "$a" in
      --parallel) out+=("$a"); [ "$proc" = 0 ] && out+=("--processes=$n") ;;
      *" --parallel"*) [ "$proc" = 0 ] && a=${a// --parallel/ --parallel --processes=$n}; out+=("$a") ;;
      *"playwright test"*) [ "$wk" = 0 ] && a=${a/playwright test/playwright test --workers=$b}; out+=("$a") ;;
      test) out+=("$a"); [ "$prev" = playwright ] && [ "$wk" = 0 ] && out+=("--workers=$b") ;;
      *) out+=("$a") ;;
    esac
    prev=$a
  done
  "${out[@]}"
}
