#!/usr/bin/env bash
#
# Pins block-unsafe-push.sh: a push that lands on main/master needs a fresh audit marker (30 min TTL);
# without one the hook asks. Pushes to any other branch and non-push commands pass untouched
# (owner decision 2026-11-27).
set -euo pipefail
HOOK="$(cd "$(dirname "$0")" && pwd)/${HOOK_UNDER_TEST:-block-unsafe-push.sh}"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"; rm -f "$MARKER"' EXIT
git init -q -b main "$TMP/repo"
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
check allow 'git push -u origin feature/x'
check allow 'git push origin fix/main-menu'
check ask 'git push'
check ask 'git push origin'
check ask 'git push origin main'
check ask 'git push origin HEAD:master'
check ask 'git push origin +feature/x:refs/heads/main'
check ask 'git push --all'
check ask "git -C $CWD push"
git -C "$CWD" switch -q -c feature/y
check allow 'git push'
check allow 'git push origin HEAD'
check ask "git -C $CWD push origin main"
check ask 'git push origin feature/z && git push origin main'
check ask 'echo push; git push origin main'
check ask 'git push origin "main"'
check ask "git push origin 'HEAD:main'"
check ask 'git push origin "$B"'
check ask 'git push origin refs/heads/*:refs/heads/*'
check ask 'cd /elsewhere && git push'
check ask 'git --git-dir=/elsewhere/.git push'
check allow 'git push -o ci.skip origin feature/y'
check ask 'git push -o ci.skip origin main'
git -C "$CWD" switch -q main
touch "$MARKER"
check allow 'git push origin main'

# A marker recorded for a tree with a new untracked file must hold while the file is still untracked
# (the guard must hash the same tree as orch_tree_hash) and after it is committed.
printf 'new\n' > "$CWD/new.php"
(cd "$CWD" && bash "$(dirname "$HOOK")/../bin/tree-hash.sh") > "$MARKER"
check allow 'git push origin main'
git -C "$CWD" add -A
git -C "$CWD" -c user.email=t@t -c user.name=t commit -q -m add
check allow 'git push origin main'
[ "$fail" = 0 ]
