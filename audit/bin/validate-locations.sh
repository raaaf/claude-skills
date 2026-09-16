#!/usr/bin/env bash
#
# Hallucination validator for finding locations, for orchestrators that hold
# their findings in prose rather than in find.js (today: /design-audit Phase 3).
# Reads `path<TAB>line` pairs from a FILE, never from a command line: a finding's
# path and line are audited-repo content, and on 2026-09-16 an inline template
# that substituted them into `F='{datei}'` was a Critical (a path with a quote
# breaks out of the literal). The orchestrator writes the pairs with the Write
# tool, then runs this script on that file; no finding text ever reaches a shell.
#
# Usage: bash validate-locations.sh <pairs.tsv> [repo-root]
# Output: `LOCATION_OK <path>:<line>` or `HALLUCINATION <path>:<line> <reason>`
# per pair, then exactly one `LOCATIONS_RESULT=OK|HITS (N)|SKIP (reason)`.
# bash 3.2, no eval, every value read with `read -r` and used quoted.
set -uo pipefail
PAIRS="${1:-}"; ROOT="${2:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
[ -n "$PAIRS" ] && [ -f "$PAIRS" ] || { echo "LOCATIONS_RESULT=SKIP (no pairs file)"; exit 0; }
HITS=0; N=0
while IFS="$(printf '\t')" read -r path line _rest; do
  [ -n "$path" ] || continue
  N=$((N+1))
  case "$line" in ''|*[!0-9]*) echo "HALLUCINATION $path:$line line is not a number"; HITS=$((HITS+1)); continue;; esac
  case "$path" in /*|*/../*|../*|*/..|..) echo "HALLUCINATION $path:$line path is absolute or escapes the repo"; HITS=$((HITS+1)); continue;; esac
  if [ ! -f "$ROOT/$path" ]; then echo "HALLUCINATION $path:$line file missing"; HITS=$((HITS+1)); continue; fi
  total=$(wc -l < "$ROOT/$path" | tr -d ' ')
  if [ "$line" -gt "$total" ]; then echo "HALLUCINATION $path:$line line out of range (file has $total)"; HITS=$((HITS+1)); continue; fi
  echo "LOCATION_OK $path:$line"
done < "$PAIRS"
[ "$N" -eq 0 ] && { echo "LOCATIONS_RESULT=SKIP (pairs file empty)"; exit 0; }
[ "$HITS" -eq 0 ] && echo "LOCATIONS_RESULT=OK" || echo "LOCATIONS_RESULT=HITS ($HITS)"
exit 0
