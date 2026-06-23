#!/usr/bin/env bash
# Runs the test command recorded in FEATURE_AUDIT.md and reports the REAL process
# exit code as a trailing "TEST_EXIT=<code|none>" line. The model must NOT claim
# test_exit from memory; this script is the source of truth (Bash decides, not the LLM).
#
# The header of FEATURE_AUDIT.md must contain a machine-readable line:
#   test-command: <command>      (or "none" when no runner is possible)
#
# Always exits 0 so the caller can capture the marker line; the true result is in
# TEST_EXIT. Test stdout/stderr is streamed first, the marker is the last line.
#
# Usage: run-tests.sh [<FEATURE_AUDIT.md>]
set -uo pipefail
FILE="${1:-FEATURE_AUDIT.md}"

cmd=""
if [ -f "$FILE" ]; then
  cmd=$(grep -m1 '^test-command:[[:space:]]*' "$FILE" | sed 's/^test-command:[[:space:]]*//')
fi

if [ -z "$cmd" ] || [ "$cmd" = "none" ]; then
  echo "TEST_EXIT=none"
  exit 0
fi

( eval "$cmd" )
code=$?
echo "TEST_EXIT=$code"
exit 0
