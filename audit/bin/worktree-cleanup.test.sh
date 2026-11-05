#!/usr/bin/env bash
# Pins worktree-cleanup.sh: refusals leave everything in place, a clean pushed worktree goes (with its branch,
# its registered databases and the process group of its test run), unrelated processes and databases stay.
# Temp repo, temp state dir, fake psql, fake sleepers only.
# Usage: bash audit/bin/worktree-cleanup.test.sh
set -u
HERE=$(cd "$(dirname "$0")" && pwd)
CLEAN="$HERE/worktree-cleanup.sh"
TMP=$(cd "$(mktemp -d "${TMPDIR:-/tmp}/wt-clean-test.XXXXXX")" && pwd -P)
SLEEPERS=""
trap 'for p in $SLEEPERS; do kill "$p" 2>/dev/null; done; rm -rf "$TMP"' EXIT
FAIL=0
check() { if [ "$2" = "$3" ]; then echo "ok   $1"; else echo "FAIL $1: expected [$2] got [$3]"; FAIL=$((FAIL + 1)); fi; }
G() { git -c user.email=t@t -c user.name=t "$@"; }

export TESTRUN_STATE_DIR="$TMP/state" TESTRUN_KILL_GRACE=1; mkdir -p "$TESTRUN_STATE_DIR/runs"
git init -q --bare "$TMP/origin.git"
git clone -q "$TMP/origin.git" "$TMP/main" 2>/dev/null
( cd "$TMP/main" && git checkout -q -b main 2>/dev/null; echo a > f; G add -A; G commit -qm init; git push -q origin main 2>/dev/null )
mkwt() { # <name>: pushed branch worktree
  G -C "$TMP/main" worktree add -q -b "feature/$1" "$TMP/$1" main
  G -C "$TMP/$1" push -q origin "feature/$1" 2>/dev/null
}
run() { bash "$CLEAN" "$1" >/dev/null 2>"$TMP/err"; echo $?; }

mkwt dirty; echo x > "$TMP/dirty/new.txt"
check "uncommitted (untracked) file: refused with exit 1" "1" "$(run "$TMP/dirty")"
check "the refusal is one line and the worktree stays" "1 yes" "$(grep -c . "$TMP/err") $([ -d "$TMP/dirty" ] && echo yes)"

mkwt ahead; ( cd "$TMP/ahead" && echo b > g && G add -A && G commit -qm unpushed )
check "unpushed commit: refused" "1 yes" "$(run "$TMP/ahead") $(grep -q 'not on any remote' "$TMP/err" && echo yes)"
check "main checkout: refused with its own reason" "1 yes" "$(run "$TMP/main") $(grep -q 'main checkout' "$TMP/err" && echo yes)"

# clean worktree with a run ticket, a registered DB and an orphan; an unrelated process and DB stay
mkwt done; mkdir -p "$TMP/done/vendor"; echo ign > "$TMP/main/.gitignore"
( cd "$TMP/main" && G add .gitignore && G commit -qm ign && git push -q origin main 2>/dev/null ); G -C "$TMP/done" merge -q main 2>/dev/null; G -C "$TMP/done" push -q origin "feature/done" 2>/dev/null
echo "vendor/" >> "$TMP/main/.git/info/exclude"
{ set -m; ( cd "$TMP/done" && exec sleep 300 ) & RUNPID=$!; set +m; } 2>/dev/null
sleep 300 & OTHER=$!; SLEEPERS="$SLEEPERS $RUNPID $OTHER"
ID="$(printf '%010d%06d' "$(date +%s)" 1)-$RUNPID"
START=$(ps -o lstart= -p $$ | sed 's/^ *//;s/ *$//'); PST=$(ps -o lstart= -p "$RUNPID" | sed 's/^ *//;s/ *$//')
printf 'pid=%s\nstart=%s\nclass=suite\nstate=running\nproject=main\ncwd=%s\nargs=x\nsince=%s\npgid=%s\npgid_start=%s\n' \
  "$$" "$START" "$TMP/done" "$(date +%s)" "$RUNPID" "$PST" > "$TESTRUN_STATE_DIR/runs/$ID"
SLUG=$(printf '%s' "$TMP/done" | shasum | cut -c1-8)
printf 'zeit_testing_%s\nother_testing_aaaaaaaa\n' "$SLUG" > "$TESTRUN_STATE_DIR/test-dbs.list"
cat > "$TMP/fake-psql" <<'FEOF'
#!/bin/bash
echo "$*" >> "$(dirname "$0")/psql.log"
case "$*" in *"from pg_database"*) printf '%s\n' $FAKE_PG_ROWS ;; esac
FEOF
chmod +x "$TMP/fake-psql"; : > "$TMP/psql.log"
export TESTRUN_PSQL="$TMP/fake-psql" FAKE_PG_ROWS="zeit_testing_$SLUG other_testing_aaaaaaaa"
# an orphan (parent 1) with its cwd in the worktree that shares its process group with a survivor must not take the survivor down
{ set -m; bash -c 'sleep 321 & ( cd "'"$TMP"'/done" && sleep 322 & ) ; wait' & SURVLEAD=$!; set +m; } 2>/dev/null
sleep 0.7
SURVKID=$(pgrep -P "$SURVLEAD" | head -1); ORPH=$(pgrep -f "^sleep 322" | head -1)
SLEEPERS="$SLEEPERS $SURVLEAD $SURVKID"
check "clean pushed worktree: removed with exit 0" "0" "$(run "$TMP/done")"
check "the worktree directory (also ignored leftovers) is gone" "no" "$([ -e "$TMP/done" ] && echo yes || echo no)"
check "the branch is gone" "" "$(git -C "$TMP/main" branch --list 'feature/done')"
check "the test run's process group was killed" "no" "$(kill -0 "$RUNPID" 2>/dev/null && echo yes || echo no)"
check "the worktree orphan is gone, its group's survivors stay" "dead alive alive" "$(kill -0 "$ORPH" 2>/dev/null && echo alive || echo dead) $(kill -0 "$SURVLEAD" 2>/dev/null && echo alive || echo dead) $(kill -0 "$SURVKID" 2>/dev/null && echo alive || echo dead)"
kill -- -"$SURVLEAD" 2>/dev/null
check "an unrelated process is untouched" "yes" "$(kill -0 "$OTHER" 2>/dev/null && echo yes || echo no)"
check "the ticket is released" "0" "$(ls "$TESTRUN_STATE_DIR/runs" | grep -vc '\.')"
check "only the registered database of this worktree is dropped" "1 0" "$(grep -c 'DROP DATABASE.*zeit_testing_'"$SLUG" "$TMP/psql.log") $(grep 'DROP' "$TMP/psql.log" | grep -c other_testing)"
check "another worktree's database stays in the registry" "other_testing_aaaaaaaa" "$(cat "$TESTRUN_STATE_DIR/test-dbs.list")"

[ "$FAIL" -eq 0 ] && echo "WORKTREE_CLEANUP_TEST=OK" || { echo "WORKTREE_CLEANUP_TEST=FAIL ($FAIL)"; exit 1; }
