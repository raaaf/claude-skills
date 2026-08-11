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
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# Guarded source: a missing lib-git-base.sh must not silently produce an empty
# guideline set. The safe direction here is the same as for a guideline
# without applies_to: treat everything as always-applicable (lib_missing below).
# shellcheck disable=SC1091
[ -r "$SCRIPT_DIR/lib-git-base.sh" ] && source "$SCRIPT_DIR/lib-git-base.sh"
DIR="${1:?usage: match-guidelines.sh <guidelines-dir>}"
[ -d "$DIR" ] || { echo "guidelines dir not found: $DIR" >&2; exit 2; }

# Same file set as collect-scope.sh (same rule as check-skips.sh); fixtures = test data, no guideline signal.
lib_missing=0
if command -v collect_changed_files >/dev/null 2>&1; then
  changed=$(collect_changed_files | grep -vE '(^|/)audit/evals/fixtures/')
else
  echo "match-guidelines: lib-git-base.sh missing or collect_changed_files undefined -- cannot derive changed files, treating every guideline as always-applicable" >&2
  changed=""
  lib_missing=1
fi

for f in "$DIR"/*.md; do
  [ -f "$f" ] || continue
  pat=""; prio="recommended"
  if head -1 "$f" | grep -qx -- '---'; then
    fm=$(awk 'NR==1{next} /^---[[:space:]]*$/{exit} {print}' "$f")
    pat=$(printf '%s\n' "$fm" | grep -m1 '^applies_to:' | sed 's/^applies_to:[[:space:]]*//')
    # Strip one layer of surrounding quotes: a YAML-quoted ERE ("\.md$") is
    # otherwise used literally, including the quote characters, which makes
    # it valid-but-never-matching and the guideline silently DROPS out --
    # the same silent-drop class the malformed-ERE branch below guards against.
    case "$pat" in
      \"*\") pat="${pat#\"}"; pat="${pat%\"}" ;;
      \'*\') pat="${pat#\'}"; pat="${pat%\'}" ;;
    esac
    p=$(printf '%s\n' "$fm" | grep -m1 '^priority:' | sed 's/^priority:[[:space:]]*//')
    [ -n "$p" ] && prio="$p"
  fi
  rel=$(basename "$f")
  if [ -z "$pat" ] || [ "$lib_missing" = 1 ]; then
    printf '%s\t%s\talways\n' "$rel" "$prio"
    continue
  fi
  # Validate the ERE before relying on grep's exit code: on a malformed pattern
  # grep -qE also exits non-zero (same as "no match"), which previously made a
  # broken applies_to silently DROP the guideline -- the migration promise is
  # "never silently drops a guideline", so a bad pattern must fail open toward
  # always-applicable, and the problem must be visible, not silent.
  pat_err=$(printf '' | grep -E "$pat" 2>&1 >/dev/null)
  if [ -n "$pat_err" ]; then
    echo "match-guidelines: malformed applies_to in $rel: $pat -- treating as always-applicable" >&2
    printf '%s\t%s\talways\n' "$rel" "$prio"
  elif printf '%s\n' "$changed" | grep -qE "$pat"; then
    printf '%s\t%s\tscoped\n' "$rel" "$prio"
  fi
done
