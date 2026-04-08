#!/usr/bin/env bash
#
# Framework detection. Prints:
#   FRAMEWORK=<laravel|nextjs|nuxt|django|generic>
#   SOURCE_DIRS=<space-separated source directories>
#
# Usage: bash detect-framework.sh [PROJECT_ROOT]
# Shared by /audit and /full-audit.
set -euo pipefail

ROOT="${1:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
cd "$ROOT"

if [ -f "artisan" ]; then
  FRAMEWORK="laravel"
  SOURCE_DIRS="app/ resources/ database/ routes/ config/"
elif [ -f "package.json" ] && grep -q '"next"' package.json 2>/dev/null; then
  FRAMEWORK="nextjs"
  SOURCE_DIRS="src/ app/ pages/ components/ lib/"
elif [ -f "nuxt.config.ts" ] || [ -f "nuxt.config.js" ]; then
  FRAMEWORK="nuxt"
  SOURCE_DIRS="components/ composables/ pages/ layouts/ server/"
elif [ -f "manage.py" ]; then
  FRAMEWORK="django"
  SOURCE_DIRS="$(find . -name 'apps.py' -exec dirname {} \; | head -20 | tr '\n' ' ')"
else
  FRAMEWORK="generic"
  SOURCE_DIRS="src/ lib/ app/"
fi

echo "FRAMEWORK=$FRAMEWORK"
echo "SOURCE_DIRS=$SOURCE_DIRS"
