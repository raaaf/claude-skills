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
#   bash patterns-store.sh recur --force {pattern} # skip near-duplicate folding, always record as a new/own key
#   bash patterns-store.sh recurrences             # list patterns seen >=2 times, most frequent first
set -euo pipefail

PROJECT_ROOT=$(git rev-parse --show-toplevel 2>/dev/null) || { echo "NOT_A_REPO"; exit 1; }
STORE_DIR="$PROJECT_ROOT/.claude/audits"
STORE="$STORE_DIR/patterns.json"
mkdir -p "$STORE_DIR"
[ -f "$STORE" ] || echo '{"version":1,"fix_patterns":[],"dismissals":{},"recurrences":{}}' > "$STORE"

command -v jq >/dev/null 2>&1 || { echo "jq required"; exit 1; }

# Every subcommand that writes (or looks up) a pattern-keyed entry runs the
# pattern through the same normalization normalize-suppression.sh performs,
# so two differently-worded descriptions of the same issue collapse into one
# key instead of fragmenting the recurrence/dismissal count into twins.
# Canonical keys (already "cat:...|...") pass through unchanged (verified
# idempotent), so existing counters keep incrementing, not forking.
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
NORMALIZE_SCRIPT="$SCRIPT_DIR/normalize-suppression.sh"
normalize_pattern() {
  local p="$1"
  if [ -f "$NORMALIZE_SCRIPT" ]; then
    printf '%s' "$p" | bash "$NORMALIZE_SCRIPT"
  else
    printf '%s' "$p"
  fi
}

# --- Near-duplicate detection (recur only) ---
#
# normalize-suppression.sh only folds formatting variance (case, whitespace,
# a category bracket, stopwords). It cannot fold a REWORDING of the same
# underlying pattern, and a reworded description is exactly what fragmented
# the "audit-owned infrastructure" recurrence into two entries in this
# repo's history (2026-08-05 and again on a later run). Before `recur`
# writes a key that does not already exist verbatim, it compares the new
# pattern's token set against every existing key's token set and folds into
# the best match on strong overlap, instead of silently starting a fresh
# counter that fragments the real count.
#
# Measure: overlap coefficient (|A intersect B| / min(|A|,|B|)) over the
# normalized, tokenized word sets, gated by an absolute floor on the
# intersection size. The coefficient alone is unstable on short strings (two
# 2-token sets sharing 1 token score 0.5), so the floor guards that; the
# coefficient guards long strings that share a few generic words by
# coincidence. Values chosen against real data in this store: the
# "audit-owned infrastructure ... only found incidentally" pair (must merge)
# shares 5 of 8 tokens, coefficient 0.625; the "fix agent self-designed test
# table clean / finds real defect" vs "self-tested-clean, verifier finds
# real bug" pair (must NOT merge, they are near-unrelated wordings sharing
# only "finds"/"real") shares 2 tokens, coefficient 0.4 but below the
# intersection floor; every pair among the four production keys in
# .claude/audits/patterns.json shares 0 tokens. A false merge (two distinct
# patterns collapsed) destroys information and is worse than a missed merge
# (which just reproduces pre-fix behavior), so both thresholds lean strict.
NEARDUP_MIN_OVERLAP_COEFF_X1000=500   # 0.50, integer math (bash has no floats)
NEARDUP_MIN_INTERSECT=3               # absolute floor, ignores coefficient below this

# Tokenize a normalized pattern/key into a sorted, unique, newline-separated
# word list: strip a leading "cat:xxx|" category prefix and any "|" section
# separators, collapse everything that is not a-z/0-9/hyphen into spaces,
# drop tokens under 3 chars (mirrors normalize-suppression.sh's own floor).
tokenize_pattern() {
  local s="$1"
  s=$(printf '%s' "$s" | sed -E 's/^cat:[^|]*\|//')
  s=$(printf '%s' "$s" | tr '|' ' ' | sed -E 's/[^a-z0-9-]+/ /g')
  printf '%s' "$s" | tr -s ' ' '\n' | awk 'length($0) >= 3' | sort -u
}

# Score two normalized strings by overlap coefficient (0-1000 integer
# scale). Echoes "<score_x1000> <intersect_count>" so the caller gets both
# numbers from one tokenize pass each.
overlap_score() {
  local a="$1" b="$2"
  local tokA tokB nA nB inter minN
  tokA=$(tokenize_pattern "$a")
  tokB=$(tokenize_pattern "$b")
  nA=$(printf '%s\n' "$tokA" | grep -c '.' || true)
  nB=$(printf '%s\n' "$tokB" | grep -c '.' || true)
  if [ "$nA" -eq 0 ] || [ "$nB" -eq 0 ]; then
    echo "0 0"
    return
  fi
  inter=$(comm -12 <(printf '%s\n' "$tokA") <(printf '%s\n' "$tokB") | grep -c '.' || true)
  minN=$nA
  [ "$nB" -lt "$minN" ] && minN=$nB
  echo "$(( inter * 1000 / minN )) $inter"
}

# Scan existing .recurrences keys for a near-duplicate of $1 (already
# normalized). Echoes the best matching existing key on stdout if one clears
# both thresholds, nothing otherwise. Picks the highest-scoring match;
# ties keep the first one encountered in stored key order.
find_near_duplicate() {
  local pattern="$1"
  local best_key="" best_score=-1
  local key score inter
  while IFS= read -r key; do
    [ -z "$key" ] && continue
    read -r score inter <<< "$(overlap_score "$pattern" "$key")"
    if [ "$inter" -ge "$NEARDUP_MIN_INTERSECT" ] && [ "$score" -ge "$NEARDUP_MIN_OVERLAP_COEFF_X1000" ]; then
      if [ "$score" -gt "$best_score" ]; then
        best_score=$score
        best_key="$key"
      fi
    fi
  done < <(jq -r '.recurrences | keys_unsorted[]' "$STORE" 2>/dev/null)
  printf '%s' "$best_key"
}

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
    RAW_PATTERN=$(printf '%s' "$INPUT" | jq -r '.pattern // empty')
    if [ -n "$RAW_PATTERN" ]; then
      NORM_PATTERN=$(normalize_pattern "$RAW_PATTERN")
      INPUT=$(printf '%s' "$INPUT" | jq --arg p "$NORM_PATTERN" '.pattern = $p')
    fi
    jq --argjson new "$INPUT" '.fix_patterns += [$new] | .fix_patterns |= unique_by(.pattern)' "$STORE" > "$STORE.new" && mv "$STORE.new" "$STORE"
    ;;
  list)
    jq -c '.fix_patterns[]' "$STORE" 2>/dev/null || true
    ;;
  dismissed)
    PATTERN="${2:-}"
    [ -z "$PATTERN" ] && { echo "pattern required"; exit 1; }
    PATTERN=$(normalize_pattern "$PATTERN")
    jq --arg p "$PATTERN" '.dismissals[$p] = ((.dismissals[$p] // 0) + 1)' "$STORE" > "$STORE.new" && mv "$STORE.new" "$STORE"
    ;;
  recur)
    FORCE=0
    if [ "${2:-}" = "--force" ]; then
      FORCE=1
      PATTERN="${3:-}"
    else
      PATTERN="${2:-}"
    fi
    [ -z "$PATTERN" ] && { echo "pattern required"; exit 1; }
    PATTERN=$(normalize_pattern "$PATTERN")

    TARGET_KEY="$PATTERN"
    EXISTS=$(jq -r --arg p "$PATTERN" 'if (.recurrences | has($p)) then "1" else "0" end' "$STORE")
    if [ "$EXISTS" = "0" ] && [ "$FORCE" -eq 0 ]; then
      MATCH=$(find_near_duplicate "$PATTERN")
      if [ -n "$MATCH" ]; then
        echo "recur: near-duplicate detected, folding into the existing pattern instead of creating a new one (use 'recur --force <pattern>' to record a genuinely distinct pattern that happens to share vocabulary)." >&2
        echo "  passed:  $PATTERN" >&2
        echo "  matched: $MATCH" >&2
        TARGET_KEY="$MATCH"
      fi
    fi

    jq --arg p "$TARGET_KEY" '.recurrences[$p] = ((.recurrences[$p] // 0) + 1)' "$STORE" > "$STORE.new" && mv "$STORE.new" "$STORE"
    jq -r --arg p "$TARGET_KEY" '.recurrences[$p]' "$STORE"
    ;;
  recurrences)
    # Nur was mindestens zweimal auftrat, haeufigste zuerst. Einmalige Findings
    # sind Rauschen; ab zwei wird es ein Muster, das eine Guideline verdient.
    jq -r '.recurrences | to_entries | map(select(.value >= 2)) | sort_by(-.value) | .[] | "\(.value)x \(.key)"' "$STORE" 2>/dev/null || true
    ;;
  should-suggest)
    PATTERN="${2:-}"
    [ -z "$PATTERN" ] && { echo "pattern required"; exit 1; }
    PATTERN=$(normalize_pattern "$PATTERN")
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
