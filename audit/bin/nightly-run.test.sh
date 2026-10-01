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

OUT=$(PATH="$TMP/bin:$PATH" bash "$SCRIPT" --dry-run "$TMP/root")
printf '%s\n' "$OUT" | grep -qF "WOULD RUN  $TMP/root/alpha (backlog=1" || { printf 'FAIL no WOULD RUN line\n%s\n' "$OUT" >&2; exit 1; }
[ ! -e "$TMP/claude-called" ] || { echo 'FAIL claude was invoked' >&2; exit 1; }
[ "$(git -C "$TMP/root/alpha" worktree list | wc -l | tr -d ' ')" = 1 ] || { echo 'FAIL worktree created' >&2; exit 1; }
[ ! -e "$HOME/.local/state/claude/nightly" ] || { echo 'FAIL report written in dry-run' >&2; exit 1; }
echo 'PASS dry-run lists the repo, no claude, no worktree, no report'
