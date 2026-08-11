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
  SOURCE_DIRS="src/ lib/ app/"
fi

echo "FRAMEWORK=$FRAMEWORK"
# %q-quoted so `eval "$(...)"` reconstructs the space-separated list as one
# assignment instead of word-splitting it into a second, failing command.
# Same pattern as perf-measure.sh --detect; don't simplify back to a bare echo.
printf 'SOURCE_DIRS=%q\n' "$SOURCE_DIRS"
echo "PLATFORM=$PLATFORM"
