#!/usr/bin/env bash
# Docs drift is the most frequent finding class in this pipeline (18 of 27
# audits), and prose reminders in guidelines/docs-sync.md demonstrably have not
# moved the number. This is the structural half: the ONE form of doc drift that
# can be decided mechanically.
#
# A file the diff deletes or renames away, while a doc still names it by path or
# basename, is drift with no judgment involved — the doc points at something that
# is not there any more. Everything else about docs (is the description still
# true?) stays an LLM call.
#
# Deliberately narrow: no "is this file mentioned anywhere" check. A source file
# absent from CLAUDE.md is the normal case, not a finding, and flagging it would
# bury the real hits.
#
# Result codes:
#   DOCSPATH_RESULT=FINDINGS  -> one Important [Docs] per DOCSPATH line
#   DOCSPATH_RESULT=CLEAN     -> nothing removed, or nothing referenced
#   DOCSPATH_RESULT=SKIP      -> no docs, or no base to diff against
#
# Usage: check-docs-path-drift.sh [BASE_REF] [ROOT]
set -euo pipefail
BASE="${1:-}"
ROOT="${2:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
cd "$ROOT"

if [ -z "$BASE" ]; then
  BASE=$(git merge-base HEAD origin/HEAD 2>/dev/null || git rev-parse HEAD 2>/dev/null || true)
fi
if [ -z "$BASE" ]; then
  echo "DOCSPATH_RESULT=SKIP"
  exit 0
fi

# Docs that describe the codebase AS IT IS. Root markdown plus the top level of
# docs/. Archives are excluded on purpose: a plan from May or an ADR naming a
# file that was deleted in July is a correct historical record, not drift, and
# including them buried the real hits under old plans on the first smoke test.
DOCS=$( { find . -maxdepth 1 -name '*.md' 2>/dev/null || true; find docs -maxdepth 1 -name '*.md' 2>/dev/null || true; } \
  | grep -vE '/(plans?|adrs?|decisions|archive|changelog)/' || true)
DOCS=$(printf '%s\n' "$DOCS" | grep -v '^$' || true)
if [ -z "$DOCS" ]; then
  echo "DOCSPATH_RESULT=SKIP"
  exit 0
fi

# Deleted (D) and rename-source (R) paths, committed diff plus working tree.
GONE=$( { git diff --name-status --diff-filter=DR "$BASE" 2>/dev/null || true; } \
  | awk '{print $2}' | sort -u)
if [ -z "$GONE" ]; then
  echo "DOCSPATH_RESULT=CLEAN"
  exit 0
fi

FINDINGS=0
OUT=""
while IFS= read -r path; do
  [ -n "$path" ] || continue
  # A path that came back under the same name (rename round trip, re-added file)
  # is not drift.
  [ -e "$path" ] && continue
  base=$(basename "$path")
  # Basename alone is too loose for generic names: require either the full path
  # or a basename with an extension, which is what docs actually quote.
  # Fixed-string match (-F): path/basename can contain regex metacharacters
  # that occur in real filenames (., +, (, [, a stray backslash, ...) — under
  # -E those cause either a false-negative miss or a spurious match, silently
  # swallowed by the 2>/dev/null below.
  case "$base" in
    *.*) hits=$( { printf '%s\n' "$DOCS" | tr '\n' '\0' | xargs -0 grep -nF -e "$path" -e "$base" 2>/dev/null || true; } ) ;;
    *)   hits=$( { printf '%s\n' "$DOCS" | tr '\n' '\0' | xargs -0 grep -nF -e "$path" 2>/dev/null || true; } ) ;;
  esac
  [ -n "$hits" ] || continue
  while IFS= read -r hit; do
    [ -n "$hit" ] || continue
    loc=$(printf '%s' "$hit" | cut -d: -f1,2)
    FINDINGS=1
    # Real newline, not a literal "\n": OUT is printed with printf '%s' below,
    # which does not interpret backslash escapes. A doc path/basename can
    # itself contain a backslash sequence (e.g. "\c"), and printf '%b' treats
    # that as an unknown escape that stops all further output -- silently
    # dropping every finding accumulated after it in the same OUT buffer.
    OUT="${OUT}DOCSPATH ${loc} references ${path}, removed in this diff
"
  done <<< "$hits"
done <<< "$GONE"

if [ "$FINDINGS" -eq 1 ]; then
  echo "DOCSPATH_RESULT=FINDINGS"
  printf '%s' "$OUT"
else
  echo "DOCSPATH_RESULT=CLEAN"
fi
