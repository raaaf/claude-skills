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
    tr_reap_dead_groups >/dev/null   # an orphaned group (wrapper died) must not keep its slot for good
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
    if [ "$dry" != --dry ]; then tr_event reap kind=playwright pid="$pid" cwd="$cwd"; tr_kill_tree "$pid" orphan-playwright >/dev/null 2>&1; kill -KILL "$pid" 2>/dev/null; fi
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

# --- the run -----------------------------------------------------------------------------------
# _tr_attempt <class> <udid> cmd...: one try in its own process group; sets _TR_RC, _TR_STALLED.
# Output goes through two FIFOs and tee into $runs/<id>.out, so growth of that file is the output signal.
_tr_attempt() {
  local class=$1 udid=$2; shift 2
  local out pid t1 t2 next_sample stall warn now size lastsize=0 cpu maxcpu=0 extra maxextra=0 last_prog outchg warned=0 delta
  out="$(_tr_ticket "$TESTRUN_ID").out"
  delta=${TESTRUN_CPU_DELTA:-5}
  if [ "$class" = xcode ]; then stall=${TEST_STALL_SECONDS_XCODE:-900}; else stall=${TEST_STALL_SECONDS:-300}; fi
  warn=${TEST_WARN_SECONDS_XCODE:-600}
  _TR_STALLED=0
  : > "$out"; rm -f "$out.1" "$out.2"
  if ! mkfifo "$out.1" "$out.2" 2>/dev/null; then "$@"; _TR_RC=$?; return; fi
  tee -a "$out" < "$out.1" & t1=$!
  tee -a "$out" < "$out.2" >&2 & t2=$!
  { set -m; "$@" > "$out.1" 2> "$out.2" & pid=$!; set +m; } 2>/dev/null
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
  for a in "$@"; do
    case "$a" in *id=*) [ -z "$udid" ] && udid=$(printf '%s' "$a" | grep -oE 'id=[0-9A-Fa-f-]+' | head -1 | cut -c4-) ;; esac
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
  tr_admit "$class" "$project" || return $?
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
  { printf '%s %s %s\n' "$(_tr_now)" "$tree" "$env"; tail -n 19 "$file" 2>/dev/null || true; } > "$file.tmp.$$" && mv "$file.tmp.$$" "$file"
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
  local db found d list keep
  list="$(_tr_state)/test-dbs.list"
  for db in $(_tr_dbs_of "$1"); do
    found=$(_tr_psql -c "select datname from pg_database where datname = '$db' or datname ~ '^${db}_test_[0-9]+\$'" 2>/dev/null)
    while IFS= read -r d; do   # here-string: zsh does not split an unquoted $found
      [ -n "$d" ] || continue
      if [ "$d" = "$db" ] || printf '%s' "$d" | grep -qE "^${db}_test_[0-9]+\$"; then
        _tr_psql -c "DROP DATABASE IF EXISTS \"$d\" WITH (FORCE)" >/dev/null 2>&1
        tr_event db_drop name="$d"
      fi
    done <<<"$found"
    keep=$(grep -vxF "$db" "$list" 2>/dev/null)
    printf '%s\n' "$keep" | sed '/^$/d' > "$list.tmp.$$" && mv "$list.tmp.$$" "$list"
  done
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
