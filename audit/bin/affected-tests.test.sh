#!/usr/bin/env bash
# Pins affected-tests.sh: which diff runs which tests, and when it falls back to the full suite.
# Usage: bash audit/bin/affected-tests.test.sh
set -u
HERE=$(cd "$(dirname "$0")" && pwd)
AT="$HERE/affected-tests.sh"
TMP=$(mktemp -d "${TMPDIR:-/tmp}/affected-tests-test.XXXXXX"); trap 'rm -rf "$TMP"' EXIT
FAIL=0
check() { if [ "$2" = "$3" ]; then echo "ok   $1"; else echo "FAIL $1: expected [$2] got [$3]"; FAIL=$((FAIL + 1)); fi; }
val() { printf '%s\n' "$1" | sed -n "s/^$2=//p"; }

# repo <name>: fresh git repo with one commit, prints its path
repo() {
  local r="$TMP/$1"; mkdir -p "$r"; git -C "$r" init -q
  git -C "$r" -c user.email=t@t -c user.name=t commit -q --allow-empty -m init
  printf '%s' "$r"
}
commit() { git -C "$1" add -A && git -C "$1" -c user.email=t@t -c user.name=t commit -q -m c; }
w() { mkdir -p "$(dirname "$1")"; printf '%s\n' "${2:-x}" > "$1"; }

# bun backend in a subdir, env assignment kept, ./ prefix for bun file paths
R=$(repo bun)
w "$R/backend/package.json" '{}'; w "$R/backend/src/recipes.ts"; w "$R/backend/tests/recipes.test.ts"; w "$R/backend/tests/other.test.ts"
commit "$R"; BASE=$(git -C "$R" rev-parse HEAD)
w "$R/backend/src/recipes.ts" changed
OUT=$(bash "$AT" "$R" "$BASE" "cd backend && CASA_DB_PATH=:memory: bun test")
check "bun: source maps to its test" "run" "$(val "$OUT" AFFECTED)"
check "bun: command keeps cd and env" "cd 'backend' && CASA_DB_PATH=:memory: bun test './tests/recipes.test.ts'" "$(val "$OUT" AFFECTED_CMD)"
w "$R/backend/src/nomatch.ts"
w "$R/backend/tests/other.test.ts" changed
OUT=$(bash "$AT" "$R" "$BASE" "cd backend && bun test")
check "bun: changed test file runs too, unmatched source adds nothing" "2" "$(val "$OUT" AFFECTED_FILES)"
w "$R/backend/tests/helpers.ts"
OUT=$(bash "$AT" "$R" "$BASE" "cd backend && bun test")
check "test helper change falls back to full" "full" "$(val "$OUT" AFFECTED)"

# script resolution: `bun run test` -> package.json script body
R=$(repo script)
w "$R/backend/package.json" '{"scripts":{"test":"SV_DB_PATH=:memory: ANTHROPIC_API_KEY= bun test"}}'
w "$R/backend/src/a.ts"; w "$R/backend/src/a.test.ts"; commit "$R"; BASE=$(git -C "$R" rev-parse HEAD)
w "$R/backend/src/a.ts" changed
OUT=$(bash "$AT" "$R" "$BASE" "cd backend && bun run typecheck && bun run test")
check "script: typecheck dropped, script env kept" "cd 'backend' && SV_DB_PATH=:memory: ANTHROPIC_API_KEY= bun test './src/a.test.ts'" "$(val "$OUT" AFFECTED_CMD)"

# vitest via npm test
R=$(repo vitest)
w "$R/package.json" '{"scripts":{"test":"vitest run"}}'
w "$R/src/x.js"; w "$R/test/x.test.js"; commit "$R"; BASE=$(git -C "$R" rev-parse HEAD)
w "$R/src/x.js" changed
OUT=$(bash "$AT" "$R" "$BASE" "npm test")
check "vitest: npx vitest run <file>" "npx vitest run 'test/x.test.js'" "$(val "$OUT" AFFECTED_CMD)"
w "$R/README.md" docs
w "$R/src/x.js" x
OUT=$(bash "$AT" "$R" "$BASE" "npm test")
check "prose-only diff runs nothing" "none" "$(val "$OUT" AFFECTED)"
w "$R/package.json" '{"scripts":{"test":"vitest run"},"x":1}'
OUT=$(bash "$AT" "$R" "$BASE" "npm test")
check "package.json change falls back to full" "full" "$(val "$OUT" AFFECTED)"

# Laravel + Pest; migration -> full; untracked new test counts
R=$(repo php)
w "$R/artisan"; mkdir -p "$R/vendor/bin"; printf '#!/bin/sh\n' > "$R/vendor/bin/pest"; chmod +x "$R/vendor/bin/pest"
printf 'vendor/\n' > "$R/.gitignore"
w "$R/app/Models/Recipe.php"; w "$R/tests/Unit/RecipeTest.php"; commit "$R"; BASE=$(git -C "$R" rev-parse HEAD)
w "$R/app/Models/Recipe.php" changed; w "$R/tests/Feature/NewTest.php"
OUT=$(bash "$AT" "$R" "$BASE" "deploy events test")
check "pest: mapped + untracked test, config:clear first" "php artisan config:clear --ansi >/dev/null && php artisan test 'tests/Feature/NewTest.php' 'tests/Unit/RecipeTest.php'" "$(val "$OUT" AFFECTED_CMD)"
w "$R/database/migrations/2026_01_01_x.php"
OUT=$(bash "$AT" "$R" "$BASE" "composer test")
check "migration falls back to full" "full" "$(val "$OUT" AFFECTED)"

# PHPUnit via artisan: one call per file
R=$(repo phpunit)
w "$R/artisan"; w "$R/app/A.php"; w "$R/tests/Unit/ATest.php"; w "$R/tests/Unit/BTest.php"; commit "$R"; BASE=$(git -C "$R" rev-parse HEAD)
w "$R/app/A.php" changed; w "$R/tests/Unit/BTest.php" changed
OUT=$(bash "$AT" "$R" "$BASE" "composer test")
check "phpunit: chained per file" "php artisan config:clear --ansi >/dev/null && php artisan test 'tests/Unit/ATest.php' && php artisan test 'tests/Unit/BTest.php'" "$(val "$OUT" AFFECTED_CMD)"

# unsupported runner and cap
OUT=$(bash "$AT" "$R" "$BASE" "swift test")
check "swift falls back to full" "full" "$(val "$OUT" AFFECTED)"
R=$(repo cap)
w "$R/package.json" '{"scripts":{"test":"bun test"}}'; commit "$R"; BASE=$(git -C "$R" rev-parse HEAD)
for i in 1 2 3; do w "$R/t$i.test.ts"; done
OUT=$(AFFECTED_CAP=2 bash "$AT" "$R" "$BASE" "bun test")
check "over the cap falls back to full" "full" "$(val "$OUT" AFFECTED)"
OUT=$(bash "$AT" "$R" "" "bun test")
check "no base ref falls back to full" "full" "$(val "$OUT" AFFECTED)"

[ "$FAIL" -eq 0 ] && echo "AFFECTED_TESTS_TEST=OK" || { echo "AFFECTED_TESTS_TEST=FAIL ($FAIL)"; exit 1; }
