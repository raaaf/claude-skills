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
  for kv in "$@"; do
    k=${kv%%=*}; v=${kv#*=}
    v=${v//\\/\\\\}; v=${v//\"/\\\"}; v=$(printf '%s' "$v" | tr '\n\t' '  ')
    extra="$extra,\"$k\":\"$v\""
    line="$line $k=$v"
  done
  printf 'TESTRUN %s%s\n' "$name" "$line" >&2
  state=$(_tr_state)
  mkdir -p "$state" 2>/dev/null || return 0
  printf '{"ts":%s,"date":"%s","event":"%s","id":"%s","project":"%s"%s}\n' \
    "$(_tr_now)" "$(date +%Y-%m-%d)" "$name" "${TESTRUN_ID:-}" "${TESTRUN_PROJECT:-}" "$extra" \
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
    _tr_alive "$f" || { mv "$f" "$f.dead.$$" 2>/dev/null && rm -f "$f.dead.$$"; }
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
# this Mac) admits with >= 25 % free and at most one active heavy run, otherwise only into an idle
# machine; level 4 and above waits; unreadable behaves like level 2 with 0 % free.
tr_pressure_ok() {
  local level free active=${1:-0} max
  level=$(_tr_pressure_level)
  case "$level" in
    1) return 0 ;;
    '') max=0 ;;
    2|3) free=$(_tr_free_pct); if [ "${free:-0}" -ge 25 ]; then max=1; else max=0; fi ;;
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

# tr_admit <class> <project> [owner-pid]: wait for admission, then export TESTRUN_ID. Returns 0 when
# admitted (also when nested, disabled or the state dir is unwritable), 75 after TESTRUN_WAIT_MAX.
tr_admit() {
  tr_enabled || return 0
  _tr_nested && return 0
  local class=$1 project=$2 owner=${3:-$$} id t0 now waited next_notice=0 active level
  mkdir -p "$(_tr_runs)" "$(_tr_slots)" 2>/dev/null || { echo "testrun: state dir not writable, running without admission" >&2; return 0; }
  id="$(_tr_stamp)-$owner"
  {
    printf 'pid=%s\nstart=%s\nclass=%s\nstate=waiting\nproject=%s\ncwd=%s\nargs=%s\nsince=%s\n' \
      "$owner" "$(_tr_lstart "$owner")" "$class" "$project" "$PWD" "$(printf '%s' "${TESTRUN_ARGS:-}" | tr '\n' ' ')" "$(_tr_now)"
  } > "$(_tr_ticket "$id").tmp.$$" && mv "$(_tr_ticket "$id").tmp.$$" "$(_tr_ticket "$id")"
  export TESTRUN_ID=$id TESTRUN_PROJECT=$project TESTRUN_OWNER_PID=$owner
  _tr_install_traps
  t0=$(_tr_now)
  while :; do
    _tr_prune
    if _tr_gate_enter; then
      active=$(_tr_active heavy "$id")
      if _tr_is_head "$id" "$class" && ! _tr_staggered "$id" && tr_pressure_ok "$active" && _tr_slot_take "$class" "$id"; then
        now=$(_tr_now)
        _tr_set "$id" admitted_at "$now"; _tr_set "$id" progress_at "$now"; _tr_set "$id" state running
        _tr_gate_leave
        level=$(_tr_pressure_level)
        [ "$now" -gt "$t0" ] && tr_event admit waited="$((now - t0))" class="$class" pressure="${level:-unreadable}"
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
      tr_event wait waited="$waited" class="$class" pressure="${level:-unreadable}" heavy="$(_tr_active heavy "$id")"
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
