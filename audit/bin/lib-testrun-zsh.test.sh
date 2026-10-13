#!/usr/bin/env bash
#
# Pins that lib-testrun.sh splits lists the same when sourced from zsh as from bash (2026-10-13): the Bash
# tool of Claude Code runs zsh, which does not word-split an unquoted $var. tr_worktree_cleanup then issued
# ONE `DROP DATABASE "a\nb\nc"` for three databases, which failed silently while the db_drop event claimed
# success. Same for the pid list of tr_kill_tree and the file/ignore lists of the test-cache delta check.
# Usage: bash audit/bin/lib-testrun-zsh.test.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
command -v zsh >/dev/null 2>&1 || { echo 'SKIP zsh not installed'; exit 0; }

TMP=$(cd "$(mktemp -d "${TMPDIR:-/tmp}/lib-testrun-zsh-test.XXXXXX")" && pwd -P)
SLEEPERS=""
trap 'for p in $SLEEPERS; do kill "$p" 2>/dev/null || true; done; rm -rf "$TMP"' EXIT

expect() {
  local got="$1" expected="$2" label="$3"
  [[ "$got" == "$expected" ]] || {
    printf 'FAIL %s\nExpected: %s\nGot: %s\n' "$label" "$expected" "$got" >&2
    exit 1
  }
  printf 'PASS %s\n' "$label"
}

export TESTRUN_STATE_DIR="$TMP/state"
export TESTRUN_AUDIT_BIN="$SCRIPT_DIR"
unset TESTRUN_DISABLE TESTRUN_ID
TOP="$TMP/wt"
mkdir -p "$TOP" "$TMP/state"

# --- tr_worktree_cleanup: one DROP per database -------------------------------------------------
SLUG=$(bash -c ". '$SCRIPT_DIR/lib-testrun.sh'; tr_slug '$TOP'")
BASE="x_$SLUG"
printf '%s\n' "$BASE" > "$TMP/state/test-dbs.list"
cat > "$TMP/psql" <<PSQL
#!/usr/bin/env bash
printf '%s\n' "\$*" >> "$TMP/psql.log"
case "\$*" in
  *"select datname"*) printf '%s\n' "$BASE" "${BASE}_test_1" "${BASE}_test_2" ;;
esac
PSQL
chmod +x "$TMP/psql"
export TESTRUN_PSQL="$TMP/psql"

zsh -c ". '$SCRIPT_DIR/lib-testrun.sh'; tr_worktree_cleanup '$TOP'" >/dev/null 2>&1
expect "$(grep -c 'DROP DATABASE' "$TMP/psql.log" || true)" 3 'zsh: tr_worktree_cleanup issues one DROP per database'
expect "$(grep 'DROP DATABASE' "$TMP/psql.log" | sed 's/.*IF EXISTS "\([^"]*\)".*/\1/' | tr '\n' ' ')" \
  "$BASE ${BASE}_test_1 ${BASE}_test_2 " 'zsh: each DROP names exactly one database'
expect "$(wc -l < "$TMP/state/test-dbs.list" | tr -d ' ')" 0 'zsh: the database is unlisted afterwards'

# --- tr_kill_tree: a multi-pid group is fully signalled -----------------------------------------
# A job-control group holding a shell and two sleeps: the pid list has several lines.
set -m
bash -c 'sleep 300 & sleep 300 & wait' &
LEADER=$!
set +m
SLEEPERS="$LEADER"
sleep 0.5
PGID=$(ps -o pgid= -p "$LEADER" | tr -d ' ')
MEMBERS=$(ps -ax -o pid=,pgid= | awk -v g="$PGID" '$2 == g { n++ } END { print n + 0 }')
expect "$MEMBERS" 3 'fixture: the group has three members'
TESTRUN_KILL_GRACE=1 zsh -c ". '$SCRIPT_DIR/lib-testrun.sh'; tr_kill_tree '$PGID' zsh-test" >/dev/null 2>&1 || true
expect "$(ps -ax -o pid=,pgid= | awk -v g="$PGID" '$2 == g { n++ } END { print n + 0 }')" 0 'zsh: tr_kill_tree leaves no group member alive'

# --- cache delta: ignore globs split into separate patterns --------------------------------------
REPO="$TMP/repo"
mkdir -p "$REPO/docs" "$REPO/.claude"
git -C "$REPO" init -q -b main .
git -C "$REPO" config user.email test@test.com
git -C "$REPO" config user.name test
echo a > "$REPO/docs/a.md"; echo b > "$REPO/docs/b.md"
git -C "$REPO" add -A
git -C "$REPO" commit -q -m c1
T1=$(git -C "$REPO" rev-parse 'HEAD^{tree}')
echo a2 >> "$REPO/docs/a.md"; echo b2 >> "$REPO/docs/b.md"
git -C "$REPO" commit -q -am c2
T2=$(git -C "$REPO" rev-parse 'HEAD^{tree}')
printf 'test-cache-ignore: other/* docs/*\n' > "$REPO/.claude/ship.md"
expect "$(zsh -c ". '$SCRIPT_DIR/lib-testrun.sh'; _tr_cache_delta_ok '$REPO' $T1 $T2 && echo hit || echo miss")" hit \
  'zsh: two changed files under the second of two ignore globs still hit'
