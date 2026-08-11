#!/usr/bin/env bash
#
# check-swift-deprecations.sh — deterministic grep for Swift anti-patterns
# that keep re-entering new code despite existing agent rules.
#
# Why this exists: UIScreen.main resurfaced 3x across separate audits
# (2026-05-17 ChatView, 2026-05-19 ChatView, 2026-07-02 RecipeDetailView)
# even though a code-quality agent rule has caught it every time since
# 2026-05-19. The rule works, it just does not stop the pattern from being
# typed again in new code, and a full agent pass is an expensive way to
# re-catch the same three literal strings. This is a plain text grep, not a
# parser — these are convention drifts (naming/API-choice), not structural
# bugs, so false positives are cheap to eyeball and precision does not need
# AST-level rigor the way duplicate-key detection did.
#
# Patterns, scoped to DIFF-changed .swift files only:
#   - UIScreen.main            deprecated screen-bounds access
#   - try!                     outside #Preview blocks and test files
#   - Color.red / Color.white / .foregroundStyle(.white)
#                               outside Theme.swift / Brand.swift
#
# #Preview-block detection is brace-depth tracking from the `#Preview` token
# to its closing `}` — correct for normally-formatted Swift, not comment/
# string-literal aware. Test files are recognized by path (a `Tests/`
# directory segment or a `*Tests.swift` filename).
#
# Output:
#   SWIFTDEPR_RESULT=OK | FINDINGS | SKIP
#   For FINDINGS: one line per hit: "SWIFTDEPR {file}:{line}: {pattern} — {code}"
#
# Usage: bash check-swift-deprecations.sh [PROJECT_ROOT]
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="${1:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
cd "$ROOT" 2>/dev/null || { echo "SWIFTDEPR_RESULT=SKIP"; exit 0; }
git rev-parse --is-inside-work-tree >/dev/null 2>&1 || { echo "SWIFTDEPR_RESULT=SKIP"; exit 0; }

# shellcheck disable=SC1091
source "$SCRIPT_DIR/lib-git-base.sh"

# collect_changed_files() (committed-since-base + working tree + untracked,
# see lib-git-base.sh) is the same changed-file set every other audit script
# uses. A hand-rolled reimplementation here previously drifted from it (it
# unioned two separate `git diff` calls instead of the shared helper's
# `git diff --name-only HEAD`), so a file could count as changed for the rest
# of the pipeline but not for this check, or vice versa.
FILES=$(collect_changed_files | grep -E '\.swift$' || true)
[ -n "$FILES" ] || { echo "SWIFTDEPR_RESULT=SKIP"; exit 0; }

HITS=""
while IFS= read -r file; do
  [ -n "$file" ] || continue
  [ -f "$file" ] || continue

  base=$(basename "$file")
  is_test=0
  case "$file" in
    */Tests/*|*Tests.swift) is_test=1 ;;
  esac
  is_theme=0
  case "$base" in
    Theme.swift|Brand.swift) is_theme=1 ;;
  esac

  FILE_HITS=$(awk -v is_test="$is_test" -v is_theme="$is_theme" -v fname="$file" '
    {
      if ($0 ~ /#Preview/) { in_preview = 1; depth = 0 }
      if (in_preview) {
        tmp = $0; n_open = gsub(/{/, "{", tmp)
        tmp = $0; n_close = gsub(/}/, "}", tmp)
        depth += n_open - n_close
        if (depth <= 0 && n_close > 0) { in_preview = 0 }
      }

      if ($0 ~ /UIScreen\.main/) {
        trimmed = $0; gsub(/^[ \t]+|[ \t]+$/, "", trimmed)
        print fname":"FNR": UIScreen.main -- "trimmed
      }

      if (is_test == 0 && !in_preview && $0 ~ /try!/) {
        trimmed = $0; gsub(/^[ \t]+|[ \t]+$/, "", trimmed)
        print fname":"FNR": try! -- "trimmed
      }

      if (is_theme == 0 && ($0 ~ /Color\.red/ || $0 ~ /Color\.white/ || $0 ~ /\.foregroundStyle\(\.white\)/)) {
        trimmed = $0; gsub(/^[ \t]+|[ \t]+$/, "", trimmed)
        print fname":"FNR": hardcoded-color -- "trimmed
      }
    }
  ' "$file" 2>/dev/null)

  if [ -n "$FILE_HITS" ]; then
    HITS="${HITS}${FILE_HITS}
"
  fi
done <<< "$FILES"

HITS=$(printf '%s' "$HITS" | sed '/^$/d')

if [ -n "$HITS" ]; then
  echo "SWIFTDEPR_RESULT=FINDINGS"
  printf '%s\n' "$HITS" | while IFS= read -r line; do
    [ -n "$line" ] && echo "SWIFTDEPR $line"
  done
else
  echo "SWIFTDEPR_RESULT=OK"
fi
