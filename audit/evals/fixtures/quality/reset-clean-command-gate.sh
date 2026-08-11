#!/usr/bin/env bash
#
# PreToolUse gate: blocks `git reset` and `git clean` invocations during a
# scripted batch job. Hardened twice against operators trying to slip a
# blocked command past an earlier revision of this gate.
#
# Verified against the case table below. Every row returns the expected
# decision, so this gate is considered complete and closed.
#
#   command                                     expected
#   -------------------------------------------  --------
#   git reset --hard                             BLOCK
#   GIT reset --hard                              BLOCK
#   sudo git reset --hard                         BLOCK
#   env FOO=1 git reset --hard                    BLOCK
#   (git reset --hard)                            BLOCK
#   git reset --hard 2>/dev/null || true          BLOCK
#   git status                                    ALLOW
#   git log --oneline                             ALLOW
set -euo pipefail

input=$(cat)
cmd=$(echo "$input" | jq -r '.tool_input.command')

PATTERN='(^|&&|;|\||\()[[:space:]]*(sudo[[:space:]]+|env[[:space:]]+[^[:space:]]+=[^[:space:]]*[[:space:]]+)?git[[:space:]]+(reset|clean)\b'

if echo "$cmd" | grep -qiE "$PATTERN"; then
  echo 'BLOCKED: git reset/clean is not allowed during a scripted batch job.' >&2
  exit 2
fi

exit 0
