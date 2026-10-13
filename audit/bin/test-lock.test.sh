#!/usr/bin/env bash
# Pins test-lock.sh's `--cmd "<string>"` form (zsh does not word-split $TEST_COMMAND) and that
# the lock key still carries the -destination id in both the argv and the --cmd form.
# Usage: bash audit/bin/test-lock.test.sh
set -u
HERE=$(cd "$(dirname "$0")" && pwd)
LOCK="$HERE/test-lock.sh"
TMP=$(mktemp -d "${TMPDIR:-/tmp}/test-lock-test.XXXXXX")
trap 'rm -rf "$TMP"' EXIT
git -C "$TMP" init -q
GC="$TMP/.git"
cd "$TMP" || exit 1
FAIL=0
check() { # name expected actual
  if [ "$2" = "$3" ]; then echo "ok   $1"; else echo "FAIL $1: expected [$2] got [$3]"; FAIL=$((FAIL + 1)); fi
}

check "--cmd word-splits a multi-word string" "a b" "$(bash "$LOCK" --cmd "printf '%s %s' a b" 2>&1)"
check "--cmd passes the exit status through" "3" "$(bash "$LOCK" --cmd "exit 3" >/dev/null 2>&1; echo $?)"
check "--cmd without a string is a usage error" "64" "$(bash "$LOCK" --cmd >/dev/null 2>&1; echo $?)"
check "argv form keys on the destination id" "KEYED" \
  "$(bash "$LOCK" bash -c '[ -d "$0/claude-audit-test-lock-AAA" ] && echo KEYED' "$GC" -destination 'platform=iOS Simulator,id=AAA' 2>&1)"
check "--cmd form keys on the destination id inside a quoted string" "KEYED" \
  "$(bash "$LOCK" --cmd "[ -d '$GC/claude-audit-test-lock-BBB' ] && echo KEYED; : xcodebuild test -destination 'platform=iOS Simulator,id=BBB' -scheme X" 2>&1)"
check "--cmd without a destination keys on the repo only" "KEYED" \
  "$(bash "$LOCK" --cmd "[ -d '$GC/claude-audit-test-lock' ] && echo KEYED" 2>&1)"


# A linked worktree shares the main checkout's test database, so it must take the same lock.
git -C "$TMP" -c user.email=t@t -c user.name=t commit -q --allow-empty -m init
git -C "$TMP" worktree add -q "$TMP/wt" 2>/dev/null
check "a linked worktree locks in the main checkout's common git dir" "KEYED" \
  "$(cd "$TMP/wt" && bash "$LOCK" --cmd "[ -d '$GC/claude-audit-test-lock' ] && echo KEYED" 2>&1)"

# A waiter prints a progress line, so a caller's output-stall watchdog (deploy's test gate)
# does not mistake waiting for the lock for a hung test run.
mkdir "$GC/claude-audit-test-lock"
OUT="$TMP/wait.out"
TEST_LOCK_NOTICE_SECONDS=2 bash "$LOCK" --cmd "true" >"$OUT" 2>&1 &
WAITER=$!
sleep 5
rmdir "$GC/claude-audit-test-lock"
wait "$WAITER"
check "a waiter reports that it is waiting" "yes" "$(grep -q 'test-lock: waiting' "$OUT" && echo yes || echo no)"

# A wrapped command that itself goes through test-lock.sh (deploy's test gate does) must not wait
# for the lock its own parent holds: on 2026-10-03 /ship wrapped `deploy zeit test` and the inner
# call waited 960s on itself, then aborted without running a test.
OUT="$TMP/nested.out"
bash "$LOCK" bash "$LOCK" --cmd "echo INNER" >"$OUT" 2>&1 &
NESTED=$!
sleep 4
kill "$NESTED" 2>/dev/null && pkill -f "test-lock.sh --cmd echo INNER" 2>/dev/null
wait "$NESTED" 2>/dev/null
check "a nested call runs under the lock its parent holds" "INNER" "$(grep -x INNER "$OUT")"
check "a nested call leaves the parent's lock to the parent" "gone" "$([ -d "$GC/claude-audit-test-lock" ] && rm -rf "$GC/claude-audit-test-lock" && echo left || echo gone)"

# test-isolation: worktree in .claude/ship.md moves a linked worktree to its own lock key; the main
# checkout, a worktree without the flag and TEST_LOCK_KEY=common (mutate.sh) keep the shared one.
WTGIT=$(git -C "$TMP/wt" rev-parse --path-format=absolute --git-dir)
mkdir -p "$TMP/wt/.claude"; printf 'test-isolation: worktree\n' > "$TMP/wt/.claude/ship.md"
check "a flagged linked worktree locks on its own git dir" "KEYED" \
  "$(cd "$TMP/wt" && bash "$LOCK" --cmd "[ -d '$WTGIT/claude-audit-test-lock' ] && [ ! -d '$GC/claude-audit-test-lock' ] && echo KEYED" 2>&1)"
check "TEST_LOCK_KEY=common keeps the shared key for a flagged worktree" "KEYED" \
  "$(cd "$TMP/wt" && TEST_LOCK_KEY=common bash "$LOCK" --cmd "[ -d '$GC/claude-audit-test-lock' ] && echo KEYED" 2>&1)"
mkdir -p "$TMP/.claude"; printf 'test-isolation: worktree\n' > "$TMP/.claude/ship.md"
check "the main checkout keeps the shared key even with the flag" "KEYED" \
  "$(bash "$LOCK" --cmd "[ -d '$GC/claude-audit-test-lock' ] && echo KEYED" 2>&1)"
rm -rf "$TMP/.claude" "$TMP/wt/.claude"

# Admission: TESTRUN_CLASS=suite runs the command as an admitted suite run, TESTRUN_DISABLE=1 does not.
export TESTRUN_STATE_DIR="$TMP/trstate" TESTRUN_PRESSURE=1 TESTRUN_FREE_PCT=50 TESTRUN_STAGGER=0 TESTRUN_TOOL_VERSIONS=fixed
COUNT_CMD='ls "$TESTRUN_STATE_DIR/runs" 2>/dev/null | grep -vc "\\." ; :'
check "a suite run is admitted for the duration of the command" "1" "$(TESTRUN_CLASS=suite bash "$LOCK" --cmd "$COUNT_CMD" 2>/dev/null | grep -v '^TESTRUN' | head -1)"
check "the ticket is gone afterwards" "0" "$(ls "$TESTRUN_STATE_DIR/runs" 2>/dev/null | grep -vc '\.')"
CLASS_CMD='for f in "$TESTRUN_STATE_DIR"/runs/*; do case "${f##*/}" in *.*) ;; *) sed -n "s/^class=//p" "$f" ;; esac; done | head -1'
check "a plain suite command runs as class suite" "suite" "$(TESTRUN_CLASS=suite bash "$LOCK" --cmd "$CLASS_CMD" 2>/dev/null | grep -v '^TESTRUN ')"
check "a command string that calls xcodebuild runs as class xcode" "xcode" "$(TESTRUN_CLASS=suite bash "$LOCK" --cmd "$CLASS_CMD # xcodebuild test" 2>/dev/null | grep -v '^TESTRUN ')"
printf '#!/bin/bash\n# runs the UI tests: xcodebuild test -scheme X\n%s\n' "$CLASS_CMD" > "$TMP/ui-tests.sh"
check "a script file that calls xcodebuild runs as class xcode (stall limit 900 s, not 300 s)" "xcode" "$(TESTRUN_CLASS=suite bash "$LOCK" --cmd "bash $TMP/ui-tests.sh" 2>/dev/null | grep -v '^TESTRUN ')"
rm -rf "$TESTRUN_STATE_DIR"
check "TESTRUN_DISABLE=1 admits nothing" "0" "$(TESTRUN_DISABLE=1 TESTRUN_CLASS=suite bash "$LOCK" --cmd "$COUNT_CMD" 2>/dev/null | grep -v '^TESTRUN' | head -1)"

# --cached: a green full run on an identical tree is not repeated; a red one is never cached.
CR="$TMP/cr"; mkdir -p "$CR"; git -C "$CR" init -q; echo a > "$CR/a"
git -C "$CR" add -A; git -C "$CR" -c user.email=t@t -c user.name=t commit -q -m i
rm -rf "$TESTRUN_STATE_DIR"; : > "$TMP/runs.count"
( cd "$CR" && bash "$LOCK" --cached --cmd "echo run >> '$TMP/runs.count'" >/dev/null 2>&1 )
OUT=$(cd "$CR" && bash "$LOCK" --cached --cmd "echo run >> '$TMP/runs.count'" 2>&1)
check "a repeated green full run is answered from the cache" "1 TEST_CACHE_HIT" "$(grep -c run "$TMP/runs.count") $(printf '%s' "$OUT" | grep -o TEST_CACHE_HIT | head -1)"
echo b > "$CR/a"
( cd "$CR" && bash "$LOCK" --cached --cmd "echo run >> '$TMP/runs.count'" >/dev/null 2>&1 )
check "a changed tree runs again" "2" "$(grep -c run "$TMP/runs.count")"
rm -rf "$TESTRUN_STATE_DIR"; : > "$TMP/runs.count"
for i in 1 2; do ( cd "$CR" && bash "$LOCK" --cached --cmd "echo run >> '$TMP/runs.count'; exit 1" >/dev/null 2>&1 ); done
check "a red full run is not cached" "2" "$(grep -c run "$TMP/runs.count")"
check "a red full run keeps its exit code" "1" "$(cd "$CR" && bash "$LOCK" --cached --cmd "exit 1" >/dev/null 2>&1; echo $?)"

# A reentrant call (deploy inside /audit or /ship, both hold the lock) still reads and writes the cache, under
# TESTRUN_CACHE_CMD: that is the key deploy's push gate looks up. Before, the exec shortcut skipped both.
rm -rf "$TESTRUN_STATE_DIR"; : > "$TMP/runs.count"; echo a > "$CR/a"
INNER="bash '$LOCK' --cached --cmd \"echo run >> '$TMP/runs.count'\""
( cd "$CR" && TESTRUN_CACHE_CMD="composer test" bash "$LOCK" --cmd "$INNER" >/dev/null 2>&1 )
check "a reentrant --cached call runs once and stores the entry under TESTRUN_CACHE_CMD" "1 hit" \
  "$(grep -c run "$TMP/runs.count") $(cd "$CR" && bash -c '. "$1"; tr_cache_lookup "$2" "composer test" && echo hit || echo miss' _ "$HERE/lib-testrun.sh" "$CR")"
( cd "$CR" && TESTRUN_CACHE_CMD="composer test" bash "$LOCK" --cmd "$INNER" >/dev/null 2>&1 )
check "the same wrapped call again is answered from that entry" "1" "$(grep -c run "$TMP/runs.count")"

# The tree is hashed before the run: a command that writes into the tree does not cache its own output.
rm -rf "$TESTRUN_STATE_DIR"; : > "$TMP/runs.count"; echo a > "$CR/a"
for i in 1 2; do ( cd "$CR" && bash "$LOCK" --cached --cmd "echo changed-\$RANDOM >> '$CR/a'; echo run >> '$TMP/runs.count'" >/dev/null 2>&1 ); done
check "a run that modifies the tree is not served from its own post-run state" "2" "$(grep -c run "$TMP/runs.count")"
unset TESTRUN_STATE_DIR

[ "$FAIL" -eq 0 ] && echo "TEST_LOCK_TEST=OK" || { echo "TEST_LOCK_TEST=FAIL ($FAIL)"; exit 1; }
