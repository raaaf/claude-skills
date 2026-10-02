#!/usr/bin/env bash
#
# Pins nightly-repos.sh (2026-10-01): status per repo from origin/<default> content, ordering, worktree
# dedupe, non-audited repos ignored. Local bare remotes via url.insteadOf, gh stubbed through PATH.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SCRIPT="$SCRIPT_DIR/${NIGHTLY_REPOS_UNDER_TEST:-nightly-repos.sh}"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
export GIT_CONFIG_GLOBAL="$TMP/gitconfig"
git config --global user.email t@t; git config --global user.name t
git config --global init.defaultBranch main

# make_repo <name> <backlog-lines> <audited 1|0>: repo with a github-looking origin served by a local bare repo
make_repo() {
  local name="$1" lines="$2" audited="$3" r="$TMP/root/$1"
  git init -q --bare "$TMP/remotes/$name.git"
  git config --global "url.$TMP/remotes/$name.git.insteadOf" "https://github.com/t/$name.git"
  git init -q "$r"; git -C "$r" remote add origin "https://github.com/t/$name.git"
  if [ "$audited" = 1 ]; then
    mkdir -p "$r/.audit"
    : > "$r/.audit/minor-backlog.tsv"
    local i=0; while [ "$i" -lt "$lines" ]; do printf 'k%s\tcopy\ta.txt\t1\t2026-10-01\tx\n' "$i" >> "$r/.audit/minor-backlog.tsv"; i=$((i+1)); done
  fi
  echo hi > "$r/a.txt"
  git -C "$r" add -A; git -C "$r" commit -q -m init
  git -C "$r" push -q origin main 2>/dev/null; git -C "$r" remote set-head origin main >/dev/null 2>&1 || true
}
mkdir -p "$TMP/root" "$TMP/remotes" "$TMP/bin"
make_repo big 3 1
make_repo small 1 1
make_repo plain 0 0
make_repo prd 2 1
make_repo idle 0 1
# legacy: backlog still at the old .claude/audits/ path on origin (fallback read)
make_repo legacy 0 0
mkdir -p "$TMP/root/legacy/.claude/audits"
printf 'k1\tcopy\ta.txt\t1\t2026-10-01\tx\nk2\tcopy\ta.txt\t1\t2026-10-01\ty\n' > "$TMP/root/legacy/.claude/audits/minor-backlog.tsv"
git -C "$TMP/root/legacy" add -A; git -C "$TMP/root/legacy" commit -q -m legacy
git -C "$TMP/root/legacy" push -q origin main
# idle: no visual files either (history older than 7 days)
GIT_COMMITTER_DATE="2020-01-01T00:00:00" GIT_AUTHOR_DATE="2020-01-01T00:00:00" git -C "$TMP/root/idle" commit -q --amend --no-edit --reset-author
git -C "$TMP/root/idle" push -q -f origin main
# a worktree of big under _worktrees must not be listed separately
mkdir -p "$TMP/root/_worktrees"
git -C "$TMP/root/big" worktree add -q "$TMP/root/_worktrees/big-wt" -b wt-branch >/dev/null 2>&1

# capped: 3 new files plus a.txt, cap 3
make_repo capped 0 1
for f in x1 x2 x3; do echo "$f" > "$TMP/root/capped/$f.txt"; done
git -C "$TMP/root/capped" add -A; git -C "$TMP/root/capped" commit -q -m files
git -C "$TMP/root/capped" push -q origin main

cat > "$TMP/bin/gh" <<'GH'
#!/usr/bin/env bash
case "$1" in
  auth) exit 0 ;;
  pr) if [ "$(basename "$PWD")" = prd ]; then echo 17; fi; exit 0 ;;
esac
GH
chmod +x "$TMP/bin/gh"

OUT=$(NIGHTLY_ALLOW_FILE=/nonexistent AUDIT_VISUAL_PASS_CAP=3 PATH="$TMP/bin:$PATH" bash "$SCRIPT" "$TMP/root")
expect() {
  printf '%s\n' "$OUT" | grep -qF -- "$1" || { printf 'FAIL %s\n%s\n' "$2" "$OUT" >&2; exit 1; }
  printf 'PASS %s\n' "$2"
}
expect "$TMP/root/big	ready	backlog=3" 'ready with backlog'
expect "$TMP/root/capped	ready	backlog=0 visual_files=4 (cap 3)" 'visual files above the cap are flagged'
expect "$TMP/root/small	ready	backlog=1 visual_files=1" 'visual files below the cap are not flagged'
expect "$TMP/root/legacy	ready	backlog=2" 'legacy path is read as fallback'
expect "$TMP/root/prd	skip-open-pr	#17" 'open PR skips'
expect "$TMP/root/idle	nothing	" 'nothing to do'
expect "$TMP/root/small	ready	backlog=1" 'second ready'
[ "$(printf '%s\n' "$OUT" | grep -c plain)" = 0 ] || { echo 'FAIL non-audited repo listed' >&2; exit 1; }
echo 'PASS non-audited repo ignored'
[ "$(printf '%s\n' "$OUT" | grep -c 'big-wt')" = 0 ] || { echo 'FAIL worktree listed' >&2; exit 1; }
echo 'PASS worktree deduped'
[ "$(printf '%s\n' "$OUT" | sed -n 1p | cut -f1)" = "$TMP/root/big" ] || { echo 'FAIL ready order' >&2; exit 1; }
echo 'PASS ready sorted by backlog desc'

# Allowlist (2026-10-02): when the file exists, only listed repos are reported; ~ and comments allowed.
printf '# production only\n%s/root/small\n' "$TMP" > "$TMP/allow"
ALLOWED=$(NIGHTLY_ALLOW_FILE="$TMP/allow" AUDIT_VISUAL_PASS_CAP=3 PATH="$TMP/bin:$PATH" bash "$SCRIPT" "$TMP/root")
[ "$(printf '%s\n' "$ALLOWED" | grep -c .)" = 1 ] && printf '%s\n' "$ALLOWED" | grep -q "^$TMP/root/small	" || { printf 'FAIL allowlist\n%s\n' "$ALLOWED" >&2; exit 1; }
echo 'PASS allowlist keeps only listed repos'
