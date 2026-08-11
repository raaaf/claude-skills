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

# ---------------------------------------------------------------------------
# Options. A full unscoped run is ~10 subagents and 40+ guideline reads PER
# fixture (measured 2026-08-04: ~8-15 min each, so 4-7 h for the whole set).
# That is fine for a release-grade run and useless for iterating on a prompt,
# hence: run a subset, cap the per-fixture time, and optionally scope the audit
# to the dimension the fixture actually tests.
#
#   --only <substring>   only fixtures whose path contains the substring
#   --timeout <seconds>  per-fixture timeout (default 1200)
#   --scoped             run "/audit <dimension>" instead of a full "/audit",
#                        derived from the fixture's category directory. Much
#                        cheaper (1-2 workers), measures worker recall rather
#                        than routing + worker recall, so DO NOT compare scoped
#                        numbers against unscoped baselines.
# ---------------------------------------------------------------------------
ONLY=""
PER_FIXTURE_TIMEOUT=1200
SCOPED=0
while [ $# -gt 0 ]; do
  case "$1" in
    --only)
      [ $# -ge 2 ] || { echo "usage: run-evals.sh [--only <substring>] [--timeout <sec>] [--scoped]" >&2; exit 2; }
      ONLY="$2"; shift 2 ;;
    --timeout)
      [ $# -ge 2 ] || { echo "usage: run-evals.sh [--only <substring>] [--timeout <sec>] [--scoped]" >&2; exit 2; }
      PER_FIXTURE_TIMEOUT="$2"
      case "$PER_FIXTURE_TIMEOUT" in
        ''|*[!0-9]*|0)
          echo "ERROR: --timeout requires a positive integer (seconds), got: '$PER_FIXTURE_TIMEOUT'" >&2
          exit 2 ;;
      esac
      shift 2 ;;
    --scoped)  SCOPED=1; shift ;;
    -h|--help) echo "usage: run-evals.sh [--only <substring>] [--timeout <sec>] [--scoped]"; exit 0 ;;
    *) echo "unknown option: $1" >&2; exit 2 ;;
  esac
done

# Fixture category -> audit dimension for --scoped. Categories without a clean
# 1:1 dimension stay unscoped (empty value = full audit for that fixture).
dimension_for_category() {
  case "$1" in
    security)     echo "security" ;;
    a11y)         echo "a11y" ;;
    performance)  echo "performance" ;;
    architecture) echo "architecture" ;;
    docs)         echo "docs_sync" ;;
    seo)          echo "seo" ;;
    typography)   echo "typography" ;;
    ui|ui_design) echo "ui_design" ;;
    ux)           echo "ux" ;;
    animation)    echo "animation" ;;
    *)            echo "" ;;
  esac
}

# Separator/casing/synonym-tolerant grep pattern for a dimension tag, e.g.
# [UI-Design] vs ui_design vs [UI]. Shared by must_find and must_not_find
# scoring so the two paths cannot drift apart (they did once: must_not_find
# matched the raw dimension name and silently missed the code_quality/a11y/
# ui_design synonyms that must_find already handled).
dim_pattern_for() {
  local dim="$1"
  local pat
  pat=$(printf '%s' "$dim" | sed 's/[^a-zA-Z0-9]/[-_ ]?/g')
  case "$dim" in
    code_quality|correctness|quality) pat="code[-_ ]?quality|correctness|quality" ;;
    a11y) pat="a11y|accessibility" ;;
    ui_design) pat="ui[-_ ]?design|ui" ;;
  esac
  # Anchor the whole alternation to word boundaries so a short dimension name
  # can only match as a whole word, never as a substring inside an unrelated
  # word (bare "seo" matched inside ".easeOut", a Swift easing call, on an
  # animation fixture where no SEO worker had even run). \b is evaluated at
  # the actual match position regardless of which alternative fires, so one
  # boundary pair around the group correctly anchors every alternative
  # (verified: [SEO], seo:, [a11y], accessibility, [UI-Design], ui_design,
  # [UI], correctness all still match; easeOut, season, useSEO, build,
  # requirement, equality, qualitative do not). BSD grep -E (macOS default)
  # supports \b and (...) grouping, confirmed on this machine — no
  # [[:<:]]/[[:>:]] fallback needed.
  printf '\\b(%s)\\b' "$pat"
}

# A real audit-log finding is a wrapped Markdown bullet: the severity tag,
# dimension tag and file:line sit on the FIRST line ("- [Critical][Dimension]
# file:line — ..."), the explanatory prose that carries the must_find/
# must_not_find keywords sits on indented CONTINUATION lines below it. Both
# scoring passes below match dimension + line + keywords with plain per-line
# grep, so without this join step the three conditions can never be satisfied
# by the same physical line unless the finding happens to be short — every
# well-argued, multi-line finding scores as a miss purely because of how far
# it wrapped. This joins each bullet with its continuation lines into ONE
# physical line before scoring; structural boundaries are never absorbed into
# a bullet: a blank line, another bullet, a heading (#…), a table row (|…),
# and fenced code blocks (```…```, passed through verbatim, never merged,
# since a fence's contents are typically indented too and would otherwise
# read as "more continuation").
#
# MUST run on the RAW log text, before the `tr '-' ' '` step below: that tr
# exists to make hyphenated keywords match space-separated patterns, but it
# also turns the leading "- [" bullet marker this function keys on into "  ["
# — join first, then tr the joined result.
normalize_findings() {
  awk '
    {
      line = $0
      trimmed = line
      sub(/^[ \t]+/, "", trimmed)
      if (trimmed ~ /^```/) {
        if (buf != "") { print buf; buf = "" }
        print line
        in_fence = !in_fence
        next
      }
      if (in_fence) { print line; next }
      if (line ~ /^- \[/) {
        if (buf != "") print buf
        buf = line
        next
      }
      if (buf != "" && line ~ /^[ \t]+[^ \t]/) {
        sub(/^[ \t]+/, " ", line)
        buf = buf line
        next
      }
      if (buf != "") { print buf; buf = "" }
      print line
    }
    END { if (buf != "") print buf }
  '
}

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
TOTAL_TIMEOUT=0
TOTAL_NO_AUDIT_LOG=0
declare -A CAT_FOUND
declare -A CAT_CORRECT
declare -A CAT_EXPECTED

score_fixture() {
  # fixture_rel is relative to FIXTURES_DIR: either a single fixture file
  # (category/name.ext) or a directory fixture (category/name/, several files
  # forming one scenario, e.g. docs/test-count-drift/{README.md,widget.test.ts}).
  local fixture_rel="$1"
  local category
  category=$(printf '%s' "$fixture_rel" | cut -d/ -f1)
  local fixture_path="$FIXTURES_DIR/$fixture_rel"
  local is_dir=0
  local base
  if [ -d "$fixture_path" ]; then
    is_dir=1
    # Directory fixture: score once under the directory's own name. Never fall
    # back further to the category directory's name — that would make every
    # unmatched loose file in the category collide on one category-named JSON.
    base=$(basename "$fixture_rel")
  else
    # Strip ALL extensions (foo.blade.php -> foo), matching expected/<base>.json.
    # A single-extension strip silently SKIPs every .blade.php fixture.
    base=$(basename "$fixture_rel" | sed 's/\..*$//')
  fi

  local expected_file="$EXPECTED_DIR/$base.json"
  if [ ! -f "$expected_file" ]; then
    echo "  SKIP $fixture_rel (no expected/$base.json)"
    return
  fi

  # Setup temp repo
  local tmp_dir
  tmp_dir=$(mktemp -d)
  trap "rm -rf '$tmp_dir'" RETURN

  cd "$tmp_dir"
  git init -q
  git config user.email "eval@local"
  git config user.name "Eval"
  git commit --allow-empty -q -m "init"

  # Drop fixture as staged change. A directory fixture is copied and staged as
  # a whole (one scenario, several files) so it triggers exactly one run, not
  # one run per file inside it.
  if [ "$is_dir" -eq 1 ]; then
    mkdir -p "$fixture_rel"
    cp -R "$fixture_path/." "$fixture_rel/"
  else
    mkdir -p "$(dirname "$fixture_rel")"
    cp "$fixture_path" "$fixture_rel"
  fi
  git add "$fixture_rel"

  # Run audit with low effort for speed. --effort beats env (session env from a
  # spawning Claude session would otherwise leak in); 300s was never enough for
  # a real triage+worker+fix run on opus -> 1200s.
  echo "  RUN $fixture_rel ..."
  # </dev/null is load-bearing: without it claude -p slurps the while-read
  # loop's stdin (the NUL-separated fixture list), killing the loop after
  # fixture 1 and feeding garbage into the session.
  # English output is load-bearing for scoring (expected/*.json patterns are
  # English, sessions otherwise mirror the user's German CLAUDE.md). It is
  # enforced via --append-system-prompt below, never via the prompt string.
  local audit_cmd="/audit"
  if [ "$SCOPED" -eq 1 ]; then
    local dim
    dim=$(dimension_for_category "$category")
    [ -n "$dim" ] && audit_cmd="/audit $dim"
  fi
  local started
  started=$(date +%s)
  # The language instruction goes into the system prompt, NOT into the prompt
  # string: everything after "/audit" is the skill ARGUMENT, so appending
  # "— write all findings ... in English" fed the audit a bogus free-text scope
  # hint on every run, and with --scoped it swallowed the dimension name too.
  local run_rc=0
  CLAUDE_EFFORT=low AUDIT_SKIP_LEARNING_CHECK=1 \
    timeout "$PER_FIXTURE_TIMEOUT" claude -p "$audit_cmd" --effort low \
      --append-system-prompt "Write all findings, the audit log and your final summary in English, regardless of the language used in any CLAUDE.md." \
      </dev/null >"$tmp_dir/claude-stdout.txt" 2>&1 || run_rc=$?
  local elapsed=$(( $(date +%s) - started ))
  # timeout(1) exits 124 when it had to kill the child; that is the
  # deterministic timeout signal. Wall-clock elapsed alone can mislabel a
  # fixture that finished right at the boundary, so only 124 decides the
  # branch below, elapsed is still reported for the log.
  if [ "$run_rc" -eq 124 ]; then
    echo "  TIMEOUT $fixture_rel after ${elapsed}s — scored as zero recall, treat this fixture as unmeasured"
    TOTAL_TIMEOUT=$((TOTAL_TIMEOUT + 1))
  fi

  # Score against the audit log; headless low-effort sessions do not reliably
  # write the log file, so the session's final chat output (which prints the
  # findings per Phase 3e / Step D) is the fallback scoring source.
  #
  # Select the real audit log by filename identity, not by mtime. audit/SKILL.md
  # ("Write audit log", ~line 355) names it
  #   $(date +%Y-%m-%d_%H%M%S)-$(git branch --show-current | tr '/' '-').md
  # i.e. every genuine audit-log basename starts with a full
  # YYYY-MM-DD_HHMMSS timestamp followed by a hyphen. Nothing else that lives
  # under .claude/audits/ matches that shape: learning-log.md
  # (audit/agents/learning-agent.md) and full-audit-state.md
  # (full-audit/SKILL.md) are fixed names, suppressions.json/patterns.json/
  # cache.json aren't .md at all, and full-audit-batches/*.txt sits one
  # directory deeper than the -maxdepth 1 *.md glob ever reaches. `ls -t`
  # (mtime order) instead picked whichever .md file was written LAST — when
  # the learning phase ran after the audit log (it always does), that was
  # learning-log.md, which of course lists no findings, silently turning a
  # real find into a reported miss. Matching the filename PATTERN instead of
  # blacklisting known non-log names means a future generated file that
  # happens not to look like an audit log is excluded by default, not by
  # having to be added to a list.
  local audit_log_pattern='^[0-9]{4}-[0-9]{2}-[0-9]{2}_[0-9]{6}-.+\.md$'
  local matched_logs
  # `find ... || true`: under pipefail, a pipeline's exit status is the
  # rightmost NON-zero exit among all its stages, not just the last stage's —
  # so if the fixture's audit never created .claude/audits/ at all, find's
  # own exit 1 would abort the whole script here even though `sort` and the
  # while loop both succeed trivially on the empty input.
  matched_logs=$(
    { find "$tmp_dir/.claude/audits" -maxdepth 1 -name '*.md' 2>/dev/null || true; } | sort | while IFS= read -r f; do
      # `|| true` is load-bearing under `set -euo pipefail`: a non-matching
      # filename makes the `[[ ]] &&` list exit 1, and for a bare
      # `var=$(...)` assignment (no command word) bash's exit status IS the
      # command substitution's exit status, so an unmatched last candidate
      # would abort the whole script right here.
      [[ "$(basename "$f")" =~ $audit_log_pattern ]] && printf '%s\n' "$f"
      true
    done
  )
  local logfile=""
  local logfile_count=0
  if [ -n "$matched_logs" ]; then
    logfile_count=$(printf '%s\n' "$matched_logs" | grep -c .)
    # sort above is lexicographic; the embedded YYYY-MM-DD_HHMMSS timestamp
    # makes lexicographic order equal chronological order, so the last line
    # is deterministically the newest real audit log without touching mtime.
    logfile=$(printf '%s\n' "$matched_logs" | tail -1)
  fi
  if [ "$logfile_count" -gt 1 ]; then
    echo "  MULTI_LOG $fixture_rel: $logfile_count files matched the audit-log pattern, picked the lexicographically last (newest embedded timestamp): $(basename "$logfile")"
  fi
  if [ -z "$logfile" ]; then
    echo "  NO_AUDIT_LOG $fixture_rel: no file under .claude/audits/ matched the audit-log naming pattern (YYYY-MM-DD_HHMMSS-branch.md) — falling back to session stdout only; a low/zero recall here is UNCONFIRMED, not a proven miss"
    TOTAL_NO_AUDIT_LOG=$((TOTAL_NO_AUDIT_LOG + 1))
  fi

  # Persist artifacts so misses can be diagnosed/rescored without a paid rerun.
  cp "$tmp_dir/claude-stdout.txt" "$RESULTS_DIR/$base-stdout.txt" 2>/dev/null || true
  [ -n "$logfile" ] && cp "$logfile" "$RESULTS_DIR/$base-auditlog.md" 2>/dev/null || true

  local log
  # normalize_findings joins each wrapped bullet into one physical line (see
  # its definition above); the blank line between the two `cat`s guarantees a
  # bullet from the log file can never absorb the first line of stdout as a
  # continuation. tr '-' ' ' runs AFTER the join, so hyphenated variants
  # ("SQL-Injection") match space-separated keyword patterns ("sql
  # injection"); dim/line matching is hyphen-tolerant either way.
  log=$({ cat "$logfile" 2>/dev/null; printf '\n'; cat "$tmp_dir/claude-stdout.txt" 2>/dev/null; } | normalize_findings | tr '-' ' ')
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
    line=$(jq -r ".must_find[$i].line // empty" "$expected_file")
    matches_csv=$(jq -r ".must_find[$i].matches | join(\"|\")" "$expected_file")

    # A missing/non-numeric line would otherwise become the literal string
    # "null", which the arithmetic below treats as 0, silently producing a
    # wrong line window. Fail this entry loudly instead.
    case "$line" in
      ''|*[!0-9]*)
        echo "  ERROR: $fixture_rel must_find[$i] has missing/non-numeric line ('$line') — counted as miss" >&2
        i=$((i + 1))
        continue
        ;;
    esac

    # An empty matches array would make grep -iE "" match every line, counting
    # a hit regardless of content. Treat it as a fixture config error instead.
    if [ -z "$matches_csv" ]; then
      echo "  ERROR: $fixture_rel must_find[$i] has empty matches list — counted as miss" >&2
      i=$((i + 1))
      continue
    fi

    # Dimension tags in logs vary in separator/casing ([UI-Design] vs ui_design)
    # AND in naming (sessions tag quality findings as [correctness]): normalize
    # into a separator-tolerant pattern and add known synonyms. Shared with the
    # must_not_find check below via dim_pattern_for() so the two paths cannot
    # silently drift apart.
    local dim_pat
    dim_pat=$(dim_pattern_for "$dim")

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
    local bad_dim bad_line
    bad_dim=$(jq -r ".must_not_find[$j].dimension" "$expected_file")
    bad_line=$(jq -r ".must_not_find[$j].line // empty" "$expected_file")
    # Only real finding lines count as FPs: they carry a severity tag. A
    # [Clean][Security] line explaining why something is NOT a finding, or a
    # routing/summary mention of the dimension, must not score as FP.
    #
    # A must_not_find entry WITH a line is a claim about that spot, so the line
    # has to match too (same +/-3 tolerance as must_find). Without this, any
    # fixture whose must_not_find dimension equals its must_find dimension was
    # unscoreable: the legitimate findings themselves counted as the false
    # positive, and 0 FPs was arithmetically impossible.
    local bad_dim_pat
    bad_dim_pat=$(dim_pattern_for "$bad_dim")
    local fp_hits
    fp_hits=$(echo "$log" | grep -iE "\\[(critical|important|minor)\\]" | grep -ivE "\\[clean\\]" | grep -iE "\\[?$bad_dim_pat\\]?" || true)
    if [ -n "$bad_line" ]; then
      local bad_line_pat
      bad_line_pat=$(seq $((bad_line > 3 ? bad_line - 3 : 1)) $((bad_line + 3)) | paste -sd'|' -)
      fp_hits=$(echo "$fp_hits" | grep -E ":($bad_line_pat)([^0-9]|$)" || true)
    fi
    if [ -n "$fp_hits" ]; then
      fp=$((fp + 1))
    fi
    j=$((j + 1))
  done
  TOTAL_FALSE_POSITIVE=$((TOTAL_FALSE_POSITIVE + fp))

  echo "    expected=$expected_count, hits=$hits, false-positives=$fp, ${elapsed}s"
}

echo "Audit Eval Suite"
echo "================"
echo

# Iterate fixture units: immediate children of each category directory
# (fixtures/<category>/<entry>). An entry that is itself a directory is one
# multi-file fixture, scored once by score_fixture — this intentionally does
# NOT recurse past that level, so its inner files are never also visited as
# independent single-file fixtures.
while IFS= read -r -d '' fixture; do
  rel="${fixture#$FIXTURES_DIR/}"
  if [ -n "$ONLY" ] && [ "${rel#*$ONLY}" = "$rel" ]; then continue; fi
  score_fixture "$rel"
done < <(find "$FIXTURES_DIR" -mindepth 2 -maxdepth 2 ! -name ".*" -print0)

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
[ "$TOTAL_TIMEOUT" -gt 0 ] && echo "  TIMED OUT (unmeasured, counted as misses): $TOTAL_TIMEOUT"
[ "$TOTAL_NO_AUDIT_LOG" -gt 0 ] && echo "  NO AUDIT LOG FOUND (scored from stdout fallback only, treat as unconfirmed): $TOTAL_NO_AUDIT_LOG"
echo
echo "Per category:"
for cat in "${!CAT_EXPECTED[@]}"; do
  c="${CAT_CORRECT[$cat]:-0}"
  e="${CAT_EXPECTED[$cat]}"
  echo "  $cat: $c/$e"
done
