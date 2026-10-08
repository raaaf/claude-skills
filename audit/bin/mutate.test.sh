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
  js) echo "!function(){new MutationObserver(function(){});var Mutations: 5;}()"; exit 1 ;;
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
  # --files: an unchanged target is measured, survivors far from any diff line are kept; a non-target gets a note
  mkdir -p app/Unchanged
  printf '<?php\nnamespace App\\Unchanged;\n' > app/Unchanged/Unc.php
  printf '<?php\n' > tests/Unit/UncTest.php
  git add app/Unchanged/Unc.php && git -c user.email=t@t -c user.name=t commit -q -m unc -- app/Unchanged/Unc.php
  printf 'app/Unchanged/*.php\n' > .claude/mutation-targets
  check "without --files an unchanged target gives SKIP no-match" "MUTATE_RESULT=SKIP MUTATE_REASON=no-match" "$(run | tr '\n' ' ' | sed 's/ $//')"
  OUT=$(run --files app/Unchanged/Unc.php)
  has "--files measures an unchanged target" "MUTATE_RESULT=OK" "$OUT"
  has "--files keeps a survivor far from every changed line" "SURVIVOR=app/Services/SecretSantaMatchService.php:63:RemoveEarlyReturn" "$OUT"
  has "--files runs the tests of that file" "tests/Unit/UncTest.php" "$(cat "$TMP/pest-args")"
  check "--files on a target prints no not-a-target note" "0" "$(printf '%s\n' "$OUT" | grep -c 'not-a-target')"
  printf 'app/Services/*.php\n' > .claude/mutation-targets
  OUT=$(run --files app/Unchanged/Unc.php)
  has "--files on a non-target is measured with a note" "MUTATE_NOTE=not-a-target:app/Unchanged/Unc.php" "$OUT"
  has "--files on a non-target still runs" "MUTATE_RESULT=OK" "$OUT"
  # entries are normalized: ./relative and absolute paths match like the plain relative one
  OUT=$(run --files ./app/Unchanged/Unc.php)
  has "--files accepts a ./relative path" "MUTATE_NOTE=not-a-target:app/Unchanged/Unc.php" "$OUT"
  OUT=$(run --files "$(pwd -P)/app/Unchanged/Unc.php")
  has "--files accepts an absolute path" "MUTATE_NOTE=not-a-target:app/Unchanged/Unc.php" "$OUT"
  # without a targets file --files still measures (all non-targets); without --files it stays SKIP no-targets
  mv .claude/mutation-targets "$TMP/targets-bak"
  OUT=$(run --files app/Unchanged/Unc.php)
  has "--files without a targets file is measured" "MUTATE_RESULT=OK" "$OUT"
  check "no targets file and no --files stays SKIP no-targets" "MUTATE_RESULT=SKIP MUTATE_REASON=no-targets" "$(run | tr '\n' ' ' | sed 's/ $//')"
  mv "$TMP/targets-bak" .claude/mutation-targets
  # the not-a-target note belongs to a file that produced a result: a no-tests SKIP carries none
  mv tests/Unit/UncTest.php "$TMP/unc-test-bak"
  OUT=$(run --files app/Unchanged/Unc.php)
  has "--files non-target without tests is SKIP no-tests" "MUTATE_REASON=no-tests" "$OUT"
  check "no not-a-target note when the file produced no result" "0" "$(printf '%s\n' "$OUT" | grep -c 'not-a-target')"
  mv "$TMP/unc-test-bak" tests/Unit/UncTest.php
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
  # a failing test dumps JS containing `Mutations:` mid-line: that is no runner summary
  echo js > "$TMP/pest-mode"
  OUT=$(run)
  has "mid-line Mutations: text is no summary -> ERROR" "MUTATE_RESULT=ERROR" "$OUT"
  rm -f "$TMP/pest-mode"
  # Pest resolved the class elsewhere (symlinked vendor/): nothing was tested
  echo nomut > "$TMP/pest-mode"
  check "No mutations created -> SKIP no-mutations" "MUTATE_RESULT=SKIP MUTATE_REASON=no-mutations" "$(run | tr '\n' ' ' | sed 's/ $//')"
  rm -f "$TMP/pest-mode"
  # per-target hint (`glob :: Name|Name`): the named test classes replace name and grep discovery
  mkdir -p tests/Feature
  printf '<?php\n' > tests/Feature/IndirectTest.php
  printf 'app/Services/*.php :: IndirectTest|GhostTest # indirect\n' > .claude/mutation-targets
  OUT=$(run)
  ARGS=$(cat "$TMP/pest-args")
  has "hint files used instead of grep hits" "tests/Feature/IndirectTest.php" "$ARGS"
  check "hint replaces the class-name match" "0" "$(printf '%s\n' "$ARGS" | grep -c 'SecretSantaMatchServiceTest')"
  has "hint-missing note" "MUTATE_NOTE=hint-missing:GhostTest" "$OUT"
  # the `::` separator tolerates any surrounding whitespace
  for sep in ' ::' ':: ' '::'; do
    printf 'app/Services/*.php%sIndirectTest\n' "$sep" > .claude/mutation-targets
    rm -f "$TMP/pest-args"
    run >/dev/null
    ARGS=$(cat "$TMP/pest-args")
    has "hint separator [$sep] uses the hint" "tests/Feature/IndirectTest.php" "$ARGS"
    check "hint separator [$sep] replaces the class-name match" "0" "$(printf '%s\n' "$ARGS" | grep -c 'SecretSantaMatchServiceTest')"
  done
  printf 'app/Services/*.php :: GhostTest\n' > .claude/mutation-targets
  has "hint without any file -> SKIP no-tests" "MUTATE_RESULT=SKIP MUTATE_REASON=no-tests" "$(run | tr '\n' ' ')"
  # Infection gets the selected tests as a PHPUnit filter, not the whole suite
  printf 'app/Services/*.php :: IndirectTest|SecretSantaMatchServiceTest\n' > .claude/mutation-targets
  printf '#!/bin/sh\n[ "$1" = "-m" ] && { printf "[PHP Modules]\\nCore\\npcov\\n"; exit 0; }\nexec sh "$@"\n' > bin/php
  chmod +x bin/php
  printf '#!/bin/sh\nprintf "%%s\\n" "$@" > "%s/inf-args"\necho "Mutation Score Indicator (MSI): 80%%"\n' "$TMP" > "$TMP/infection.phar"
  : > phpunit.xml
  mv vendor/bin/pest "$TMP/pest-off"
  OUT=$(INFECTION_PHAR="$TMP/infection.phar" run)
  # one argv element carries filter and PHPUnit's --order-by; Infection itself has no --order-by option
  has "infection: filter and order-by arrive as one --test-framework-options argument" \
    "--test-framework-options=--filter=IndirectTest|SecretSantaMatchServiceTest --order-by=default" "$(cat "$TMP/inf-args")"
  check "infection: no standalone --order-by argument" "0" "$(grep -c '^--order-by' "$TMP/inf-args")"
  has "infection: score reported" "MUTATE_SCORE=app/Services/SecretSantaMatchService.php:80" "$OUT"
  # Infection refuses to start when the suite is red: ERROR initial-tests-failed naming the failing file
  printf '#!/bin/sh\necho "  [ERROR] Project tests must be in a passing state before running Infection."\necho "1) Tests\\Feature\\Tax\\MissingReceiptServiceTest::test_x"\necho "   tests/Feature/Tax/MissingReceiptServiceTest.php:88  "\nexit 1\n' > "$TMP/infection-red.phar"
  OUT=$(INFECTION_PHAR="$TMP/infection-red.phar" run)
  has "infection red suite: ERROR" "MUTATE_RESULT=ERROR" "$OUT"
  has "infection red suite: reason" "MUTATE_REASON=initial-tests-failed" "$OUT"
  has "infection red suite: names the failing test file" "MUTATE_ERROR=tests/Feature/Tax/MissingReceiptServiceTest.php:88" "$OUT"
  # every generated mutant exceeded the per-mutant timeout: nothing was tested, never OK
  cat > "$TMP/infection-skipped.phar" <<'STUB'
#!/bin/sh
echo "27 mutations were generated:"
echo "       0 mutants were killed by Test Framework"
echo "      27 mutants required more time than configured"
echo "Metrics:"
echo "         Mutation Code Coverage: 0%"
echo "         Covered Code MSI: 0%"
STUB
  OUT=$(INFECTION_PHAR="$TMP/infection-skipped.phar" run | tr '\n' ' ')
  has "all mutants skipped -> SKIP all-mutants-skipped" "MUTATE_RESULT=SKIP MUTATE_REASON=all-mutants-skipped" "$OUT"
  has "all mutants skipped -> note" "MUTATE_NOTE=skipped-mutants:app/Services/SecretSantaMatchService.php:27" "$OUT"
  # a normal run reports only Covered Code MSI; the escaped mutant comes from the text log; config carries the timeout
  cat > "$TMP/infection-ok.phar" <<'STUB'
#!/bin/sh
cfg=${1#--configuration=}
cp "$cfg" "$INF_CFG_COPY"
printf 'Escaped mutants:\n===\n\n1) %s/app/Services/SecretSantaMatchService.php:112    [M] TrueToFalse [ID] abc\n' "$(pwd -P)" > "$(dirname "$cfg")/infection-text.log"
echo "27 mutations were generated:"
echo "      22 mutants were killed by Test Framework"
echo "       5 mutants were not covered by tests"
echo "         Covered Code MSI: 81%"
STUB
  OUT=$(INF_CFG_COPY="$TMP/inf-config" INFECTION_PHAR="$TMP/infection-ok.phar" run)
  has "infection normal run: OK" "MUTATE_RESULT=OK" "$OUT"
  has "infection normal run: Covered Code MSI is the score" "MUTATE_SCORE=app/Services/SecretSantaMatchService.php:81" "$OUT"
  has "infection normal run: escaped mutant is a survivor" "SURVIVOR=app/Services/SecretSantaMatchService.php:112:TrueToFalse" "$OUT"
  has "infection config: default per-mutant timeout" '"timeout": 120,' "$(cat "$TMP/inf-config")"
  INF_CFG_COPY="$TMP/inf-config" MUTATE_INFECTION_TIMEOUT=400 INFECTION_PHAR="$TMP/infection-ok.phar" run >/dev/null
  has "infection config: timeout override via MUTATE_INFECTION_TIMEOUT" '"timeout": 400,' "$(cat "$TMP/inf-config")"
  OUT=$(INF_CFG_COPY="$TMP/inf-config" MUTATE_INFECTION_TIMEOUT=2m INFECTION_PHAR="$TMP/infection-ok.phar" run)
  has "infection config: invalid timeout falls back to 120" '"timeout": 120,' "$(cat "$TMP/inf-config")"
  has "invalid timeout prints a note" "MUTATE_NOTE=invalid-infection-timeout:2m" "$OUT"
  # both summary lines present: the covered-code figure wins whatever the order
  cat > "$TMP/infection-both.phar" <<'STUB'
#!/bin/sh
echo "         Mutation Score Indicator (MSI): 40%"
echo "         Covered Code MSI: 81%"
STUB
  OUT=$(INFECTION_PHAR="$TMP/infection-both.phar" run)
  has "infection: Covered Code MSI preferred over MSI" "MUTATE_SCORE=app/Services/SecretSantaMatchService.php:81" "$OUT"
  mv "$TMP/pest-off" vendor/bin/pest
  rm -f phpunit.xml
  cp "$TMP/targets-match" .claude/mutation-targets
  use_php php-pcov
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
