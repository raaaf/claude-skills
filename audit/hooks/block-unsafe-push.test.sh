#!/usr/bin/env bash
#
# Pins the nightly exception of block-unsafe-push.sh (2026-10-01): a marker-less push is allowed only for
# chore/nightly-audit-* and chore/minor-backlog-* branches; every other shape still asks.
set -euo pipefail
HOOK="$(cd "$(dirname "$0")" && pwd)/${HOOK_UNDER_TEST:-block-unsafe-push.sh}"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
# A cwd with no audit marker, on a nightly branch.
git init -q "$TMP/repo"
git -C "$TMP/repo" -c user.email=t@t -c user.name=t commit -q --allow-empty -m init
git -C "$TMP/repo" checkout -q -b chore/nightly-audit-2026-10-02

run() { jq -n --arg c "$1" --arg d "$TMP/repo" '{tool_input:{command:$c},cwd:$d}' | bash "$HOOK"; }
fail=0
check() {
  local want="$1" cmd="$2" out
  out=$(run "$cmd")
  if [ "$want" = allow ] && [ -z "$out" ]; then printf 'PASS allow: %s\n' "$cmd"
  elif [ "$want" = ask ] && printf '%s' "$out" | grep -q '"ask"'; then printf 'PASS ask: %s\n' "$cmd"
  else printf 'FAIL want=%s: %s\n  got: %s\n' "$want" "$cmd" "$out" >&2; fail=1; fi
}

check allow 'git push -u origin chore/nightly-audit-2026-10-02'
check allow 'git push origin chore/minor-backlog-2026-10-02'
check allow 'git push'
check allow 'git push origin HEAD'
check ask 'git push --force -u origin chore/nightly-audit-2026-10-02'
check ask 'git push -f origin chore/nightly-audit-2026-10-02'
check ask 'git push origin +chore/nightly-audit-x'
check ask 'git push origin chore/nightly-audit-x:main'
check ask 'git push origin main'
check ask 'git push origin feature/x'
check ask 'git push --all'
check ask 'git push --tags origin chore/nightly-audit-x'
check ask 'git push origin --delete chore/nightly-audit-x'
check ask 'git push origin chore/nightly-audit-x && git push origin main'
check ask 'git push origin chore/nightly-audit-x main'
git -C "$TMP/repo" checkout -q -b feature/y
check ask 'git push'
[ "$fail" = 0 ]
