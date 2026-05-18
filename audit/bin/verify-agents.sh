#!/usr/bin/env bash
#
# Verify that every audit subagent definition file exists before the
# orchestrator dispatches anything. Cheap fail-fast — saves a confusing
# half-loop when an install is incomplete.
#
# Usage: bash verify-agents.sh <AUDIT_AGENTS_DIR>
#
# Output:
#   AGENTS_RESULT=OK | MISSING
#   <missing files, one per line>
set -euo pipefail

AGENTS_DIR="${1:?usage: verify-agents.sh <AUDIT_AGENTS_DIR>}"

REQUIRED=(
  1-architecture.md
  2-security.md
  3-performance.md
  4-code-quality.md
  5-seo.md
  6-a11y.md
  7-typography.md
  8-ui-design.md
  9-ux.md
  10-animation.md
  11-docs-sync.md
  0-triage.md
  fix-agent.md
  prompt-template.md
  learning-agent.md
)

MISSING=""
for f in "${REQUIRED[@]}"; do
  if [ ! -f "$AGENTS_DIR/$f" ]; then
    MISSING+="$AGENTS_DIR/$f"$'\n'
  fi
done

if [ -n "$MISSING" ]; then
  echo "AGENTS_RESULT=MISSING"
  printf '%s' "$MISSING"
  exit 1
else
  echo "AGENTS_RESULT=OK"
fi
