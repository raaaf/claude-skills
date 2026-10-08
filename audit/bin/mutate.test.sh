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
check "changed-lines parses added ranges and ignores pure deletions" "app/A.php:4 app/A.php:5 app/A.php:12" \
  "$("$BASH_BIN" "$MUT" --changed-lines "$TMP/diff" | tr '\n' ' ' | sed 's/ $//')"

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
case "\$(cat "$TMP/pest-mode" 2>/dev/null)" in
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
for tool in git sed grep sort head cat tr cut basename dirname mktemp rm mkdir wc sleep env date; do
  p=$(command -v "$tool") && ln -sf "$p" "$MIN/$tool"
done
cp stubs/php-pcov "$MIN/php"
check "no timeout binary -> SKIP no-timeout" "MUTATE_RESULT=SKIP MUTATE_REASON=no-timeout" \
  "$(PATH="$MIN" "$BASH_BIN" "$MUT" "$REPO" HEAD 2>&1 | tr '\n' ' ' | sed 's/ $//')"

[ "$FAIL" -eq 0 ] && echo "MUTATE_TEST=OK" || { echo "MUTATE_TEST=FAIL ($FAIL)"; exit 1; }
