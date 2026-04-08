#!/usr/bin/env bash
#
# Detect companion mobile apps in the repo. Prints one MOBILE_APP=<kind> line
# per detected target. Silent if nothing is found.
#
# Monorepo-safe: walks up to 4 levels deep so a mobile workspace inside
# apps/, packages/, platforms/ is detected even when the root package.json
# has nothing about React Native. Skips vendor/build directories for speed.
set -euo pipefail

PROJECT_ROOT=$(git rev-parse --show-toplevel 2>/dev/null || pwd)
cd "$PROJECT_ROOT"

FIND_OPTS=(-maxdepth 4 -not -path '*/node_modules/*' -not -path '*/vendor/*' -not -path '*/.git/*' -not -path '*/dist/*' -not -path '*/build/*')

IOS_DIR=$(find . "${FIND_OPTS[@]}" \( -name "*.xcodeproj" -o -name "*.xcworkspace" -o -name "Podfile" -o -name "Package.swift" \) 2>/dev/null | head -1 || true)
ANDROID_DIR=$(find . "${FIND_OPTS[@]}" \( -name "build.gradle" -o -name "build.gradle.kts" -o -name "AndroidManifest.xml" \) 2>/dev/null | head -1 || true)
FLUTTER_CHECK=$(find . "${FIND_OPTS[@]}" -name "pubspec.yaml" 2>/dev/null | head -1 || true)
CAP_CHECK=$(find . "${FIND_OPTS[@]}" -name "capacitor.config.*" 2>/dev/null | head -1 || true)

# React Native: any package.json in the tree that declares react-native.
RN_CHECK=""
while IFS= read -r pkg; do
  if grep -q '"react-native"' "$pkg" 2>/dev/null; then
    RN_CHECK="$pkg"
    break
  fi
done < <(find . "${FIND_OPTS[@]}" -name "package.json" 2>/dev/null)

[ -n "$IOS_DIR" ]       && echo "MOBILE_APP=ios: $IOS_DIR"
[ -n "$ANDROID_DIR" ]   && echo "MOBILE_APP=android: $ANDROID_DIR"
[ -n "$RN_CHECK" ]      && echo "MOBILE_APP=react-native: $RN_CHECK"
[ -n "$FLUTTER_CHECK" ] && echo "MOBILE_APP=flutter: $FLUTTER_CHECK"
[ -n "$CAP_CHECK" ]     && echo "MOBILE_APP=capacitor: $CAP_CHECK"

exit 0
