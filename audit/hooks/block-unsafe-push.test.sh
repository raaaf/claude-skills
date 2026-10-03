#!/usr/bin/env bash
#
# Pins block-unsafe-push.sh: every push needs a fresh audit marker (30 min TTL); without one the hook asks,
# whatever the branch name. Non-push commands pass untouched.
set -euo pipefail
HOOK="$(cd "$(dirname "$0")" && pwd)/${HOOK_UNDER_TEST:-block-unsafe-push.sh}"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"; rm -f "$MARKER"' EXIT
git init -q "$TMP/repo"
git -C "$TMP/repo" -c user.email=t@t -c user.name=t commit -q --allow-empty -m init
CWD=$(cd "$TMP/repo" && pwd)
HASH=$(echo -n "$CWD" | md5 2>/dev/null || echo -n "$CWD" | md5sum | cut -d' ' -f1)
MARKER="/tmp/claude-audit-passed-$HASH"
rm -f "$MARKER"

run() { jq -n --arg c "$1" --arg d "$CWD" '{tool_input:{command:$c},cwd:$d}' | bash "$HOOK"; }
fail=0
check() {
  local want="$1" cmd="$2" out
  out=$(run "$cmd")
  if [ "$want" = allow ] && [ -z "$out" ]; then printf 'PASS allow: %s\n' "$cmd"
  elif [ "$want" = ask ] && printf '%s' "$out" | grep -q '"ask"'; then printf 'PASS ask: %s\n' "$cmd"
  else printf 'FAIL want=%s: %s\n  got: %s\n' "$want" "$cmd" "$out" >&2; fail=1; fi
}

check allow 'git status'
check ask 'git push'
check ask 'git push -u origin feature/x'
check ask 'git push -u origin chore/nightly-audit-2026-10-02'
check ask 'git push -u origin chore/cleanup-sweep-2026-10-02'
check ask 'git push -u origin chore/backlog-x'
touch "$MARKER"
check allow 'git push -u origin feature/x'
[ "$fail" = 0 ]
