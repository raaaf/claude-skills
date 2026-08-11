#!/usr/bin/env bash
#
# Framework detection. Prints:
#   FRAMEWORK=<laravel|nextjs|nuxt|django|react-native|flutter|ios|android|generic>
#   SOURCE_DIRS=<space-separated source directories, each %q-quoted individually>
#   PLATFORM=<web|native|cross>
#
# Usage: bash detect-framework.sh [PROJECT_ROOT]
# Shared by /audit and /full-audit.
#
# ============================================================================
# CONSUMPTION CONTRACT -- READ BEFORE WRITING A NEW CONSUMER
# ============================================================================
# SOURCE_DIRS is a list of directories, each individually %q-quoted, joined by
# PLAIN (unescaped) separator spaces. A %q escape protects ONLY a space that
# is actually inside a directory name -- the spaces between elements are real
# and must stay real, or a directory name containing a space becomes
# indistinguishable from a separator. See the comment above the emit block at
# the bottom of this file for why that distinction has to be preserved.
#
# CONSEQUENCE: the three-line output CANNOT be consumed with one blanket
#   eval "$(bash detect-framework.sh)"
# The unescaped separator spaces in the SOURCE_DIRS line make it several
# shell words, not a single assignment. Bash's "VAR=value word2 word3" sets
# VAR only in word2's environment while word2 itself runs as a command -- it
# does NOT persist VAR as a shell variable in the calling shell. Verified
# directly on this repo (2026-08-11): FRAMEWORK and PLATFORM survive a
# blanket eval untouched (they are ordinary single-word lines with nothing
# after them), SOURCE_DIRS silently comes out EMPTY, and bash prints an
# unrelated-looking error ("<dir>: is a directory" or "No such file or
# directory") that gives no hint SOURCE_DIRS is the actual casualty. This is
# the exact shape of the Critical bug fixed earlier the same day, when an
# unquoted SOURCE_DIRS left every multi-directory framework with an empty
# scope and /full-audit silently audited the wrong file set.
#
# CORRECT consumption -- capture the output as text, extract each value by
# key, THEN reconstruct the array with its own targeted eval:
#   FW_OUT="$(bash detect-framework.sh)"
#   FRAMEWORK=$(printf '%s\n' "$FW_OUT" | sed -n 's/^FRAMEWORK=//p')
#   SOURCE_DIRS=$(printf '%s\n' "$FW_OUT" | sed -n 's/^SOURCE_DIRS=//p')
#   PLATFORM=$(printf '%s\n' "$FW_OUT" | sed -n 's/^PLATFORM=//p')
#   eval "SOURCE_DIRS_ARR=($SOURCE_DIRS)"     # array context, not a blanket eval
#
# All in-repo consumers (audit/SKILL.md, full-audit/references/
# scope-context-batching.md, design-audit/SKILL.md, app-baseline/bin/
# baseline-scan.sh) already use this pattern -- baseline-scan.sh additionally
# greps for `^(PLATFORM|FRAMEWORK)=` before its eval, which is also safe
# since it strips the SOURCE_DIRS line out before eval ever sees it. The risk
# this block guards against is the NEXT consumer, written from memory or an
# old example, that reaches for the blanket form again.
# ============================================================================
set -euo pipefail

ROOT="${1:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
cd "$ROOT"

PLATFORM="web"

# Every branch below builds SOURCE_DIRS_LIST as a bash ARRAY, one directory
# per element, never as a joined string. This matters for any branch that
# derives its list from `find`: joining into "dir1 dir2 dir3" first and only
# quoting at the very end (as this script used to) throws away the one piece
# of information that distinguishes a separator space from a space inside a
# directory name -- by the time it's one string, that's undecidable. Building
# the array directly, and reading `find`/`dirname` output line-by-line with
# `IFS= read -r`, keeps each directory intact (embedded spaces included)
# until the single %q-quoting pass at the bottom.

if [ -f "artisan" ]; then
  FRAMEWORK="laravel"
  SOURCE_DIRS_LIST=("app/" "resources/" "database/" "routes/" "config/")
elif [ -f "package.json" ] && grep -q '"react-native"' package.json 2>/dev/null; then
  FRAMEWORK="react-native"
  SOURCE_DIRS_LIST=("src/" "app/" "components/" "ios/" "android/")
  PLATFORM="cross"
elif [ -f "pubspec.yaml" ] && grep -q '^flutter:' pubspec.yaml 2>/dev/null; then
  FRAMEWORK="flutter"
  SOURCE_DIRS_LIST=("lib/" "test/")
  PLATFORM="cross"
elif [ -f "package.json" ] && grep -q '"next"' package.json 2>/dev/null; then
  FRAMEWORK="nextjs"
  SOURCE_DIRS_LIST=("src/" "app/" "pages/" "components/" "lib/")
elif [ -f "nuxt.config.ts" ] || [ -f "nuxt.config.js" ]; then
  FRAMEWORK="nuxt"
  SOURCE_DIRS_LIST=("components/" "composables/" "pages/" "layouts/" "server/")
elif [ -f "manage.py" ]; then
  FRAMEWORK="django"
  SOURCE_DIRS_LIST=()
  while IFS= read -r d; do
    [ -z "$d" ] && continue
    SOURCE_DIRS_LIST+=("$d")
  done < <(find . -name 'apps.py' -exec dirname {} \; 2>/dev/null | head -20 || true)
  [ "${#SOURCE_DIRS_LIST[@]}" -eq 0 ] && SOURCE_DIRS_LIST=("./")
elif ls -d ./*.xcodeproj >/dev/null 2>&1 || ls -d ./*.xcworkspace >/dev/null 2>&1 || { [ -f "Package.swift" ] && find . -maxdepth 3 -name "*.swift" -path "*Sources*" | head -1 | grep -q .; }; then
  FRAMEWORK="ios"
  SOURCE_DIRS_LIST=()
  while IFS= read -r d; do
    [ -z "$d" ] && continue
    SOURCE_DIRS_LIST+=("$d")
  done < <(find . -maxdepth 2 -type d \( -name Sources -o -name '*App' \) 2>/dev/null | head -5 || true)
  [ "${#SOURCE_DIRS_LIST[@]}" -eq 0 ] && SOURCE_DIRS_LIST=("./")
  PLATFORM="native"
elif [ -f "settings.gradle" ] || [ -f "settings.gradle.kts" ]; then
  FRAMEWORK="android"
  SOURCE_DIRS_LIST=("app/src/main/")
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
  SOURCE_DIRS_LIST=()
  for d in $CANDIDATES; do
    [ -d "$d" ] && SOURCE_DIRS_LIST+=("$d/")
  done

  if [ "${#SOURCE_DIRS_LIST[@]}" -eq 0 ]; then
    # None of the conventional names exist either. Derive the source set from
    # what the repo actually tracks: top-level directories holding
    # git-tracked files, minus the same dependency/build directories every
    # consumer already prunes (EXCLUDE in scope-context-batching.md,
    # FIND_OPTS in detect-mobile.sh) -- so a caller that skips those prunes
    # still doesn't sweep in node_modules/vendor/build output.
    if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
      # -c core.quotePath=false disables git's default C-quoting of non-ASCII
      # bytes in a path. With the default on, a directory named "Übersicht"
      # prints from `git ls-files` as the octal-escaped literal
      # "\303\234bersicht/sub/file.txt", which this derivation would carry
      # straight through -- no find(1) on disk matches that string, so the
      # directory silently disappears from SOURCE_DIRS. -z + NUL-splitting
      # would be the fully robust fix but is out of scope here (grep/sort/awk
      # below are all line-oriented); quotePath=false covers the reproduced
      # non-ASCII loss without rewriting the whole pipeline.
      #
      # grep -v legitimately finds nothing to filter on a repo with no
      # matching noise dirs (or no subdirectories at all) and exits 1 in that
      # case; under `set -o pipefail` that would abort the whole script, so
      # `|| true` treats "nothing left after filtering" as the valid empty
      # result it is, not an error.
      RAW_TOP_DIRS=$( (git -c core.quotePath=false ls-files 2>/dev/null | awk -F/ 'NF>1 {print $1}' | sort -u |
        grep -vE '^(node_modules|vendor|\.next|\.nuxt|dist|build|coverage|\.git|\.github|\.vscode|\.idea|target|out|\.venv|__pycache__)$' || true) )

      # A directory name containing a space is now representable: it stays
      # one array element here and gets %q-quoted individually at the final
      # emit below, instead of being flattened into the same space-joined
      # string every other element uses. No skip, no narrower scope.
      SOURCE_DIRS_LIST=()
      while IFS= read -r d; do
        [ -z "$d" ] && continue
        SOURCE_DIRS_LIST+=("$d/")
      done <<< "$RAW_TOP_DIRS"
    fi
  fi

  # Still nothing: either not a git repo, or every tracked file sits directly
  # at the repo root with no subdirectory to name. Fall back to the whole
  # tree -- same precedent as the django/ios branches above. An honest
  # "audit everything" beats aborting, and this is the last resort, not the
  # default path (both prior steps run first).
  [ "${#SOURCE_DIRS_LIST[@]}" -eq 0 ] && SOURCE_DIRS_LIST=("./")
fi

echo "FRAMEWORK=$FRAMEWORK"
# Each directory is %q-quoted INDIVIDUALLY, then joined with a single plain
# (unescaped) space. This is the fix for the old contract, which applied %q
# to the whole joined string: that escaped every separator space too, so
# after `eval` rebuilt the string, a separator space and a space that was
# part of a directory's own name were the same byte sequence and the split
# was no longer reversible. Quoting per element instead means %q only ever
# escapes a space that is actually INSIDE a name -- the separators between
# elements stay real, unescaped spaces.
#
# MUST be consumed as: capture this script's stdout as text (do NOT run the
# whole 3-line output through a single `eval "$(...)"`, since the SOURCE_DIRS
# line's unescaped separator spaces make it multiple shell words, not one
# assignment), extract the value after `SOURCE_DIRS=`, then:
#   eval "SOURCE_DIRS_ARR=($SOURCE_DIRS)"
# This is the standard pattern for reconstructing an array from a %q-quoted,
# space-joined element list: bash's `NAME=(...)` compound-assignment syntax
# treats the parenthesized list as array-literal words, splitting on
# unescaped whitespace and honoring each element's own %q escaping (of
# spaces, quotes, `$`, backticks, `;`, and anything else shell-active) so an
# attacker-controlled directory name in an audited repo can only ever
# reconstruct as inert text, never as something that executes. Known
# consumers:
#   - full-audit/references/scope-context-batching.md -- extracts the line,
#     then `eval "SOURCE_DIRS_ARR=($SOURCE_DIRS)"` (correct)
#   - audit/SKILL.md Phase 1 -- extracts FRAMEWORK/SOURCE_DIRS/PLATFORM the
#     same way, re-echoes them clean for the orchestrator to read as text
#   - design-audit/SKILL.md Phase 1 -- reads FRAMEWORK/PLATFORM raw from
#     stdout (fine, single-token values); does not consume SOURCE_DIRS
SOURCE_DIRS=""
for d in "${SOURCE_DIRS_LIST[@]}"; do
  q=$(printf '%q' "$d")
  SOURCE_DIRS="$SOURCE_DIRS $q"
done
SOURCE_DIRS="${SOURCE_DIRS# }"
echo "SOURCE_DIRS=$SOURCE_DIRS"
echo "PLATFORM=$PLATFORM"
