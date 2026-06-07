#!/usr/bin/env bash
#
# run-evals.sh — Score /audit against the eval fixtures.
#
# For each fixture under audit/evals/fixtures/<category>/<name>.<ext>:
#   1. Create a tmp git repo
#   2. Drop the fixture as a staged change
#   3. Run /audit (via CLAUDE_EFFORT=low for speed)
#   4. Parse the audit-log markdown
#   5. Score against audit/evals/expected/<name>.json
#
# Output: per-fixture pass/fail + aggregate precision/recall per category.
#
# NOTE: This is a scaffold. It uses pattern-match scoring on finding
# descriptions, which is fragile. A proper eval would compare structured
# finding objects against the expected JSON with stricter field checks.

set -euo pipefail

EVALS_DIR="$(cd "$(dirname "$0")" && pwd)"
FIXTURES_DIR="$EVALS_DIR/fixtures"
EXPECTED_DIR="$EVALS_DIR/expected"

if [ ! -d "$FIXTURES_DIR" ] || [ ! -d "$EXPECTED_DIR" ]; then
  echo "ERROR: fixtures/ or expected/ missing under $EVALS_DIR"
  exit 1
fi

# Check claude CLI available
if ! command -v claude >/dev/null 2>&1; then
  echo "ERROR: 'claude' CLI not found. Eval runner requires non-interactive Claude Code."
  exit 1
fi

TOTAL_EXPECTED=0
TOTAL_FOUND=0
TOTAL_CORRECT=0
TOTAL_FALSE_POSITIVE=0
declare -A CAT_FOUND
declare -A CAT_CORRECT
declare -A CAT_EXPECTED

score_fixture() {
  local fixture_rel="$1"
  local category
  category=$(dirname "$fixture_rel")
  local base
  base=$(basename "$fixture_rel" | sed 's/\.[^.]*$//')

  local expected_file="$EXPECTED_DIR/$base.json"
  if [ ! -f "$expected_file" ]; then
    echo "  SKIP $fixture_rel (no expected/$base.json)"
    return
  fi

  local fixture_path="$FIXTURES_DIR/$fixture_rel"

  # Setup temp repo
  local tmp_dir
  tmp_dir=$(mktemp -d)
  trap "rm -rf '$tmp_dir'" RETURN

  cd "$tmp_dir"
  git init -q
  git config user.email "eval@local"
  git config user.name "Eval"
  git commit --allow-empty -q -m "init"

  # Drop fixture as staged change
  mkdir -p "$(dirname "$fixture_rel")"
  cp "$fixture_path" "$fixture_rel"
  git add "$fixture_rel"

  # Run audit with low effort for speed
  echo "  RUN $fixture_rel ..."
  CLAUDE_EFFORT=low AUDIT_SKIP_LEARNING_CHECK=1 \
    timeout 300 claude -p "/audit" >/dev/null 2>&1 || true

  # Find latest audit log
  local logfile
  logfile=$(ls -t "$tmp_dir/.claude/audits/"*.md 2>/dev/null | head -1 || true)
  if [ -z "$logfile" ]; then
    echo "  FAIL $fixture_rel: no audit log produced"
    return
  fi

  local log
  log=$(cat "$logfile")

  # Parse expected
  local expected_count
  expected_count=$(jq '.must_find | length' "$expected_file")
  TOTAL_EXPECTED=$((TOTAL_EXPECTED + expected_count))
  CAT_EXPECTED[$category]=$(( ${CAT_EXPECTED[$category]:-0} + expected_count ))

  local hits=0
  local i=0
  while [ "$i" -lt "$expected_count" ]; do
    local dim line matches_csv
    dim=$(jq -r ".must_find[$i].dimension" "$expected_file")
    line=$(jq -r ".must_find[$i].line" "$expected_file")
    matches_csv=$(jq -r ".must_find[$i].matches | join(\"|\")" "$expected_file")

    if echo "$log" | grep -iE "\\[?$dim\\]?" | grep -E ":$line" | grep -iE "$matches_csv" >/dev/null 2>&1; then
      hits=$((hits + 1))
    fi
    i=$((i + 1))
  done

  TOTAL_FOUND=$((TOTAL_FOUND + hits))
  TOTAL_CORRECT=$((TOTAL_CORRECT + hits))
  CAT_FOUND[$category]=$(( ${CAT_FOUND[$category]:-0} + hits ))
  CAT_CORRECT[$category]=$(( ${CAT_CORRECT[$category]:-0} + hits ))

  # Check must_not_find
  local fp=0
  local fp_count
  fp_count=$(jq '.must_not_find | length' "$expected_file")
  local j=0
  while [ "$j" -lt "$fp_count" ]; do
    local bad_dim
    bad_dim=$(jq -r ".must_not_find[$j].dimension" "$expected_file")
    if echo "$log" | grep -iE "\\[$bad_dim\\]" >/dev/null 2>&1; then
      fp=$((fp + 1))
    fi
    j=$((j + 1))
  done
  TOTAL_FALSE_POSITIVE=$((TOTAL_FALSE_POSITIVE + fp))

  echo "    expected=$expected_count, hits=$hits, false-positives=$fp"
}

echo "Audit Eval Suite"
echo "================"
echo

# Iterate fixtures
while IFS= read -r -d '' fixture; do
  rel="${fixture#$FIXTURES_DIR/}"
  score_fixture "$rel"
done < <(find "$FIXTURES_DIR" -type f \( -name "*.php" -o -name "*.blade.php" -o -name "*.tsx" -o -name "*.vue" \) -print0)

echo
echo "Summary"
echo "-------"
if [ "$TOTAL_EXPECTED" -gt 0 ]; then
  recall=$(awk -v c="$TOTAL_CORRECT" -v e="$TOTAL_EXPECTED" 'BEGIN { printf "%.0f", (c/e)*100 }')
  echo "  Recall:    $TOTAL_CORRECT/$TOTAL_EXPECTED ($recall%)"
else
  echo "  Recall:    no expected findings configured"
fi
echo "  False-positives: $TOTAL_FALSE_POSITIVE"
echo
echo "Per category:"
for cat in "${!CAT_EXPECTED[@]}"; do
  c="${CAT_CORRECT[$cat]:-0}"
  e="${CAT_EXPECTED[$cat]}"
  echo "  $cat: $c/$e"
done
