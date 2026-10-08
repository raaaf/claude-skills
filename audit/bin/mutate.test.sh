#!/usr/bin/env bash
# Pins mutate.sh: target intersection, SKIP reasons, FQCN, parsers against real Pest and Infection
# logs (fixtures/mutate/), the changed-line filter and cap, and a full Pest flow with a stub runner.
# Usage: bash audit/bin/mutate.test.sh
set -u
HERE=$(cd "$(dirname "$0")" && pwd)
MUT="$HERE/mutate.sh"
FIX="$HERE/fixtures/mutate"
BASH_BIN=$(command -v bash)
TMP=$(mktemp -d "${TMPDIR:-/tmp}/mutate-test.XXXXXX")
trap 'rm -rf "$TMP"' EXIT
FAIL=0
check() { # name expected actual
  if [ "$2" = "$3" ]; then echo "ok   $1"; else echo "FAIL $1: expected [$2] got [$3]"; FAIL=$((FAIL + 1)); fi
}
has() { # name needle haystack
  case "$3" in *"$2"*) echo "ok   $1" ;; *) echo "FAIL $1: [$2] not in [$3]"; FAIL=$((FAIL + 1)) ;; esac
}

# --- parsers against real logs ---------------------------------------------------------------
PEST=$("$BASH_BIN" "$MUT" --parse-pest "$FIX/pest-mutate-secretsanta.log" --root /nowhere)
has "pest: line 112 TrueToFalse is an UNTESTED survivor" "SURVIVOR_RAW=app/Services/SecretSantaMatchService.php:112:TrueToFalse" "$PEST"
has "pest: 46 survivors before filtering" "MUTATE_UNFILTERED=46" "$PEST"
has "pest: score line" "MUTATE_SCORE=app/Services/SecretSantaMatchService.php:71.95" "$PEST"

INF_ROOT=$(grep -m1 -o '^1) .*snap-bew' "$FIX/infection-bewirtung.txt" | cut -c4-)
INF=$("$BASH_BIN" "$MUT" --parse-infection "$FIX/infection-bewirtung.txt" --root "$INF_ROOT")
has "infection: absolute path becomes repo-relative" "SURVIVOR_RAW=app/Services/Tax/BewirtungSplit.php:36:Assignment" "$INF"
has "infection: second escaped mutant" "SURVIVOR_RAW=app/Services/Tax/BewirtungSplit.php:37:Assignment" "$INF"
has "infection: five escaped mutants" "MUTATE_UNFILTERED=5" "$INF"

# --- changed lines and the +-3 filter with cap -----------------------------------------------
printf '%s\n' '+++ b/app/A.php' '@@ -3,0 +4,2 @@' '@@ -10 +12 @@' '@@ -20,2 +21,0 @@' > "$TMP/diff"
check "changed-lines parses added ranges and anchors pure deletions" "app/A.php:4 app/A.php:5 app/A.php:12 app/A.php:21" \
  "$("$BASH_BIN" "$MUT" --changed-lines "$TMP/diff" | tr '\n' ' ' | sed 's/ $//')"

# a deletion-only hunk keeps a survivor around the gap
printf '%s\n' '+++ b/app/A.php' '@@ -20,2 +21,0 @@' > "$TMP/diff-del"
"$BASH_BIN" "$MUT" --changed-lines "$TMP/diff-del" > "$TMP/changed-del"
check "filter keeps a survivor next to a deletion-only hunk" "SURVIVOR=app/A.php:23:X " \
  "$(printf '%s\n' SURVIVOR_RAW=app/A.php:23:X SURVIVOR_RAW=app/A.php:30:Y | "$BASH_BIN" "$MUT" --filter "$TMP/changed-del" | tr '\n' ' ')"

printf '%s\n' app/A.php:10 > "$TMP/changed"
OUT=$(printf '%s\n' SURVIVOR_RAW=app/A.php:6:X SURVIVOR_RAW=app/A.php:7:Y SURVIVOR_RAW=app/A.php:13:Z SURVIVOR_RAW=app/A.php:14:W SURVIVOR_RAW=app/B.php:10:V \
  | "$BASH_BIN" "$MUT" --filter "$TMP/changed" | tr '\n' ' ')
check "filter keeps only lines within 3 of a changed line in the same file" "SURVIVOR=app/A.php:7:Y SURVIVOR=app/A.php:13:Z " "$OUT"

: > "$TMP/changed"
i=100; RAW=""
while [ "$i" -lt 120 ]; do echo "app/A.php:$i" >> "$TMP/changed"; RAW="$RAW SURVIVOR_RAW=app/A.php:$i:M"; i=$((i + 1)); done
OUT=$(printf '%s\n' $RAW | "$BASH_BIN" "$MUT" --filter "$TMP/changed")
check "cap: 15 survivors" "15" "$(printf '%s\n' "$OUT" | grep -c '^SURVIVOR=')"
has "cap: the rest is counted" "SURVIVORS_TRUNCATED=5" "$OUT"

# --- target intersection and SKIP reasons in a temp repo -------------------------------------
REPO="$TMP/repo"
mkdir -p "$REPO/app/Services" "$REPO/app/Other" "$REPO/bin" "$REPO/stubs"
cd "$REPO" || exit 1
git init -q
{ echo '<?php'; echo 'namespace App\Services;'; i=3; while [ "$i" -le 130 ]; do echo "// line $i"; i=$((i + 1)); done; } > app/Services/SecretSantaMatchService.php
cp app/Services/SecretSantaMatchService.php app/Other/Free.php
git add -A && git -c user.email=t@t -c user.name=t commit -q -m base
sed -i.bak '112s/.*/\/\/ changed 112/' app/Services/SecretSantaMatchService.php && rm -f app/Services/SecretSantaMatchService.php.bak
sed -i.bak '112s/.*/\/\/ changed 112/' app/Other/Free.php && rm -f app/Other/Free.php.bak

printf '#!/bin/sh\nprintf "[PHP Modules]\\nCore\\n"\n' > stubs/php-nodriver
printf '#!/bin/sh\nprintf "[PHP Modules]\\nCore\\npcov\\n"\n' > stubs/php-pcov
chmod +x stubs/php-nodriver stubs/php-pcov
use_php() { mkdir -p bin; cp "stubs/$1" bin/php; }
run() { PATH="$REPO/bin:$PATH" "$BASH_BIN" "$MUT" "$REPO" HEAD "$@" 2>&1; }

use_php php-pcov
check "targets file absent -> SKIP no-targets" "MUTATE_RESULT=SKIP MUTATE_REASON=no-targets" "$(run | tr '\n' ' ' | sed 's/ $//')"

mkdir -p .claude
printf '# nothing here\napp/Nothing/*.php\n' > "$TMP/targets-nomatch"
printf '# only services\napp/Services/*.php\n' > "$TMP/targets-match"

cp "$TMP/targets-nomatch" .claude/mutation-targets
check "changed file outside every glob -> SKIP no-match" "MUTATE_RESULT=SKIP MUTATE_REASON=no-match" "$(run | tr '\n' ' ' | sed 's/ $//')"

cp "$TMP/targets-match" .claude/mutation-targets
use_php php-nodriver
check "match but no pcov/xdebug -> SKIP no-coverage" "MUTATE_RESULT=SKIP MUTATE_REASON=no-coverage" "$(run | tr '\n' ' ' | sed 's/ $//')"

use_php php-pcov
printf '{"require-dev": {"pestphp/pest": "^3"}}\n' > composer.json
mkdir -p vendor/bin
cat > vendor/bin/pest <<EOF
#!/bin/sh
echo "\$@" > "$TMP/pest-args"
echo run >> "$TMP/pest-runs"
case "\$(cat "$TMP/pest-mode" 2>/dev/null)" in
  stdin) cat >/dev/null ;;
  fail) echo "  Pest\\Browser\\Exceptions\\PlaywrightNotInstalledException"; exit 1 ;;
  nomut) echo "  INFO  No mutations created."; exit 0 ;;
esac
cat "$FIX/pest-mutate-secretsanta.log"
EOF
chmod +x vendor/bin/pest
check "pest runner but no test file mentions the class -> SKIP no-tests" "MUTATE_RESULT=SKIP MUTATE_REASON=no-tests" "$(run | tr '\n' ' ' | sed 's/ $//')"

mkdir -p tests/Unit
printf '<?php\n// covers SecretSantaMatchService\n' > tests/Unit/SecretSantaMatchServiceTest.php

if command -v timeout >/dev/null 2>&1 || command -v gtimeout >/dev/null 2>&1; then
  OUT=$(run)
  has "full flow: result OK" "MUTATE_RESULT=OK" "$OUT"
  has "full flow: survivor on a changed line" "SURVIVOR=app/Services/SecretSantaMatchService.php:112:TrueToFalse" "$OUT"
  has "full flow: score reported" "MUTATE_SCORE=app/Services/SecretSantaMatchService.php:71.95" "$OUT"
  check "full flow: no survivor far from the changed line" "0" "$(printf '%s\n' "$OUT" | grep -c ':63:')"
  has "FQCN is namespace plus basename, test file found by class name" \
    '--mutate --covered-only --class=App\Services\SecretSantaMatchService tests/Unit/SecretSantaMatchServiceTest.php' "$(cat "$TMP/pest-args")"
  # oracle files join the test list even when they never mention the class
  printf '<?php\n' > tests/Unit/OracleTest.php
  run --oracle-files tests/Unit/OracleTest.php >/dev/null
  has "oracle files are passed to the runner" "tests/Unit/OracleTest.php" "$(cat "$TMP/pest-args")"
  # Browser suites need Playwright and are far too slow for mutation: never passed to the runner
  mkdir -p tests/Browser/Event
  printf '<?php\n// SecretSantaMatchService in a browser test\n' > tests/Browser/Event/SantaCardTest.php
  run >/dev/null
  check "a Browser/ test file is not passed to the runner" "0" "$(grep -c 'Browser' "$TMP/pest-args")"
  rm -rf tests/Browser
  # a test named after the class wins over files that merely mention it (DB-backed Feature tests blow the budget)
  mkdir -p tests/Feature
  printf '<?php\n// SecretSantaMatchService\n' > tests/Feature/GrepOnlyTest.php
  OUT=$(run)
  check "a grep-only file is not passed when a test is named after the class" "0" "$(grep -c 'GrepOnly' "$TMP/pest-args")"
  check "no fallback note when the name match exists" "0" "$(printf '%s\n' "$OUT" | grep -c 'MUTATE_NOTE')"
  # no test is named after the class: fall back to grep hits, Unit first, capped at 5, with a note
  mv tests/Unit/SecretSantaMatchServiceTest.php "$TMP/named-test"
  rm tests/Unit/OracleTest.php
  for n in 1 2 3 4; do printf '<?php\n// SecretSantaMatchService\n' > "tests/Feature/F${n}Test.php"; printf '<?php\n// SecretSantaMatchService\n' > "tests/Unit/U${n}Test.php"; done
  OUT=$(run)
  ARGS=$(cat "$TMP/pest-args")
  check "fallback passes at most 5 test files" "5" "$(printf '%s\n' "$ARGS" | tr ' ' '\n' | grep -c 'tests/')"
  check "fallback prefers tests/Unit" "4" "$(printf '%s\n' "$ARGS" | tr ' ' '\n' | grep -c 'tests/Unit/')"
  has "fallback prints a note" "MUTATE_NOTE=fallback-test-selection:5" "$OUT"
  rm -f tests/Feature/*Test.php tests/Unit/U*Test.php
  mv "$TMP/named-test" tests/Unit/SecretSantaMatchServiceTest.php
  # two matched files; a runner that reads stdin must not swallow the second file
  cp app/Services/SecretSantaMatchService.php app/Services/Second.php
  git add app/Services/Second.php && git -c user.email=t@t -c user.name=t commit -q -m second
  sed -i.bak '50s/.*/\/\/ changed 50/' app/Services/Second.php && rm -f app/Services/Second.php.bak
  printf '<?php\n' > tests/Unit/SecondTest.php
  echo stdin > "$TMP/pest-mode"; rm -f "$TMP/pest-runs"
  run >/dev/null
  check "a stdin-reading runner does not swallow the next file" "2" "$(wc -l < "$TMP/pest-runs" | tr -d ' ')"
  # budget gone before the 2nd file (slow git diff after the 1st run): TIMEOUT, no stale log parsed
  rm -f "$TMP/pest-mode"
  mkdir -p slowbin
  REALGIT=$(command -v git)
  printf '#!/bin/sh\n[ "$1" = diff ] && [ "$2" = -U0 ] && sleep 3\nexec %s "$@"\n' "$REALGIT" > slowbin/git
  chmod +x slowbin/git
  OUT=$(PATH="$REPO/slowbin:$REPO/bin:$PATH" MUTATE_BUDGET=2 "$BASH_BIN" "$MUT" "$REPO" HEAD 2>&1)
  has "exhausted budget -> TIMEOUT" "MUTATE_RESULT=TIMEOUT" "$OUT"
  check "exhausted budget: 2nd file not parsed from the stale log" "1" "$(printf '%s\n' "$OUT" | grep -c '^MUTATE_SCORE=')"
  rm -rf slowbin tests/Unit/SecondTest.php
  git rm -q -f app/Services/Second.php && git -c user.email=t@t -c user.name=t commit -q -m rmsecond
  # a runner that dies without a summary is ERROR, not OK
  echo fail > "$TMP/pest-mode"
  OUT=$(run)
  has "runner failure -> ERROR" "MUTATE_RESULT=ERROR" "$OUT"
  has "runner failure -> reason" "MUTATE_REASON=runner-failed" "$OUT"
  has "runner failure -> first exception line" "MUTATE_ERROR=Pest\\Browser\\Exceptions\\PlaywrightNotInstalledException" "$OUT"
  # Pest resolved the class elsewhere (symlinked vendor/): nothing was tested
  echo nomut > "$TMP/pest-mode"
  check "No mutations created -> SKIP no-mutations" "MUTATE_RESULT=SKIP MUTATE_REASON=no-mutations" "$(run | tr '\n' ' ' | sed 's/ $//')"
  rm -f "$TMP/pest-mode"
else
  echo "skip full-flow tests: neither timeout nor gtimeout installed"
fi

# --- neither timeout nor gtimeout: SKIP, never an unbounded run ------------------------------
MIN="$TMP/minbin"
mkdir -p "$MIN"
for tool in git find awk sed grep sort head cat tr cut basename dirname mktemp rm mkdir wc sleep env date; do
  p=$(command -v "$tool") && ln -sf "$p" "$MIN/$tool"
done
cp stubs/php-pcov "$MIN/php"
check "no timeout binary -> SKIP no-timeout" "MUTATE_RESULT=SKIP MUTATE_REASON=no-timeout" \
  "$(PATH="$MIN" "$BASH_BIN" "$MUT" "$REPO" HEAD 2>&1 | tr '\n' ' ' | sed 's/ $//')"

[ "$FAIL" -eq 0 ] && echo "MUTATE_TEST=OK" || { echo "MUTATE_TEST=FAIL ($FAIL)"; exit 1; }
