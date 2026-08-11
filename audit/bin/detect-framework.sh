#!/usr/bin/env bash
#
# Framework detection. Prints:
#   FRAMEWORK=<laravel|nextjs|nuxt|django|react-native|flutter|ios|android|generic>
#   SOURCE_DIRS=<space-separated source directories>
#   PLATFORM=<web|native|cross>
#
# Usage: bash detect-framework.sh [PROJECT_ROOT]
# Shared by /audit and /full-audit.
set -euo pipefail

ROOT="${1:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
cd "$ROOT"

PLATFORM="web"

if [ -f "artisan" ]; then
  FRAMEWORK="laravel"
  SOURCE_DIRS="app/ resources/ database/ routes/ config/"
elif [ -f "package.json" ] && grep -q '"react-native"' package.json 2>/dev/null; then
  FRAMEWORK="react-native"
  SOURCE_DIRS="src/ app/ components/ ios/ android/"
  PLATFORM="cross"
elif [ -f "pubspec.yaml" ] && grep -q '^flutter:' pubspec.yaml 2>/dev/null; then
  FRAMEWORK="flutter"
  SOURCE_DIRS="lib/ test/"
  PLATFORM="cross"
elif [ -f "package.json" ] && grep -q '"next"' package.json 2>/dev/null; then
  FRAMEWORK="nextjs"
  SOURCE_DIRS="src/ app/ pages/ components/ lib/"
elif [ -f "nuxt.config.ts" ] || [ -f "nuxt.config.js" ]; then
  FRAMEWORK="nuxt"
  SOURCE_DIRS="components/ composables/ pages/ layouts/ server/"
elif [ -f "manage.py" ]; then
  FRAMEWORK="django"
  SOURCE_DIRS="$(find . -name 'apps.py' -exec dirname {} \; 2>/dev/null | head -20 | tr '\n' ' ' || true)"
  [ -z "$SOURCE_DIRS" ] && SOURCE_DIRS="./"
elif ls -d ./*.xcodeproj >/dev/null 2>&1 || ls -d ./*.xcworkspace >/dev/null 2>&1 || { [ -f "Package.swift" ] && find . -maxdepth 3 -name "*.swift" -path "*Sources*" | head -1 | grep -q .; }; then
  FRAMEWORK="ios"
  SOURCE_DIRS="$(find . -maxdepth 2 -type d \( -name Sources -o -name '*App' \) 2>/dev/null | head -5 | tr '\n' ' ' || true)"
  [ -z "${SOURCE_DIRS// /}" ] && SOURCE_DIRS="./"
  PLATFORM="native"
elif [ -f "settings.gradle" ] || [ -f "settings.gradle.kts" ]; then
  FRAMEWORK="android"
  SOURCE_DIRS="app/src/main/"
  PLATFORM="native"
else
  FRAMEWORK="generic"
  # No known framework marker matched. Prefer conventional source directory
  # names, but only the ones that actually exist -- a hard-coded "src/ lib/
  # app/" produces an empty SOURCE_DIRS on a repo like this one (top level is
  # audit/, full-audit/, write-a-skill/, ...), which zeroes out the `find` in
  # scope-context-batching.md and now trips its scope-plausibility abort
  # instead of the old silent "audited nothing" bug.
  CANDIDATES="src lib app source cmd pkg internal api server client packages"
  SOURCE_DIRS=""
  for d in $CANDIDATES; do
    [ -d "$d" ] && SOURCE_DIRS="$SOURCE_DIRS $d/"
  done
  SOURCE_DIRS="${SOURCE_DIRS# }"

  if [ -z "$SOURCE_DIRS" ]; then
    # None of the conventional names exist either. Derive the source set from
    # what the repo actually tracks: top-level directories holding
    # git-tracked files, minus the same dependency/build directories every
    # consumer already prunes (EXCLUDE in scope-context-batching.md,
    # FIND_OPTS in detect-mobile.sh) -- so a caller that skips those prunes
    # still doesn't sweep in node_modules/vendor/build output.
    if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
      # grep -v legitimately finds nothing to filter on a repo with no
      # matching noise dirs (or no subdirectories at all) and exits 1 in that
      # case; under `set -o pipefail` that would abort the whole script, so
      # `|| true` treats "nothing left after filtering" as the valid empty
      # result it is, not an error.
      SOURCE_DIRS=$( (git ls-files 2>/dev/null | awk -F/ 'NF>1 {print $1}' | sort -u |
        grep -vE '^(node_modules|vendor|\.next|\.nuxt|dist|build|coverage|\.git)$' || true) |
        sed 's/$/\//' | tr '\n' ' ')
      SOURCE_DIRS="${SOURCE_DIRS% }"
    fi
  fi

  # Still nothing: either not a git repo, or every tracked file sits directly
  # at the repo root with no subdirectory to name. Fall back to the whole
  # tree -- same precedent as the django/ios branches above. An honest
  # "audit everything" beats aborting, and this is the last resort, not the
  # default path (both prior steps run first).
  [ -z "$SOURCE_DIRS" ] && SOURCE_DIRS="./"
fi

echo "FRAMEWORK=$FRAMEWORK"
# %q-quoted so `eval "$(...)"` reconstructs the space-separated list as one
# assignment instead of word-splitting it into a second, failing command.
# Same pattern as perf-measure.sh --detect; don't simplify back to a bare echo.
# MUST be consumed via `eval "$(...)"`, never as bare stdout, or the %q
# backslash-escaping leaks through as literal text. Known consumers:
#   - full-audit/references/scope-context-batching.md — eval "$(...)" (correct)
#   - audit/SKILL.md Phase 1 — eval "$(...)" then re-echoes FRAMEWORK/
#     SOURCE_DIRS/PLATFORM clean, since the orchestrator reads that stdout
#     text to brief subagents
#   - design-audit/SKILL.md Phase 1 — reads FRAMEWORK/PLATFORM raw from
#     stdout (fine, single-token values); does not consume SOURCE_DIRS
printf 'SOURCE_DIRS=%q\n' "$SOURCE_DIRS"
echo "PLATFORM=$PLATFORM"
