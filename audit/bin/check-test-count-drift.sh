#!/usr/bin/env bash
# Numeric test-count claims in README.md/CLAUDE.md drift silently when fix
# waves add tests. This check extracts every "<N> Tests" claim and diffs it
# against source-level suite counts.
#
# Source counts are approximations: parametrized tests (test.each, @Test
# arguments:) expand at runtime, so a MISMATCH here is a verify hint, not an
# auto-finding. The orchestrator compares the claims against the actual
# test-run output in Phase 3c; only a runtime mismatch becomes a finding.
set -euo pipefail
ROOT="${1:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
cd "$ROOT"

CLAIMS=$(grep -rnoE '[0-9]+ Tests?\b' README.md CLAUDE.md 2>/dev/null || true)
if [ -z "$CLAIMS" ]; then
  echo "TESTCOUNT_RESULT=SKIP"
  exit 0
fi

EXCLUDES=(--exclude-dir=node_modules --exclude-dir=vendor --exclude-dir=.git --exclude-dir=dist --exclude-dir=build)

# Every count ends in `|| true`: pipefail would otherwise abort the whole
# check the first time a suite type has zero matches.
JS=$( { grep -rhoE '^[[:space:]]*(it|test)(\.[a-z]+)?\(' "${EXCLUDES[@]}" \
  --include='*.test.ts' --include='*.test.js' --include='*.test.tsx' --include='*.test.jsx' \
  . 2>/dev/null || true; } | wc -l | tr -d ' ')
# Swift Testing (@Test) plus XCTest (func test...). Comment lines excluded.
SWIFT_AT=$( { grep -rhE '^[[:space:]]*@Test' "${EXCLUDES[@]}" --include='*.swift' . 2>/dev/null || true; } | wc -l | tr -d ' ')
SWIFT_FN=$( { grep -rhE '^[[:space:]]*func test[A-Z_]' "${EXCLUDES[@]}" --include='*.swift' . 2>/dev/null || true; } | wc -l | tr -d ' ')
SWIFT=$((SWIFT_AT + SWIFT_FN))
PHP=$( { grep -rhE 'function test[A-Z_]|#\[Test\]' "${EXCLUDES[@]}" --include='*Test.php' . 2>/dev/null || true; } | wc -l | tr -d ' ')

COUNTS=""
if [ "$JS" -gt 0 ]; then COUNTS="$COUNTS js=$JS"; fi
if [ "$SWIFT" -gt 0 ]; then COUNTS="$COUNTS swift=$SWIFT"; fi
if [ "$PHP" -gt 0 ]; then COUNTS="$COUNTS php=$PHP"; fi
if [ -z "$COUNTS" ]; then
  echo "TESTCOUNT_RESULT=SKIP"
  exit 0
fi
TOTAL=$((JS + SWIFT + PHP))

MISMATCH=0
OUT=""
while IFS= read -r line; do
  n=$(printf '%s' "$line" | grep -oE '[0-9]+' | tail -1)
  loc=$(printf '%s' "$line" | cut -d: -f1,2)
  if [ "$n" != "$JS" ] && [ "$n" != "$SWIFT" ] && [ "$n" != "$PHP" ] && [ "$n" != "$TOTAL" ]; then
    MISMATCH=1
    OUT="${OUT}CLAIM ${loc} says ${n} Tests — no suite count matches (${COUNTS# } total=${TOTAL})\n"
  fi
done <<< "$CLAIMS"

if [ "$MISMATCH" -eq 1 ]; then
  echo "TESTCOUNT_RESULT=MISMATCH"
  echo "COUNTS:${COUNTS} total=${TOTAL}"
  printf '%b' "$OUT"
else
  echo "TESTCOUNT_RESULT=OK"
  echo "COUNTS:${COUNTS} total=${TOTAL}"
fi
