#!/usr/bin/env bash
#
# Deterministic design-check. Decides whether Screenshot verification is
# required based on whether any visually relevant files appear in the current
# changeset (committed-unpushed + staged + unstaged + untracked).
#
# Usage: bash design-check.sh [--full]
#   --full   scan the entire codebase (for /full-audit) instead of the diff
#
# Output:
#   DESIGN_CHECK_RESULT=SCREENSHOTS_ERFORDERLICH | KEINE_VISUELLEN_DATEIEN
#   DATEIEN: <newline-separated list, only on SCREENSHOTS_ERFORDERLICH>
set -euo pipefail

MODE="diff"
[ "${1:-}" = "--full" ] && MODE="full"

PROJECT_ROOT=$(git rev-parse --show-toplevel)
cd "$PROJECT_ROOT"
EXTENSIONS='*.blade.php *.html *.vue *.tsx *.jsx *.svelte *.astro *.css *.scss'

# Framework-specific visually relevant backend patterns
if [ -f "artisan" ]; then
  VISUAL_BACKEND_PATTERN='app/Livewire/**/*.php'
elif [ -f "package.json" ] && grep -q '"next"' package.json 2>/dev/null; then
  VISUAL_BACKEND_PATTERN='src/**/*.tsx src/**/*.jsx app/**/*.tsx app/**/*.jsx'
elif [ -f "nuxt.config.ts" ] || [ -f "nuxt.config.js" ]; then
  VISUAL_BACKEND_PATTERN='components/**/*.vue pages/**/*.vue layouts/**/*.vue'
else
  VISUAL_BACKEND_PATTERN=''
fi

if [ "$MODE" = "full" ]; then
  ALL_VISUAL=$(find . -type f \
    \( -name '*.blade.php' -o -name '*.html' -o -name '*.vue' \
       -o -name '*.tsx' -o -name '*.jsx' -o -name '*.svelte' -o -name '*.astro' \
       -o -name '*.css' -o -name '*.scss' \) \
    -not -path '*/vendor/*' -not -path '*/node_modules/*' -not -path '*/.next/*' \
    -not -path '*/dist/*' -not -path '*/build/*' 2>/dev/null | sort -u)
else
  # shellcheck disable=SC1091
  source "$(dirname "$0")/lib-git-base.sh"
  DEFAULT_BRANCH=$(resolve_default_branch)
  BASE_REF=$(resolve_base_ref "$DEFAULT_BRANCH")
  # shellcheck disable=SC2086
  COMMITTED=$(git diff --name-only "$BASE_REF"...HEAD -- $EXTENSIONS $VISUAL_BACKEND_PATTERN 2>/dev/null || true)
  # shellcheck disable=SC2086
  WORKING=$(git diff --name-only HEAD -- $EXTENSIONS $VISUAL_BACKEND_PATTERN 2>/dev/null || true)
  # shellcheck disable=SC2086
  UNTRACKED=$(git ls-files --others --exclude-standard -- $EXTENSIONS $VISUAL_BACKEND_PATTERN 2>/dev/null || true)
  ALL_VISUAL=$(printf '%s\n' "$COMMITTED" "$WORKING" "$UNTRACKED" | grep -v '^$' | sort -u || true)
fi

if [ -n "$ALL_VISUAL" ]; then
  echo "DESIGN_CHECK_RESULT=SCREENSHOTS_ERFORDERLICH"
  echo "DATEIEN:"
  echo "$ALL_VISUAL"
else
  echo "DESIGN_CHECK_RESULT=KEINE_VISUELLEN_DATEIEN"
fi
