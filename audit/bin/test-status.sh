#!/usr/bin/env bash
# Shows the test runs of this Mac and cleans up what nobody owns any more. Reads the ticket store of
# lib-testrun.sh (~/.local/state/claude/runs, or $TESTRUN_STATE_DIR).
#
# Usage: test-status.sh                    one line per run: project, class, state, age, progress age, holder;
#                                          then swap use and the booted simulators with age and owner run
#        test-status.sh --reap [--scope DIR]   also kill what the listing marks as reapable:
#                                          - process groups whose wrapper is dead (state `orphan`)
#                                          - `playwright run-server` with ppid 1, older than 10 min, cwd inside
#                                            DIR (default /), without a pest/phpunit process in the same cwd
#                                          Never per name, never global pkill.
# Install: ln -s <skills>/audit/bin/test-status.sh ~/.local/bin/test-status
# Why: a run_in_background wrapper can die while its group keeps running, and aborted Pest runs leave
# Playwright servers behind (2026-10-13: two orphans in apps/events and a worktree). bash 3.2 compatible.

set -u
# Resolve ~/.local/bin/test-status (a symlink) to the real script: the lib sits next to that, not next to the link.
SELF=$0
while [ -L "$SELF" ]; do
  t=$(readlink "$SELF")
  case "$t" in /*) SELF=$t ;; *) SELF=$(dirname "$SELF")/$t ;; esac
done
. "$(cd "$(dirname "$SELF")" && pwd)/lib-testrun.sh" || { echo "test-status: lib-testrun.sh not found" >&2; exit 1; }

REAP=0; SCOPE=/
while [ $# -gt 0 ]; do
  case "$1" in
    --reap) REAP=1 ;;
    --scope) SCOPE=${2:-/}; shift ;;
    *) echo "usage: test-status.sh [--reap [--scope DIR]]" >&2; exit 64 ;;
  esac
  shift
done

human() {  # seconds -> 12s | 3m05s | 1h02m
  local s=$1
  if [ "$s" -lt 60 ]; then echo "${s}s"
  elif [ "$s" -lt 3600 ]; then printf '%dm%02ds' $((s / 60)) $((s % 60))
  else printf '%dh%02dm' $((s / 3600)) $(((s % 3600) / 60)); fi
}

_tr_prune
now=$(_tr_now)
ids=$(_tr_live_ids)
if [ -z "$ids" ]; then
  echo "no test runs"
else
  printf '%-18s %-6s %-8s %-8s %-9s %s\n' PROJECT CLASS STATE AGE PROGRESS HOLDER
  for id in $ids; do
    f=$(_tr_ticket "$id")
    state=$(_tr_field state "$f")
    _tr_wrapper_alive "$f" || state=orphan
    prog=$(_tr_field progress_at "$f")
    printf '%-18s %-6s %-8s %-8s %-9s pid %s in %s\n' "$(_tr_field project "$f")" "$(_tr_field class "$f")" "$state" \
      "$(human $((now - $(_tr_field since "$f"))))" "$([ -n "$prog" ] && human $((now - prog)) || echo -)" \
      "$(_tr_field pid "$f")" "$(_tr_field cwd "$f")"
  done
fi

# Booted simulators (age, and the run that holds each) and swap: what the caps in lib-testrun.sh act on.
echo
_tr_swap_raw | awk '{ for (i = 1; i < NF; i++) { if ($i == "total") t = $(i + 2) + 0; if ($i == "used") u = $(i + 2) + 0 } }
  END { if (t > 0) printf "swap: %d of %d MB used (%d%%)\n", u, t, u * 100 / t; else print "swap: unreadable" }'
sims=$(_tr_booted_sims)
if [ -z "$sims" ]; then
  echo "no booted simulators"
else
  printf '%-38s %-24s %-8s %s\n' UDID SIMULATOR BOOTED OWNER
  while IFS='|' read -r udid name; do
    age=$(tr_sim_age "$udid")
    printf '%-38s %-24s %-8s %s\n' "$udid" "$name" "$([ -n "$age" ] && human "$age" || echo ?)" "$(tr_sim_owner "$udid" || echo "no active run")"
  done <<<"$sims"
fi

if [ "$REAP" = 1 ]; then
  tr_reap_dead_groups
  tr_reap_orphans "$SCOPE"
else
  dead=$(tr_reap_dead_groups --dry); orph=$(tr_reap_orphans "$SCOPE" --dry)
  if [ -n "$dead$orph" ]; then
    echo "reapable (run with --reap):"
    printf '%s\n' "$dead" "$orph" | sed '/^$/d; s/^/  /'
  fi
fi
