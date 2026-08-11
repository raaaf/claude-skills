#!/usr/bin/env bash
#
# Learning-Loop: stores fix patterns across audit runs. Reads JSON from stdin
# and merges it into .claude/audits/patterns.json.
#
# Also tracks repeatedly-dismissed findings for suppression suggestions.
#
# Usage:
#   echo '{"type":"fix","dimension":"security","pattern":"raw query","fix":"use prepared statement"}' \
#     | bash patterns-store.sh add
#   bash patterns-store.sh list                    # show all learned patterns
#   bash patterns-store.sh dismissed {pattern}     # increment dismiss counter
#   bash patterns-store.sh should-suggest {pattern} # exit 0 if >=3 dismissals
#   bash patterns-store.sh recur {pattern}         # count this finding pattern, echoes new count
#   bash patterns-store.sh recurrences             # list patterns seen >=2 times, most frequent first
set -euo pipefail

PROJECT_ROOT=$(git rev-parse --show-toplevel 2>/dev/null) || { echo "NOT_A_REPO"; exit 1; }
STORE_DIR="$PROJECT_ROOT/.claude/audits"
STORE="$STORE_DIR/patterns.json"
mkdir -p "$STORE_DIR"
[ -f "$STORE" ] || echo '{"version":1,"fix_patterns":[],"dismissals":{},"recurrences":{}}' > "$STORE"

command -v jq >/dev/null 2>&1 || { echo "jq required"; exit 1; }

# Migrate stores written before the recurrence counter existed.
jq -e '.recurrences' "$STORE" >/dev/null 2>&1 || {
  jq '.recurrences = {}' "$STORE" > "$STORE.new" && mv "$STORE.new" "$STORE"
}

CMD="${1:-list}"

trap 'rm -f "$STORE.new"' EXIT

case "$CMD" in
  add)
    INPUT=$(cat)
    [ -z "$INPUT" ] && exit 0
    printf '%s' "$INPUT" | jq -e . >/dev/null 2>&1 || { echo "add: malformed JSON on stdin, nothing written" >&2; exit 1; }
    jq --argjson new "$INPUT" '.fix_patterns += [$new] | .fix_patterns |= unique_by(.pattern)' "$STORE" > "$STORE.new" && mv "$STORE.new" "$STORE"
    ;;
  list)
    jq -c '.fix_patterns[]' "$STORE" 2>/dev/null || true
    ;;
  dismissed)
    PATTERN="${2:-}"
    [ -z "$PATTERN" ] && { echo "pattern required"; exit 1; }
    jq --arg p "$PATTERN" '.dismissals[$p] = ((.dismissals[$p] // 0) + 1)' "$STORE" > "$STORE.new" && mv "$STORE.new" "$STORE"
    ;;
  recur)
    PATTERN="${2:-}"
    [ -z "$PATTERN" ] && { echo "pattern required"; exit 1; }
    jq --arg p "$PATTERN" '.recurrences[$p] = ((.recurrences[$p] // 0) + 1)' "$STORE" > "$STORE.new" && mv "$STORE.new" "$STORE"
    jq -r --arg p "$PATTERN" '.recurrences[$p]' "$STORE"
    ;;
  recurrences)
    # Nur was mindestens zweimal auftrat, haeufigste zuerst. Einmalige Findings
    # sind Rauschen; ab zwei wird es ein Muster, das eine Guideline verdient.
    jq -r '.recurrences | to_entries | map(select(.value >= 2)) | sort_by(-.value) | .[] | "\(.value)x \(.key)"' "$STORE" 2>/dev/null || true
    ;;
  should-suggest)
    PATTERN="${2:-}"
    [ -z "$PATTERN" ] && { echo "pattern required"; exit 1; }
    COUNT=$(jq -r --arg p "$PATTERN" '.dismissals[$p] // 0' "$STORE")
    [ "$COUNT" -ge 3 ] && exit 0 || exit 1
    ;;
  *)
    echo "unknown command: $CMD"
    exit 1
    ;;
esac

# Ensure .gitignore entry exists (only on add, not every call)
if [ "$CMD" = "add" ]; then
  grep -qF '.claude/audits/patterns.json' "$PROJECT_ROOT/.gitignore" 2>/dev/null || printf '\n.claude/audits/patterns.json\n' >> "$PROJECT_ROOT/.gitignore"
fi
