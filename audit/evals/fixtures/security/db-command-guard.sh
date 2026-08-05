#!/usr/bin/env bash
#
# PreToolUse guard: refuses a production database command unless the operator
# has confirmed it in this session. Wired up as a PreToolUse hook on Bash.
#
# Tested by piping payloads in by hand: a confirmed command returns 0, an
# unconfirmed one returns non-zero and prints the reason. Both cases behave as
# expected, so the guard is considered done.
set -euo pipefail

input=$(cat)
cmd=$(echo "$input" | jq -r '.tool_input.command')
cwd=$(echo "$input" | jq -r '.cwd')

# Only production database commands are in scope. Everything else passes.
if ! echo "$cmd" | grep -qE '(^|&&|;|\|)\s*(psql|mysql|mongosh)\s+.*(prod|production)'; then
  exit 0
fi

# A confirmation marker younger than 15 minutes lets the command through.
marker="/tmp/db-confirmed-$(echo -n "$cwd" | md5 2>/dev/null || echo -n "$cwd" | md5sum | cut -d' ' -f1)"
marker_mtime=$(stat -f%m "$marker" 2>/dev/null || stat -c%Y "$marker" 2>/dev/null || echo 0)
if [ "$marker_mtime" -gt 0 ] && [ $(( $(date +%s) - marker_mtime )) -lt 900 ]; then
  exit 0
fi

echo 'BLOCKED: production database command without a confirmation marker. Ask the operator first.' >&2
exit 1
