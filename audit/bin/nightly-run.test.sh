#!/usr/bin/env bash
#
# Pins nightly-run.sh --dry-run (2026-10-01): lists ready and skipped repos, creates no worktree, writes no
# report, never calls claude (a stub claude on PATH records any invocation).
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SCRIPT="$SCRIPT_DIR/${NIGHTLY_RUN_UNDER_TEST:-nightly-run.sh}"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
export GIT_CONFIG_GLOBAL="$TMP/gitconfig" HOME="$TMP/home"
mkdir -p "$HOME" "$TMP/bin" "$TMP/remotes"
git config --global user.email t@t; git config --global user.name t; git config --global init.defaultBranch main

make_repo() {
  local name="$1" r="$TMP/root/$1"
  git init -q --bare "$TMP/remotes/$name.git"
  git config --global "url.$TMP/remotes/$name.git.insteadOf" "https://github.com/t/$name.git"
  git init -q "$r"; git -C "$r" remote add origin "https://github.com/t/$name.git"
  mkdir -p "$r/.claude/audits"; printf 'k\tcopy\ta.txt\t1\t2026-10-01\tx\n' > "$r/.claude/audits/minor-backlog.tsv"
  echo hi > "$r/a.txt"; git -C "$r" add -A; git -C "$r" commit -q -m init
  git -C "$r" push -q origin main 2>/dev/null; git -C "$r" remote set-head origin main >/dev/null 2>&1 || true
}
make_repo alpha
printf '#!/usr/bin/env bash\nexit 0\n' > "$TMP/bin/gh"
printf '#!/usr/bin/env bash\necho CLAUDE-CALLED > "%s/claude-called"\n' "$TMP" > "$TMP/bin/claude"
chmod +x "$TMP/bin/gh" "$TMP/bin/claude"

OUT=$(NIGHTLY_ALLOW_FILE=/nonexistent PATH="$TMP/bin:$PATH" bash "$SCRIPT" --dry-run "$TMP/root")
printf '%s\n' "$OUT" | grep -qF "WOULD RUN  $TMP/root/alpha (backlog=1" || { printf 'FAIL no WOULD RUN line\n%s\n' "$OUT" >&2; exit 1; }
[ ! -e "$TMP/claude-called" ] || { echo 'FAIL claude was invoked' >&2; exit 1; }
[ "$(git -C "$TMP/root/alpha" worktree list | wc -l | tr -d ' ')" = 1 ] || { echo 'FAIL worktree created' >&2; exit 1; }
[ ! -e "$HOME/.local/state/claude/nightly" ] || { echo 'FAIL report written in dry-run' >&2; exit 1; }
echo 'PASS dry-run lists the repo, no claude, no worktree, no report'

# --- real runs with a stub claude: sentinel, resume, failure, allow list ---
printf '#!/usr/bin/env bash\necho "$*" >> "%s/claude-args"\nn=$(cat "%s/count" 2>/dev/null || echo 0); n=$((n+1)); echo $n > "%s/count"\ncat "%s/out.$n" 2>/dev/null || cat "%s/out.last"\n' "$TMP" "$TMP" "$TMP" "$TMP" "$TMP" > "$TMP/bin/claude"
chmod +x "$TMP/bin/claude"
run_real() { # <outputs...>: out.1..N; the last one repeats
  rm -f "$TMP/count" "$TMP/claude-args" "$TMP"/out.*; rm -rf "$HOME/.local/state/claude/nightly"
  local i=0 o
  for o in "$@"; do i=$((i+1)); printf '%s' "$o" > "$TMP/out.$i"; done
  cp "$TMP/out.$i" "$TMP/out.last"
  NIGHTLY_ALLOW_FILE=/nonexistent HEADLESS_POLL_SECS=0.2 PATH="$TMP/bin:$PATH" bash "$SCRIPT" "$TMP/root" >/dev/null
  cat "$HOME/.local/state/claude/nightly/"*.md
}
NO='{"session_id":"s1","result":"find.js is running"}'
YES='{"session_id":"s1","result":"fertig\nNIGHTLY_DONE"}'

R=$(run_real "$NO" "$YES")
[ "$(cat "$TMP/count")" = 2 ] || { echo 'FAIL (a) expected exactly 2 claude calls' >&2; exit 1; }
grep -qF -- '--resume s1' "$TMP/claude-args" || { echo 'FAIL (a) second call lacks --resume s1' >&2; exit 1; }
grep -qF 'Warte auf laufende Workflows' "$TMP/claude-args" || { echo 'FAIL (a) resume prompt missing' >&2; exit 1; }
printf '%s\n' "$R" | grep -qF '1 resume(s)' && ! printf '%s\n' "$R" | grep -q 'failed' || { printf 'FAIL (a) report\n%s\n' "$R" >&2; exit 1; }
echo 'PASS (a) missing sentinel resumes once, second output ends the run'

R=$(run_real "$NO")
[ "$(cat "$TMP/count")" = 4 ] || { echo 'FAIL (b) expected 1 start + 3 resumes' >&2; exit 1; }
printf '%s\n' "$R" | grep -qF 'failed (no NIGHTLY_DONE after 3 resumes)' || { printf 'FAIL (b) report\n%s\n' "$R" >&2; exit 1; }
echo 'PASS (b) three resumes without sentinel end in a reported failure'

if grep -qE 'dangerously-skip-permissions|bypassPermissions' "$TMP/claude-args"; then echo 'FAIL (c) bypass flag passed' >&2; exit 1; fi
grep -qF -- '--allowedTools' "$TMP/claude-args" && grep -qF 'git push -u origin chore/nightly-audit-*' "$TMP/claude-args" \
  || { echo 'FAIL (c) allow list missing' >&2; exit 1; }
echo 'PASS (c) explicit allow list, no bypass flag'

DRY=$(NIGHTLY_ALLOW_FILE=/nonexistent PATH="$TMP/bin:$PATH" bash "$SCRIPT" --dry-run "$TMP/root")
printf '%s\n' "$DRY" | grep -qF 'COMMAND    claude -p' || { echo 'FAIL dry-run prints no claude command' >&2; exit 1; }
echo 'PASS dry-run prints the claude command'
