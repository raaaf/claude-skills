#!/usr/bin/env bash
# affected-tests.sh: turns a diff into the test run /audit needs, so the full suite runs only in /ship
# and `deploy <app> test` (decided 2026-11-07: full suites blocked parallel sessions on every push).
#
# Usage: affected-tests.sh <root> <base_ref> <test_command>
#   The changed files are `git diff --name-only <base_ref>` plus untracked files, i.e. the audit scope
#   including whatever the Phase 4 fix executor added.
# Prints exactly one of:
#   AFFECTED=run   + AFFECTED_FILES=<n> + AFFECTED_CMD=<command string, run it via test-lock.sh --cmd>
#   AFFECTED=none  + AFFECTED_REASON=<why>   (code changed, no test belongs to it: nothing to run)
#   AFFECTED=full  + AFFECTED_REASON=<why>   (run the declared full suite, as before)
# Fails open to `full`: an unknown runner, a config/lockfile/test-helper/migration change, or more than
# AFFECTED_CAP (default 25) test files all fall back to the full suite.
#
# A test belongs to a change when the test file itself changed, or when its name is derived from the
# changed source file's basename: foo.ts -> foo.test.ts / foo.spec.ts, Foo.php -> FooTest.php,
# foo.py -> test_foo.py / foo_test.py. Name mapping is deliberately simple; the full suite in /ship
# catches what it misses.
# Runners: bun test, vitest, jest, node --test, Pest / artisan (Pest), artisan on PHPUnit (one call per
# file, at most 5), pytest. `cd <dir> && ...` prefixes and env assignments in the command are kept.
# bash 3.2 compatible.
set -u

ROOT=${1:?root}; BASE=${2:-}; CMD=${3:-}
CAP=${AFFECTED_CAP:-25}

full() { echo "AFFECTED=full"; echo "AFFECTED_REASON=$1"; exit 0; }
none() { echo "AFFECTED=none"; echo "AFFECTED_REASON=$1"; exit 0; }

[ -n "$CMD" ] || full "no test command"
[ -n "$BASE" ] || full "no base ref"
cd "$ROOT" 2>/dev/null || full "root not found"

# --- test command: subdir, runner -----------------------------------------------------------------
SUBDIR=""; REST=$CMD
case "$CMD" in
  "cd "*" && "*) SUBDIR=${CMD#cd }; SUBDIR=${SUBDIR%% && *}; REST=${CMD#cd "$SUBDIR" && } ;;
esac
SUBDIR=${SUBDIR%/}
case "$SUBDIR" in *" "*|*";"*|*"|"*) full "unparsable cd prefix" ;; esac
D=$ROOT; [ -n "$SUBDIR" ] && D="$ROOT/$SUBDIR"
[ -d "$D" ] || full "test dir $SUBDIR not found"

# A package-manager script (`npm test`, `bun run test`, ...) is resolved to the script body.
SEGMENT=""
pick_segment() { # <command string> <needle>: the last &&-segment containing needle
  printf '%s\n' "$1" | sed 's/ && /\
/g' | grep -F -- "$2" | tail -1
}
RUNNER=""
for r in "bun test" "vitest" "jest" "node --test" "pytest"; do
  s=$(pick_segment "$REST" "$r"); [ -n "$s" ] && { RUNNER=$r; SEGMENT=$s; break; }
done
if [ -z "$RUNNER" ]; then
  case " $REST " in
    *" npm test"*|*" npm run test"*|*" bun run test"*|*" pnpm test"*|*" pnpm run test"*|*" yarn test"*)
      SCRIPT=$(jq -r '.scripts.test // empty' "$D/package.json" 2>/dev/null)
      for r in "bun test" "vitest" "jest" "node --test"; do
        s=$(pick_segment "$SCRIPT" "$r"); [ -n "$s" ] && { RUNNER=$r; SEGMENT=$s; break; }
      done ;;
  esac
fi
if [ -z "$RUNNER" ]; then
  case " $REST " in
    *" artisan test"*|*" composer test"*|*"pest"*|*"phpunit"*|*"deploy "*" test"*)
      if [ -f "$D/artisan" ] && [ -x "$D/vendor/bin/pest" ]; then RUNNER=artisan-pest
      elif [ -f "$D/artisan" ]; then RUNNER=artisan-phpunit
      elif [ -x "$D/vendor/bin/pest" ]; then RUNNER=pest
      fi ;;
  esac
fi
[ -n "$RUNNER" ] || full "runner not supported for affected runs"

# --- changed files, relative to the test dir ------------------------------------------------------
CHANGED=$( { git diff --name-only "$BASE" -- 2>/dev/null; git ls-files --others --exclude-standard 2>/dev/null; } | sed '/^$/d' | sort -u)
[ -n "$CHANGED" ] || none "empty diff"
if [ -n "$SUBDIR" ]; then
  CHANGED=$(printf '%s\n' "$CHANGED" | sed -n "s#^$SUBDIR/##p")
  [ -n "$CHANGED" ] || none "no change under $SUBDIR"
fi

TEST_RE='(\.(test|spec)\.(ts|tsx|js|jsx|mjs|cjs)$|Test\.php$|(^|/)test_[^/]*\.py$|_test\.py$)'
CONFIG_RE='(^|/)(package\.json|package-lock\.json|bun\.lockb?|pnpm-lock\.yaml|yarn\.lock|composer\.(json|lock)|phpunit\.xml(\.dist)?|bunfig\.toml|tsconfig[^/]*\.json|(vitest|vite|jest)\.config\.[a-z]+|pytest\.ini|conftest\.py|pyproject\.toml|\.env\.testing)$'
CODE_RE='\.(ts|tsx|js|jsx|mjs|cjs|php|py)$'

hit=$(printf '%s\n' "$CHANGED" | grep -E "$CONFIG_RE" | head -1)
[ -n "$hit" ] && full "config changed: $hit"
hit=$(printf '%s\n' "$CHANGED" | grep -E '^database/(migrations|factories|seeders)/' | head -1)
[ -n "$hit" ] && full "schema/factory changed: $hit"
# A non-test code file inside a test dir is a helper, fixture or setup that many tests load.
hit=$(printf '%s\n' "$CHANGED" | grep -E '(^|/)(tests?|__tests__|spec)/' | grep -E "$CODE_RE" | grep -Ev "$TEST_RE" | head -1)
[ -n "$hit" ] && full "test helper changed: $hit"

ALL_TESTS=$(cd "$D" && git ls-files --cached --others --exclude-standard 2>/dev/null | grep -E "$TEST_RE")
SELECTED=""
add() { [ -f "$D/$1" ] && SELECTED="$SELECTED
$1"; }
while IFS= read -r f; do
  [ -n "$f" ] || continue
  if printf '%s' "$f" | grep -Eq "$TEST_RE"; then add "$f"; continue; fi
  printf '%s' "$f" | grep -Eq "$CODE_RE" || continue
  case "$f" in *.blade.php) continue ;; esac
  b=${f##*/}; b=${b%.*}
  [ -n "$b" ] || continue
  m=$(printf '%s\n' "$ALL_TESTS" | awk -v b="$b" '{ n=$0; sub(/.*\//, "", n);
      if (index(n, b ".test.") == 1 || index(n, b ".spec.") == 1 || n == b "Test.php" || n == "test_" b ".py" || n == b "_test.py") print }')
  while IFS= read -r t; do [ -n "$t" ] && add "$t"; done <<EOF
$m
EOF
done <<EOF
$CHANGED
EOF
SELECTED=$(printf '%s\n' "$SELECTED" | sed '/^$/d' | sort -u)
[ -n "$SELECTED" ] || none "no test belongs to the changed files"
N=$(printf '%s\n' "$SELECTED" | grep -c .)
[ "$N" -le "$CAP" ] || full "$N affected test files (cap $CAP)"

# --- command -----------------------------------------------------------------------------------
q() { printf "'%s'" "$(printf '%s' "$1" | sed "s/'/'\\\\''/g")"; }
FILES=""
while IFS= read -r t; do
  case "$RUNNER" in "bun test") t="./$t" ;; esac
  FILES="$FILES $(q "$t")"
done <<EOF
$SELECTED
EOF
# keep env assignments and the runner word, drop the script's own trailing arguments
head_of() { printf '%s' "${SEGMENT%%"$1"*}$1"; }
case "$RUNNER" in
  "bun test")      RUN="$(head_of "bun test")$FILES" ;;
  vitest)          h=$(head_of vitest); case "$h" in *npx\ vitest|*bunx\ vitest) ;; vitest|*" vitest") h="${h%vitest}npx vitest" ;; esac; RUN="$h run$FILES" ;;
  jest)            h=$(head_of jest);   case "$h" in *npx\ jest|*bunx\ jest) ;; jest|*" jest") h="${h%jest}npx jest" ;; esac; RUN="$h$FILES" ;;
  "node --test")   RUN="$(head_of "node --test")$FILES" ;;
  pytest)          RUN="$(head_of pytest)$FILES" ;;
  pest)            RUN="vendor/bin/pest$FILES" ;;
  artisan-pest)    RUN="php artisan config:clear --ansi >/dev/null && php artisan test$FILES" ;;
  artisan-phpunit)
    [ "$N" -le 5 ] || full "$N affected test files for PHPUnit (cap 5)"
    RUN="php artisan config:clear --ansi >/dev/null"
    while IFS= read -r t; do RUN="$RUN && php artisan test $(q "$t")"; done <<EOF
$SELECTED
EOF
    ;;
esac
RUN=$(printf '%s' "$RUN" | sed 's/^ *//')
[ -n "$SUBDIR" ] && RUN="cd $(q "$SUBDIR") && $RUN"
echo "AFFECTED=run"
echo "AFFECTED_FILES=$N"
echo "AFFECTED_CMD=$RUN"
