#!/usr/bin/env bash
# Makes a fresh git worktree testable: .env, vendor, node_modules, public/build. Called by `/worktree new` and by the
# Feierabend daemon before an agent starts, so no agent has to improvise the setup (2026-11-05: an events worktree
# without public/build failed the browser tests for 29 minutes on a false red; a symlinked vendor breaks Pest with
# "facade root not set"; node_modules and the build were only fixed after the red run).
#
# Usage: worktree-setup.sh <worktree> <main-checkout>
# Exit:  0 ok (also nothing to do), 1 a step failed (one line `worktree-setup: FAILED ...` on stderr), 2 usage.
# Env (tests): WTSETUP_COMPOSER (composer) WTSETUP_NPM (npm) WTSETUP_BUN (bun)
#
# Per app dir: the worktree root plus every nested dir (depth <= 3) that has composer.json or package.json, so a
# repo with `backend/` or `app/` is covered. Mobile projects (package.json with expo, react-native or capacitor)
# and pure Swift/Xcode repos have nothing a test needs and are skipped, so such a repo is a no-op.
#   .env          copied from the main checkout when the worktree has none (never overwritten).
#   vendor        APFS clone (`cp -c -R`) of the main checkout's vendor when composer.lock is identical, followed
#                 by `composer install` (a no-op when in sync); else `composer install`. A symlink is never used.
#   node_modules  (a nested folder only when the main checkout installed it too) clone when the lockfile (package-lock.json, bun.lock, yarn.lock) is identical, else `npm ci`
#                 (`bun install --frozen-lockfile`, `yarn install --frozen-lockfile`).
#   public/build  clone of main's build when its lockfile, resources/ and the vite/tailwind/postcss configs are
#                 identical and the build is newer than every source, else `npm run build` (vite projects).
# The test database needs no step: the project's test bootstrap creates `<base>_<slug>` and registers it in
# ~/.local/state/claude/test-dbs.list (lib-testrun.sh), which worktree-cleanup.sh drops again.
# Idempotent: a piece that exists is left alone. No migrations (they would hit the shared dev database).
# bash 3.2 compatible.

set -u
WT=${1:-}; MAIN=${2:-}
[ -n "$WT" ] && [ -n "$MAIN" ] && [ -d "$WT" ] && [ -d "$MAIN" ] || { echo "usage: worktree-setup.sh <worktree> <main-checkout>" >&2; exit 2; }
WT=$(cd "$WT" && pwd -P); MAIN=$(cd "$MAIN" && pwd -P)
COMPOSER=${WTSETUP_COMPOSER:-composer}; NPM=${WTSETUP_NPM:-npm}; BUN=${WTSETUP_BUN:-bun}
DONE=""

fail() { echo "worktree-setup: FAILED $1 in ${REL:-.}: $2" >&2; exit 1; }
note() { DONE="$DONE${DONE:+, }$1${REL:+ ($REL)}"; }
same() { [ -f "$1" ] && [ -f "$2" ] && cmp -s "$1" "$2"; }   # both files exist and are identical
run() {  # <step> <cmd...>: output only on failure
  local step=$1 out; shift
  out=$("$@" 2>&1) || fail "$step" "$(printf '%s' "$out" | tail -n 1 | cut -c1-160)"
}

# A mobile project: expo/react-native/capacitor plus an ios or android folder, and no composer.json next to it
# (a Laravel app that also lists capacitor is still a web app).
is_mobile() {
  [ ! -f "$1/composer.json" ] && grep -qE '"(expo|react-native|@capacitor/core)"' "$1/package.json" 2>/dev/null \
    && { [ -d "$1/ios" ] || [ -d "$1/android" ]; }
}

setup_dir() {  # <rel dir, "" for the root>
  local rel=$1 w m lock
  REL=$rel
  w=$WT${rel:+/$rel}; m=$MAIN${rel:+/$rel}
  [ -f "$w/.env" ] || { [ -f "$m/.env" ] && cp "$m/.env" "$w/.env" && note ".env"; }

  if [ -f "$w/composer.json" ] && [ ! -f "$w/vendor/autoload.php" ]; then
    rm -rf "$w/vendor"
    if same "$w/composer.lock" "$m/composer.lock" && [ -f "$m/vendor/autoload.php" ]; then
      cp -c -R "$m/vendor" "$w/vendor" || fail "vendor clone" "cp failed"
      # `install` after the clone: a no-op when vendor is in sync with composer.lock, and it fixes a main checkout whose
      # vendor is stale; it also rebuilds the autoloader for the new path (what dump-autoload did alone before).
      ( cd "$w" && run "composer install" "$COMPOSER" install --no-interaction --quiet ) || exit 1
      note "vendor cloned"
    else
      ( cd "$w" && run "composer install" "$COMPOSER" install --no-interaction --quiet ) || exit 1
      note "composer install"
    fi
  fi

  # A nested tool folder that the main checkout never installed (scripts/, an MCP helper) is not part of the tests: skipped.
  if [ -f "$w/package.json" ] && [ ! -d "$w/node_modules" ] && { [ -z "$rel" ] || [ -d "$m/node_modules" ] || [ -f "$w/composer.json" ]; }; then
    lock=""
    for f in package-lock.json bun.lock yarn.lock; do [ -f "$w/$f" ] && { lock=$f; break; }; done
    if [ -n "$lock" ] && same "$w/$lock" "$m/$lock" && [ -d "$m/node_modules" ]; then
      cp -c -R "$m/node_modules" "$w/node_modules" || fail "node_modules clone" "cp failed"
      # cheap sync check (reads node_modules, no network): a stale main checkout falls back to a clean install
      if ( cd "$w" && "$NPM" ls --depth=0 >/dev/null 2>&1 ); then note "node_modules cloned"
      else
        rm -rf "$w/node_modules"
        ( cd "$w" && run "npm ci" "$NPM" ci --silent ) || exit 1
        note "node_modules cloned, out of sync, reinstalled"
      fi
    else
      case "$lock" in
        bun.lock)  ( cd "$w" && run "bun install" "$BUN" install --frozen-lockfile ) || exit 1 ;;
        yarn.lock) ( cd "$w" && run "yarn install" yarn install --frozen-lockfile ) || exit 1 ;;
        *)         ( cd "$w" && run "npm ci" "$NPM" ci --silent ) || exit 1 ;;
      esac
      note "node_modules installed"
    fi
  fi

  setup_build "$w" "$m"
  REL=""
}

# Frontend build for Laravel+Vite apps: the browser tests load public/build.
setup_build() {  # <worktree app dir> <main app dir>
  local w=$1 m=$2 f same_src=1
  ls "$w"/vite.config.* >/dev/null 2>&1 || return 0
  grep -q '"build"' "$w/package.json" 2>/dev/null || return 0
  [ -f "$w/public/build/manifest.json" ] && return 0
  if [ -f "$m/public/build/manifest.json" ] && same "$w/package-lock.json" "$m/package-lock.json"; then
    for f in vite.config.js vite.config.ts vite.config.mjs tailwind.config.js tailwind.config.ts postcss.config.js; do
      if [ -f "$w/$f" ] || [ -f "$m/$f" ]; then same "$w/$f" "$m/$f" || same_src=0; fi
    done
    [ -d "$w/resources" ] && ! diff -rq "$w/resources" "$m/resources" >/dev/null 2>&1 && same_src=0
    # a build older than a source in main is stale, whatever the worktree holds
    [ -n "$(find "$m/resources" "$m/vite.config."* -newer "$m/public/build/manifest.json" -print -quit 2>/dev/null)" ] && same_src=0
    if [ "$same_src" = 1 ]; then
      mkdir -p "$w/public"
      cp -c -R "$m/public/build" "$w/public/build" || fail "build clone" "cp failed"
      note "public/build cloned"
      return 0
    fi
  fi
  [ -d "$w/node_modules" ] || fail "npm run build" "node_modules missing"
  ( cd "$w" && run "npm run build" "$NPM" run build --silent ) || exit 1
  note "public/build built"
}

# Root first, then nested manifests (never inside dependency or build folders).
APPS=$(cd "$WT" && find . -maxdepth 4 \( -name node_modules -o -name vendor -o -name .git -o -name .build -o -name build -o -name DerivedData -o -name Pods \) -prune -o \
  \( -name composer.json -o -name package.json \) -print 2>/dev/null | while IFS= read -r f; do d=$(dirname "$f"); echo "${d#./}"; done | sort -u)
[ -n "$APPS" ] || { echo "worktree-setup: ok (nothing to set up)"; exit 0; }
while IFS= read -r d; do
  [ "$d" = . ] && d=""
  case "$d" in */*/*/*) continue ;; esac   # depth <= 3
  [ -z "$d" ] || [ -d "$MAIN/$d" ] || continue   # the folder is new on this branch: nothing to clone from
  is_mobile "$WT${d:+/$d}" && continue
  setup_dir "$d"
done <<EOF
$APPS
EOF
if [ -n "$DONE" ]; then echo "worktree-setup: ok ($DONE)"; else echo "worktree-setup: ok (nothing to do)"; fi
