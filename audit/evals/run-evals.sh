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
#
# Dev-only tool: runs on the developer's machine, never invoked by the
# orchestrator. Requires bash 4+ (declare -A) — exempt from the bash 3.2
# rule that applies to audit/bin/. macOS: run via `brew install bash`.

set -euo pipefail

EVALS_DIR="$(cd "$(dirname "$0")" && pwd)"
FIXTURES_DIR="$EVALS_DIR/fixtures"
EXPECTED_DIR="$EVALS_DIR/expected"

if [ ! -d "$FIXTURES_DIR" ] || [ ! -d "$EXPECTED_DIR" ]; then
  echo "ERROR: fixtures/ or expected/ missing under $EVALS_DIR"
  exit 1
fi

# Per-run artifact dir (gitignored via results/): session stdout + audit log
# per fixture, for post-hoc diagnosis and rescoring without paid reruns.
RESULTS_DIR="$EVALS_DIR/results/$(date +%Y-%m-%d_%H%M%S)"
mkdir -p "$RESULTS_DIR"
echo "Artifacts: $RESULTS_DIR"

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
  # Strip ALL extensions (foo.blade.php -> foo), matching expected/<base>.json.
  # A single-extension strip silently SKIPs every .blade.php fixture.
  base=$(basename "$fixture_rel" | sed 's/\..*$//')

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

  # Run audit with low effort for speed. --effort beats env (session env from a
  # spawning Claude session would otherwise leak in); 300s was never enough for
  # a real triage+worker+fix run on opus -> 1200s.
  echo "  RUN $fixture_rel ..."
  # </dev/null is load-bearing: without it claude -p slurps the while-read
  # loop's stdin (the NUL-separated fixture list), killing the loop after
  # fixture 1 and feeding garbage into the session.
  # The English instruction is load-bearing for scoring: sessions otherwise
  # mirror the user's CLAUDE.md language (German) and the expected/*.json
  # keyword patterns are English.
  CLAUDE_EFFORT=low AUDIT_SKIP_LEARNING_CHECK=1 \
    timeout 1200 claude -p "/audit — write all findings, the audit log and your final summary in English" --effort low </dev/null >"$tmp_dir/claude-stdout.txt" 2>&1 || true

  # Score against the audit log; headless low-effort sessions do not reliably
  # write the log file, so the session's final chat output (which prints the
  # findings per Phase 3e / Step D) is the fallback scoring source.
  local logfile
  logfile=$(ls -t "$tmp_dir/.claude/audits/"*.md 2>/dev/null | head -1 || true)

  # Persist artifacts so misses can be diagnosed/rescored without a paid rerun.
  cp "$tmp_dir/claude-stdout.txt" "$RESULTS_DIR/$base-stdout.txt" 2>/dev/null || true
  [ -n "$logfile" ] && cp "$logfile" "$RESULTS_DIR/$base-auditlog.md" 2>/dev/null || true

  local log
  # tr '-' ' ' so hyphenated variants ("SQL-Injection") match space-separated
  # keyword patterns ("sql injection"); dim/line matching is hyphen-tolerant.
  log=$({ cat "$logfile" 2>/dev/null; cat "$tmp_dir/claude-stdout.txt" 2>/dev/null; } | tr '-' ' ')
  if [ -z "$log" ]; then
    echo "  FAIL $fixture_rel: no audit log and no session output"
    return
  fi

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

    # Dimension tags in logs vary in separator/casing ([UI-Design] vs ui_design):
    # normalize expected dim into a separator-tolerant pattern.
    local dim_pat
    dim_pat=$(printf '%s' "$dim" | sed 's/[^a-zA-Z0-9]/[-_ ]?/g')

    # Line numbers drift by a few lines between model judgment and fixture
    # ground truth (observed off-by-one on sqli-laravel): accept +/-3.
    local line_pat
    line_pat=$(seq $((line > 3 ? line - 3 : 1)) $((line + 3)) | paste -sd'|' -)

    if echo "$log" | grep -iE "\\[?$dim_pat\\]?" | grep -E ":($line_pat)([^0-9]|$)" | grep -iE "$matches_csv" >/dev/null 2>&1; then
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
done < <(find "$FIXTURES_DIR" -type f ! -name ".*" -print0)

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
