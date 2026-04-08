#!/usr/bin/env bash
#
# Collect audit scope for /audit.
#
# Prints:
#   DEFAULT_BRANCH=<name>
#   BASE_REF=<commit-sha used as diff base>
#   ---FILES---
#   <deduped list of changed files>
#   ---FRONTEND---
#   <subset: frontend files>
#   ---TRANSLATIONS---
#   <subset: translation files>
#   ---DIFF---
#   <deduplicated unified diff>
#
# Diff base resolution order:
#   1. origin/<default-branch> if present
#   2. upstream branch (@{u}) if configured
#   3. merge-base with main/master/develop/trunk
#   4. HEAD~20 as last resort (capped to commit history length)
#
# Usage: bash collect-scope.sh
set -euo pipefail

# shellcheck disable=SC1091
source "$(dirname "$0")/lib-git-base.sh"
DEFAULT_BRANCH=$(resolve_default_branch)
BASE_REF=$(resolve_base_ref "$DEFAULT_BRANCH")

echo "DEFAULT_BRANCH=$DEFAULT_BRANCH"
echo "BASE_REF=$BASE_REF"

# --- 3. Collect changed files (deduped) -----------------------------------
FILES=$(
  {
    git diff --name-only "$BASE_REF"...HEAD 2>/dev/null || true
    git diff --name-only
    git diff --name-only --staged
    git ls-files --others --exclude-standard
  } | grep -v '^$' | sort -u || true
)

echo "---FILES---"
printf '%s\n' "$FILES"

# --- 4. Classify: frontend + translation ----------------------------------
FRONTEND=$(printf '%s\n' "$FILES" | grep -E '\.(blade\.php|html|vue|tsx?|jsx?|css|scss|svelte|astro)$' || true)
echo "---FRONTEND---"
printf '%s\n' "$FRONTEND"

TRANSLATIONS=$(printf '%s\n' "$FILES" \
  | grep -E '(^|/)(lang|locales?|translations?|messages|i18n)/' \
  | grep -E '\.(php|json|ya?ml|pot?|ts|js)$' || true)
echo "---TRANSLATIONS---"
printf '%s\n' "$TRANSLATIONS"

# --- 5. Unified diff (deduped) --------------------------------------------
# Single committed-unpushed diff + single working-tree diff (covers both
# staged and unstaged via `HEAD`). No three-way overlap.
echo "---DIFF---"
git diff "$BASE_REF"...HEAD 2>/dev/null || true
git diff HEAD 2>/dev/null || true
