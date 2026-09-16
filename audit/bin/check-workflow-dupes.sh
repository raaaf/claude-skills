#!/usr/bin/env bash
#
# The Workflow tool forbids imports, so find.js and fix.js each carry a copy of
# the helpers they share (hasCompleteCoverage, FINDINGS_SCHEMA, warnIfNull,
# chunk). Copies drift: on 2026-09-16 fix.js's hasCompleteCoverage had grown a
# stricter check find.js never got. This is the mechanical guard for that: it
# extracts each duplicated top-level definition from both files and diffs them.
#
# Usage: bash check-workflow-dupes.sh [root]
# Output: `WORKFLOW_DUPES_HIT <symbol>` per drifted symbol, then exactly one
# `WORKFLOW_DUPES_RESULT=OK|HITS (N)|SKIP (reason)`. bash 3.2, BSD-safe (awk only).
set -uo pipefail
ROOT="${1:-$(git rev-parse --show-toplevel 2>/dev/null || echo .)}"
A="$ROOT/audit/workflows/find.js"; B="$ROOT/audit/workflows/fix.js"
[ -f "$A" ] && [ -f "$B" ] || { echo "WORKFLOW_DUPES_RESULT=SKIP (workflow scripts not found under $ROOT)"; exit 0; }

# Print one top-level definition: from its first line to the first line that is
# exactly `}` or `};` at column 0.
extract() {
  awk -v sym="$2" '
    $0 ~ "^(const|function) "sym"[ (=]" { on=1 }
    on { print }
    on && ($0 == "}" || $0 == "};") { exit }
  ' "$1"
}
HITS=0
for sym in hasCompleteCoverage FINDINGS_SCHEMA warnIfNull chunk; do
  a=$(extract "$A" "$sym"); b=$(extract "$B" "$sym")
  if [ -z "$a" ] || [ -z "$b" ]; then
    echo "WORKFLOW_DUPES_HIT $sym: missing in $([ -z "$a" ] && echo find.js || echo fix.js)"; HITS=$((HITS+1)); continue
  fi
  if [ "$a" != "$b" ]; then echo "WORKFLOW_DUPES_HIT $sym: definitions differ between find.js and fix.js"; HITS=$((HITS+1)); fi
done
[ "$HITS" -eq 0 ] && echo "WORKFLOW_DUPES_RESULT=OK" || echo "WORKFLOW_DUPES_RESULT=HITS ($HITS)"
exit 0
