#!/usr/bin/env bash
# Verify-by-Measurement helper for the performance dimension (/audit Schritt E/E.5).
# Activates only when the project declares a measurement command, so a fix to a
# performance finding can be verified by a real before/after metric instead of a
# subjective peer-review. Adapted from AvdLee's Xcode-Build-Optimization skill
# (benchmark -> apply -> re-benchmark).
#
# Declare the command via env (PERF_MEASURE_CMD) or in .claude/audit-guidelines.md:
#   perf-measure: <command>
# The command MUST print exactly one line "PERF_METRIC=<number>" (lower = better),
# e.g. bundle bytes, build seconds, query count.
#
# Usage:
#   perf-measure.sh --detect        prints PERF_MEASURE_CMD=<cmd> (empty if none)
#   perf-measure.sh --run "<cmd>"   runs cmd, prints PERF_METRIC=<number|NA>
set -euo pipefail
ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"

case "${1:-}" in
  --detect)
    cmd="${PERF_MEASURE_CMD:-}"
    if [ -z "$cmd" ] && [ -f "$ROOT/.claude/audit-guidelines.md" ]; then
      cmd=$(grep -m1 '^perf-measure:[[:space:]]*' "$ROOT/.claude/audit-guidelines.md" \
            | sed 's/^perf-measure:[[:space:]]*//')
    fi
    printf 'PERF_MEASURE_CMD=%q\n' "$cmd"   # %q-quoted so eval reconstructs spaces faithfully
    ;;
  --run)
    cmd="${2:-}"
    [ -n "$cmd" ] || { echo "PERF_METRIC=NA"; exit 0; }
    out=$(cd "$ROOT" && eval "$cmd" 2>&1) || { echo "PERF_METRIC=NA"; exit 0; }
    metric=$(printf '%s\n' "$out" | grep -oE 'PERF_METRIC=[0-9]+(\.[0-9]+)?' | tail -1 | cut -d= -f2 || true)
    echo "PERF_METRIC=${metric:-NA}"
    ;;
  *)
    echo "usage: perf-measure.sh --detect | --run \"<cmd>\"" >&2
    exit 2
    ;;
esac
