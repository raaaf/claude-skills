#!/usr/bin/env bash
# Deterministic per-file guideline selection for /audit.
# Concept borrowed from mcp-context-toolkit (query_rules_for_file): given the
# changed files, which guidelines actually apply? Instead of a worker loading a
# whole guideline file unconditionally, the orchestrator can load only the ones
# whose scope matches the diff, and carry a priority as a severity anchor.
#
# A guideline MAY declare, in YAML frontmatter at the very top of the file:
#   applies_to: <ERE matched against changed file paths>   # one line, one regex
#   priority:   non_negotiable | mandatory | recommended   # -> Critical | Important | Minor anchor
# A guideline WITHOUT applies_to is ALWAYS applicable (backward compatible: every
# existing guideline keeps loading until it opts in).
#
# Emits one TAB line per applicable guideline:  <name.md>\t<priority>\t<scoped|always>
# Changed files come from git (same scope as check-skips.sh). bash 3.2 safe.
set -o pipefail
DIR="${1:?usage: match-guidelines.sh <guidelines-dir>}"
[ -d "$DIR" ] || { echo "guidelines dir not found: $DIR" >&2; exit 2; }

changed=$( {
  git diff --name-only HEAD 2>/dev/null
  git diff --name-only --cached 2>/dev/null
  git ls-files --others --exclude-standard 2>/dev/null
  up=$(git rev-parse --abbrev-ref --symbolic-full-name '@{u}' 2>/dev/null)
  [ -n "$up" ] && git diff --name-only "${up}...HEAD" 2>/dev/null
} | sort -u | grep -vE '(^|/)audit/evals/fixtures/' )   # fixtures = test data, no guideline signal (same rule as check-skips.sh)

for f in "$DIR"/*.md; do
  [ -f "$f" ] || continue
  pat=""; prio="recommended"
  if head -1 "$f" | grep -qx -- '---'; then
    fm=$(awk 'NR==1{next} /^---[[:space:]]*$/{exit} {print}' "$f")
    pat=$(printf '%s\n' "$fm" | grep -m1 '^applies_to:' | sed 's/^applies_to:[[:space:]]*//')
    p=$(printf '%s\n' "$fm" | grep -m1 '^priority:' | sed 's/^priority:[[:space:]]*//')
    [ -n "$p" ] && prio="$p"
  fi
  rel=$(basename "$f")
  if [ -z "$pat" ]; then
    printf '%s\t%s\talways\n' "$rel" "$prio"
  elif printf '%s\n' "$changed" | grep -qE "$pat"; then
    printf '%s\t%s\tscoped\n' "$rel" "$prio"
  fi
done
