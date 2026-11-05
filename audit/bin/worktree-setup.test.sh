#!/usr/bin/env bash
# Pins worktree-setup.sh with fake composer/npm/bun that only log their calls. Temp dirs only.
# Usage: bash audit/bin/worktree-setup.test.sh
set -u
HERE=$(cd "$(dirname "$0")" && pwd)
SETUP="$HERE/worktree-setup.sh"
TMP=$(cd "$(mktemp -d "${TMPDIR:-/tmp}/wt-setup-test.XXXXXX")" && pwd -P)
trap 'rm -rf "$TMP"' EXIT
FAIL=0
check() { if [ "$2" = "$3" ]; then echo "ok   $1"; else echo "FAIL $1: expected [$2] got [$3]"; FAIL=$((FAIL + 1)); fi; }

for t in composer npm bun; do
  cat > "$TMP/fake-$t" <<EOF
#!/bin/bash
echo "$t \$*" >> "$TMP/calls.log"
[ -n "\${FAKE_FAIL:-}" ] && [ "\$FAKE_FAIL" = "$t" ] && { echo "boom from $t"; exit 1; }
if [ "$t" = npm ] && [ "\$1" = run ]; then mkdir -p public/build && echo '{}' > public/build/manifest.json; fi
if [ "$t" = npm ] && [ "\$1" = ls ] && [ -n "\${FAKE_NPM_LS_FAIL:-}" ]; then exit 1; fi
if [ "$t" = npm ] && [ "\$1" = ci ]; then mkdir -p node_modules; fi
if [ "$t" = composer ] && [ "\$1" = install ]; then mkdir -p vendor && : > vendor/autoload.php; fi
exit 0
EOF
  chmod +x "$TMP/fake-$t"
done
export WTSETUP_COMPOSER="$TMP/fake-composer" WTSETUP_NPM="$TMP/fake-npm" WTSETUP_BUN="$TMP/fake-bun"
calls() { grep -c "$1" "$TMP/calls.log" 2>/dev/null; true; }
setup() { : > "$TMP/calls.log"; bash "$SETUP" "$1" "$2" >"$TMP/out" 2>"$TMP/err"; echo $?; }

# A Laravel+Vite main checkout
M="$TMP/main"; mkdir -p "$M/vendor" "$M/node_modules" "$M/resources/js" "$M/public/build"
echo APP=x > "$M/.env"; echo '{"scripts":{"build":"vite build"}}' > "$M/package.json"; echo '{}' > "$M/composer.json"
echo lock1 > "$M/composer.lock"; echo plock1 > "$M/package-lock.json"; : > "$M/vendor/autoload.php"
echo 'export default {}' > "$M/vite.config.js"; echo js > "$M/resources/js/app.js"
sleep 1; echo '{}' > "$M/public/build/manifest.json"   # build newer than every source

clone() { rm -rf "$1"; mkdir -p "$1"; for f in .env package.json composer.json composer.lock package-lock.json vite.config.js; do cp "$M/$f" "$1/" 2>/dev/null; done; cp -R "$M/resources" "$1/resources"; }

W="$TMP/w1"; clone "$W"; rm "$W/.env"
check "matching lockfiles: exit 0" "0" "$(setup "$W" "$M")"
check ".env copied" "APP=x" "$(cat "$W/.env")"
check "vendor cloned (a directory, not a symlink)" "yes" "$([ -d "$W/vendor" ] && [ ! -L "$W/vendor" ] && echo yes || echo no)"
check "composer install ran once after the clone (no-op when in sync)" "1" "$(calls 'composer install')"
check "node_modules cloned, npm ci not run" "yes 0" "$([ -d "$W/node_modules" ] && echo yes) $(calls 'npm ci')"
check "public/build cloned when sources match, no build" "yes 0" "$([ -f "$W/public/build/manifest.json" ] && echo yes) $(calls 'npm run build')"
check "second run is idempotent: no tool call" "0 0" "$(setup "$W" "$M") $(calls .)"
check "a second run does not nest a copy of public/build" "no" "$([ -e "$W/public/build/build" ] && echo yes || echo no)"
echo OTHER > "$W/.env"; setup "$W" "$M" >/dev/null
check ".env is never overwritten" "OTHER" "$(cat "$W/.env")"

W="$TMP/w2"; clone "$W"; echo lock2 > "$W/composer.lock"; echo plock2 > "$W/package-lock.json"
check "different lockfiles: exit 0" "0" "$(setup "$W" "$M")"
check "composer install and npm ci instead of a clone" "1 1" "$(calls 'composer install') $(calls 'npm ci')"
check "changed lockfile also means a fresh build" "1" "$(calls 'npm run build')"

W="$TMP/w2b"; clone "$W"; FAKE_NPM_LS_FAIL=1 setup "$W" "$M" >/dev/null
check "a cloned node_modules that is out of sync is reinstalled" "1" "$(calls 'npm ci')"

W="$TMP/w3"; clone "$W"; echo 'new js' > "$W/resources/js/app.js"
setup "$W" "$M" >/dev/null
check "changed frontend source builds instead of cloning" "1" "$(calls 'npm run build')"

# nested app dir (manifest not at the root) and a bun backend
M2="$TMP/main2"; mkdir -p "$M2/backend/node_modules"; echo '{}' > "$M2/backend/package.json"; echo b1 > "$M2/backend/bun.lock"; echo K=1 > "$M2/backend/.env"
W="$TMP/w4"; mkdir -p "$W/backend"; cp "$M2/backend/package.json" "$M2/backend/bun.lock" "$W/backend/"
check "nested dir: exit 0" "0" "$(setup "$W" "$M2")"
check "nested dir gets .env and a node_modules clone" "K=1 yes" "$(cat "$W/backend/.env") $([ -d "$W/backend/node_modules" ] && echo yes)"
W="$TMP/w5"; mkdir -p "$W/backend"; cp "$M2/backend/package.json" "$W/backend/"; echo b2 > "$W/backend/bun.lock"
setup "$W" "$M2" >/dev/null
check "bun lock differs: bun install --frozen-lockfile" "1" "$(calls 'bun install --frozen-lockfile')"

# pure Swift/Xcode repo and a mobile project: nothing to do
W="$TMP/w6"; M3="$TMP/main3"; mkdir -p "$W" "$M3"; echo "name: App" > "$W/project.yml"
check "a Swift repo is a no-op" "0 0" "$(setup "$W" "$M3") $(calls .)"
W="$TMP/w7"; M4="$TMP/main4"; mkdir -p "$W/native/ios" "$M4/native"; echo '{"dependencies":{"expo":"1"}}' > "$W/native/package.json"
check "a mobile project is skipped" "0 0" "$(setup "$W" "$M4") $(calls .)"

# a nested tool folder the main checkout never installed is skipped
W="$TMP/w10"; M6="$TMP/main6"; mkdir -p "$W/tools" "$M6/tools"; echo '{}' > "$W/tools/package.json"; echo p1 > "$W/tools/package-lock.json"; cp "$W/tools/package-lock.json" "$M6/tools/"
check "an uninstalled nested tool folder is no work" "0 0" "$(setup "$W" "$M6") $(calls .)"

# a Laravel app that lists capacitor is a web app, not skipped
W="$TMP/w9"; M5="$TMP/main5"; mkdir -p "$W/ios" "$M5"; echo '{"dependencies":{"@capacitor/core":"1"}}' > "$W/package.json"; echo '{}' > "$W/composer.json"; echo K=2 > "$M5/.env"
setup "$W" "$M5" >/dev/null
check "a composer app with capacitor in package.json still gets set up" "K=2" "$(cat "$W/.env" 2>/dev/null)"

# failure: one line on stderr, non-zero
W="$TMP/w8"; clone "$W"; echo lock9 > "$W/composer.lock"
check "a failing composer install exits 1" "1" "$(FAKE_FAIL=composer setup "$W" "$M")"
check "the failure is one plain line naming the step" "1 yes" "$(grep -c . "$TMP/err") $(grep -q 'FAILED composer install.*boom from composer' "$TMP/err" && echo yes)"
check "missing arguments exit 2" "2" "$(bash "$SETUP" >/dev/null 2>&1; echo $?)"

[ "$FAIL" -eq 0 ] && echo "WORKTREE_SETUP_TEST=OK" || { echo "WORKTREE_SETUP_TEST=FAIL ($FAIL)"; exit 1; }
