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
#   --validate-only      run validate_expected() over every expected/*.json and
#                        exit — no fixture runs, no model calls, no cost. Seconds
#                        instead of hours. Prints a summary of errors/warnings by
#                        class. See validate_expected() for what it checks.
#   --recheck <dir>      re-run the scorer-gap tripwire (see score_against_log)
#                        over a stored results/<timestamp>/ directory, reading
#                        its *-auditlog.md / *-stdout.txt artifacts. No fixture
#                        runs, no model calls, no cost.
# ---------------------------------------------------------------------------
ONLY=""
PER_FIXTURE_TIMEOUT=1200
SCOPED=0
VALIDATE_ONLY=0
RECHECK_DIR=""
USAGE="usage: run-evals.sh [--only <substring>] [--timeout <sec>] [--scoped] [--validate-only] [--recheck <dir>]"
while [ $# -gt 0 ]; do
  case "$1" in
    --only)
      [ $# -ge 2 ] || { echo "$USAGE" >&2; exit 2; }
      ONLY="$2"; shift 2 ;;
    --timeout)
      [ $# -ge 2 ] || { echo "$USAGE" >&2; exit 2; }
      PER_FIXTURE_TIMEOUT="$2"
      case "$PER_FIXTURE_TIMEOUT" in
        ''|*[!0-9]*|0)
          echo "ERROR: --timeout requires a positive integer (seconds), got: '$PER_FIXTURE_TIMEOUT'" >&2
          exit 2 ;;
      esac
      shift 2 ;;
    --scoped)         SCOPED=1; shift ;;
    --validate-only)  VALIDATE_ONLY=1; shift ;;
    --recheck)
      [ $# -ge 2 ] || { echo "$USAGE" >&2; exit 2; }
      RECHECK_DIR="$2"; shift 2 ;;
    -h|--help) echo "$USAGE"; exit 0 ;;
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
    # `quality` and `copy` map to real dimensions and were simply missing here, so
    # --scoped silently fell through to a full unscoped audit for all 13 of those
    # fixtures: roughly ten times the agents and cost per fixture, for a run the
    # caller asked to be scoped. `correctness` and `reliability` stay unmapped on
    # purpose, they span several dimensions and have no single right answer.
    quality)      echo "code_quality" ;;
    copy)         echo "copy" ;;
    docs)         echo "docs_sync" ;;
    payments)     echo "payments" ;;
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

# Line-window match shared by must_find and must_not_find. A bounded regex
# alternation of individual line numbers (the old `seq ... | paste -sd'|'`
# approach) can only ever match a SINGLE cited number, so a finding cited as
# a range (e.g. "file.js:10-18", which audits write routinely) was compared
# against the window by its first digits only and silently missed whenever
# the first number of a real range fell outside the window even though the
# range covers it. This instead parses the digits (or digit range) right
# after each colon in the piped-in lines and does the numeric overlap check
# directly: a cited value/range counts when it overlaps [lo, hi], not only
# when a single number falls inside it.
#
# The range separator is matched as "-" OR a run of whitespace: callers pipe
# in $log, which has already gone through `tr '-' ' '` (see below) for
# keyword hyphen-tolerance, so a source citation like "file.js:10-18" has
# already become "file.js:10 18" by the time it gets here — the hyphen
# itself is gone. Space is the only delimiter this function ever actually
# sees for a real range in practice; matching literal "-" too costs nothing
# and only matters if a caller ever passes in pre-tr text.
#
# Reads finding lines from stdin, prints the ones that overlap (any output
# means "found").
line_window_match() {
  local lo="$1" hi="$2"
  awk -F: -v lo="$lo" -v hi="$hi" '
    {
      for (i = 2; i <= NF; i++) {
        if (match($i, /^[0-9]+([ \t]+[0-9]+|-[0-9]+)?/)) {
          s = substr($i, RSTART, RLENGTH)
          n = split(s, p, /[ \t-]+/)
          a = p[1] + 0
          b = (n > 1 ? p[2] + 0 : a)
          if (a <= hi && b >= lo) { print; next }
        }
      }
    }
  '
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
#
# Contract vs. safety net: the ONLY sanctioned finding-line shape is
# "- [Severity][Dimension] file:line: description" on ONE physical line, per
# audit/references/audit-log-template.md and audit/SKILL.md Phase 4. Real
# sessions have drifted from it anyway (2026-09-10: four eval runs wrote
# "- **<dim>-<n>-<n> — Severity — ...**" with file:line and description on
# indented continuation lines instead), and every finding in that shape then
# scored zero recall because dimension/line/keyword can never be satisfied on
# one grepped line. The second branch below recognizes that drifted shape too
# so such a log is still scored — this is a safety net for logs that already
# exist or slip again, NOT a licence to keep writing it: the contract stays
# the rule, fix the SKILL/template violation instead of relying on this.
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
      if (line ~ /^- \*\*[a-z_]+-[0-9]+-[0-9]+ .*(Critical|Important|Minor)/) {
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

# Remove findings the audit pipeline itself rejected before the false-positive
# check ever sees them: a [Severity][Dimension] line under a "## Discarded"
# section, or one carrying an explicit refutation marker on its own physical
# line, is the verification stage working as designed (CONFIRMED -> fixed,
# REFUTED -> discarded, per audit/references/audit-log-template.md), not a
# false positive of the audit. Scoring it as one penalizes the pipeline for
# catching its own mistake (2026-09-12: a [Minor][security] line explicitly
# marked "Discarded as out of scope" in advisory-landing-hero-auditlog.md
# counted as a false positive).
#
# Bounded deliberately narrow so a genuine false positive is never swallowed:
# - Section-based: only lines between a bare "## Discarded" heading and the
#   next "## " heading are dropped, mirroring the parsed-contract section
#   from audit/references/audit-log-template.md, never any other heading
#   (a real finding under "## Findings per Dimension" is untouched even if
#   its prose happens to contain one of the marker words below).
# - Marker-based fallback (for drifted logs that inline the verdict instead
#   of using the section, or a --recheck artifact from before the section was
#   adopted): a line is also dropped if it contains "REFUTED", "discarded as
#   ", "discarded," or "discard:" (case-insensitive) — the exact vocabulary
#   audit-log-template.md defines for a discarded/refuted finding, per
#   audit/SKILL.md's CONFIRMED/REFUTED/UNCERTAIN decision procedure.
# - Deliberately NOT a marker: "Minor" severity, "low confidence", or "never
#   fixed" alone. Every logged Minor finding reads "never fixed" by policy
#   (Minor is never fixed, always logged — audit/SKILL.md), so treating that
#   phrase alone as a discard signal would silently exempt every real Minor
#   false positive from ever being counted.
strip_discarded_findings() {
  awk '
    /^## / {
      in_discarded = ($0 ~ /^## Discarded[ \t]*$/) ? 1 : 0
      next
    }
    in_discarded { next }
    { print }
  ' | grep -viE 'refuted|discarded as |discarded,|discard:'
}

if [ ! -d "$FIXTURES_DIR" ] || [ ! -d "$EXPECTED_DIR" ]; then
  echo "ERROR: fixtures/ or expected/ missing under $EVALS_DIR"
  exit 1
fi

# Canonical dimension ids, single-sourced from find.js's ALL_DIMENSIONS (never
# duplicated here as a second literal list). dim_pattern_for() above hard-codes
# exactly two non-canonical synonyms as deliberate, working aliases ("quality"
# and "correctness" both resolve to the code_quality pattern) — verified by
# actually calling dim_pattern_for and grep-matching its output against a real
# "[code_quality]" tag, so these two are accepted alongside the 14 canonical
# ids. Every other non-canonical spelling found while building this check
# (docs, ui, code-quality, architecture|quality) was verified the same way to
# either fail outright or only accidentally succeed against a real tag, so
# anything outside this set is flagged.
FIND_JS="$EVALS_DIR/../workflows/find.js"
if [ -f "$FIND_JS" ]; then
  ALL_DIMENSIONS_LIST=$(awk '/^const ALL_DIMENSIONS = \[/,/\];/' "$FIND_JS" | grep -oE "'[a-zA-Z0-9_]+'" | tr -d "'")
else
  ALL_DIMENSIONS_LIST=""
fi
KNOWN_DIMENSIONS="$ALL_DIMENSIONS_LIST
quality
correctness"

# A must_not_find entry without a `line` degrades to "any finding in this
# dimension is a false positive" (see the must_not_find scoring loop below).
# That is only sound when the entry's dimension differs from every must_find
# dimension in the same file; when it matches, the fixture's own legitimate
# must_find hits count as false positives and 0 FPs becomes arithmetically
# impossible (2026-09-10 incident: 3 of 8 measured security FPs were exactly
# this). Same-dimension + no line is therefore a hard error, not a warning —
# there is no legitimate reason for it. Different-dimension + no line is
# still surfaced as a warning: it is sometimes intentional (a truly
# dimension-wide "nothing here belongs in category X" claim) but is
# indistinguishable from a forgotten line, so the author must see it.
#
# validate_expected() also catches five more drift classes, each grounded in
# how score_fixture actually matches (re-verify the mechanism before trusting
# these comments if score_fixture changes):
#
# - Window collision: a must_find and a must_not_find in the SAME dimension of
#   the SAME fixture whose lines are 3 or fewer apart makes the fixture
#   unscoreable in one direction. Derived directly from score_fixture's actual
#   mechanism: the must_not_find false-positive check builds a window
#   [bad_line-3, bad_line+3] and flags any finding CITING A LINE inside it, so
#   a legitimate must_find at line F is wrongly counted as a false positive
#   exactly when F falls in that window, i.e. when the gap between F and the
#   must_not_find line is <= 3. A gap of 4-6 only makes the two +/-3 windows
#   touch as ranges; no single cited line can land in both, so it is harmless
#   and must NOT be flagged. Do not re-widen this to "windows overlap" (gap <
#   7) — that flags gaps of 4-6 that never actually collide. Hard error
#   (known instance: export-import-roundtrip.json, 88 vs 89).
# - Line out of range: a cited `line` (or any anchor in `lines`) that is <=0
#   or past the end of the fixture file. Only checked when `fixture` names a
#   single file that resolves; directory fixtures are skipped rather than
#   guessed at.
# - Both `line` and `lines` present on one must_find entry: ambiguous about
#   which anchor(s) apply, hard error. A must_find entry uses exactly one of
#   the two fields; the window-collision check above folds every anchor in
#   `lines` into the same check as a single `line`, so a collision on any one
#   of them still gets caught.
# - Missing fixture: `fixture` points at a path that does not exist under
#   fixtures/.
# - Unknown dimension: a `dimension` outside KNOWN_DIMENSIONS above.
# - Unknown severity: a must_find `severity` other than critical/important/
#   minor, case-insensitive.
# - Keyword that can never match: score_fixture pipes the log through
#   `tr '-' ' '` before grepping, so a hyphenated keyword can never match.
#   Warning per such keyword (a sibling keyword in the same entry can still
#   match); escalated to a hard error only when EVERY keyword of one
#   must_find entry is hyphenated, since that entry is then unsatisfiable
#   regardless of what the audit finds.
#
# A malformed expected/*.json invalidates only the fixture it belongs to, not
# the whole suite: every ERROR below (not WARNING) also records that file's
# basename without .json (matching the `base` score_fixture pairs a fixture
# against) into the global INVALID_EXPECTED map, with the reason class(es)
# that triggered it. --validate-only still aborts here (see the exit at the
# bottom of this function), since that mode exists to fail loudly in a
# pre-commit/CI context; a normal run consults the map instead to skip just
# those fixtures while still measuring everything else.
declare -A INVALID_EXPECTED
validate_expected() {
  local bad=0
  local f
  # Summary counters, printed by class at the end (also the --validate-only
  # output).
  local c_mnf_error=0 c_mnf_warning=0 c_window=0 c_range=0 c_missing_fixture=0
  local c_unknown_dim=0 c_unknown_sev=0 c_hyphen_warn=0 c_hyphen_error=0
  local c_invalid_files=0 c_both_line_fields=0
  for f in "$EXPECTED_DIR"/*.json; do
    [ -f "$f" ] || continue
    local name
    name=$(basename "$f")
    local key="${name%.json}"
    local file_bad=0 file_reasons=""

    # --- must_not_find without a line, same dimension as a must_find -------
    local fp_count
    fp_count=$(jq '.must_not_find | length' "$f")
    local j=0
    while [ "$j" -lt "$fp_count" ]; do
      local bad_line bad_dim
      bad_line=$(jq -r ".must_not_find[$j].line // empty" "$f")
      if [ -z "$bad_line" ]; then
        bad_dim=$(jq -r ".must_not_find[$j].dimension" "$f")
        if jq -e --arg d "$bad_dim" '[.must_find[].dimension] | index($d) != null' "$f" >/dev/null; then
          echo "ERROR: expected/$name must_not_find[$j] (dimension '$bad_dim') has no line and shares its dimension with a must_find entry — the check degrades to dimension-wide and the fixture's own correct hit(s) would count as false positives, making 0 FPs impossible. Add a line." >&2
          bad=1
          file_bad=1; file_reasons="$file_reasons,must_not_find missing line"
          c_mnf_error=$((c_mnf_error + 1))
        else
          echo "WARNING: expected/$name must_not_find[$j] (dimension '$bad_dim') has no line — the check degrades to 'any finding in this dimension is a false positive'. If that is not deliberate, add a line." >&2
          c_mnf_warning=$((c_mnf_warning + 1))
        fi
      fi
      j=$((j + 1))
    done

    # --- fixture field: resolvable, and whether it names a single file -----
    local fixture_field fixture_abs fixture_is_file=0 fixture_line_count=0
    fixture_field=$(jq -r '.fixture' "$f")
    fixture_abs="$FIXTURES_DIR/$fixture_field"
    if [ ! -e "$fixture_abs" ]; then
      echo "ERROR: expected/$name fixture '$fixture_field' does not exist under fixtures/." >&2
      bad=1
      file_bad=1; file_reasons="$file_reasons,missing fixture"
      c_missing_fixture=$((c_missing_fixture + 1))
    elif [ -f "$fixture_abs" ]; then
      fixture_is_file=1
      fixture_line_count=$(wc -l < "$fixture_abs" | tr -d ' ')
    fi
    # else: directory fixture — line-range check below is skipped for it.

    # --- window collision: must_find vs must_not_find, same dimension ------
    local collisions
    collisions=$(jq -c '
      [.must_find[]? | . as $e
        | (((if $e.line != null then [$e.line] else [] end)
            + (if $e.lines != null then $e.lines else [] end))[]) as $ln
        | {dim: $e.dimension, line: $ln}] as $mf
      | [.must_not_find[]? | select(.line != null) | {dim: .dimension, line: .line}] as $mnf
      | [ $mf[] as $a | $mnf[] as $b
          | select($a.dim == $b.dim and (($a.line - $b.line) | if . < 0 then -. else . end) <= 3)
          | {dim: $a.dim, must_find_line: $a.line, must_not_find_line: $b.line} ]
      | .[]
    ' "$f")
    if [ -n "$collisions" ]; then
      while IFS= read -r c; do
        [ -z "$c" ] && continue
        local cdim cmf cmnf cgap
        cdim=$(echo "$c" | jq -r '.dim')
        cmf=$(echo "$c" | jq -r '.must_find_line')
        cmnf=$(echo "$c" | jq -r '.must_not_find_line')
        cgap=$((cmf > cmnf ? cmf - cmnf : cmnf - cmf))
        echo "ERROR: expected/$name dimension '$cdim' has must_find line $cmf and must_not_find line $cmnf, $cgap line(s) apart — the must_find line falls inside the must_not_find's +/-3 false-positive window, making the fixture unscoreable in one direction." >&2
        bad=1
        file_bad=1; file_reasons="$file_reasons,window collision"
        c_window=$((c_window + 1))
      done <<< "$collisions"
    fi

    # --- per must_find entry: severity, dimension, line range, keywords ----
    local mf_count
    mf_count=$(jq '.must_find | length' "$f")
    local i=0
    while [ "$i" -lt "$mf_count" ]; do
      local dim sev line
      dim=$(jq -r ".must_find[$i].dimension" "$f")
      sev=$(jq -r ".must_find[$i].severity // empty" "$f")
      line=$(jq -r ".must_find[$i].line // empty" "$f")

      if [ -n "$sev" ]; then
        case "$(printf '%s' "$sev" | tr '[:upper:]' '[:lower:]')" in
          critical|important|minor) ;;
          *)
            echo "ERROR: expected/$name must_find[$i] has unknown severity '$sev' (expected critical, important or minor)." >&2
            bad=1
            file_bad=1; file_reasons="$file_reasons,unknown severity"
            c_unknown_sev=$((c_unknown_sev + 1)) ;;
        esac
      fi

      if [ -n "$dim" ] && ! grep -qxF "$dim" <<< "$KNOWN_DIMENSIONS"; then
        echo "ERROR: expected/$name must_find[$i] has unknown dimension '$dim' (not one of find.js's ALL_DIMENSIONS or the documented quality/correctness aliases)." >&2
        bad=1
        file_bad=1; file_reasons="$file_reasons,unknown dimension"
        c_unknown_dim=$((c_unknown_dim + 1))
      fi

      local has_lines
      has_lines=$(jq -r ".must_find[$i].lines != null" "$f")
      if [ -n "$line" ] && [ "$has_lines" = "true" ]; then
        echo "ERROR: expected/$name must_find[$i] has both 'line' and 'lines' — ambiguous, use only one." >&2
        bad=1
        file_bad=1; file_reasons="$file_reasons,both line and lines"
        c_both_line_fields=$((c_both_line_fields + 1))
      fi

      if [ -n "$line" ] && [ "$fixture_is_file" -eq 1 ]; then
        if [ "$line" -le 0 ] 2>/dev/null || [ "$line" -gt "$fixture_line_count" ] 2>/dev/null; then
          echo "ERROR: expected/$name must_find[$i] cites line $line but $fixture_field has $fixture_line_count lines." >&2
          bad=1
          file_bad=1; file_reasons="$file_reasons,line out of range"
          c_range=$((c_range + 1))
        fi
      fi

      if [ "$has_lines" = "true" ] && [ "$fixture_is_file" -eq 1 ]; then
        local lines_count li lval
        lines_count=$(jq ".must_find[$i].lines | length" "$f")
        li=0
        while [ "$li" -lt "$lines_count" ]; do
          lval=$(jq -r ".must_find[$i].lines[$li]" "$f")
          if [ "$lval" -le 0 ] 2>/dev/null || [ "$lval" -gt "$fixture_line_count" ] 2>/dev/null; then
            echo "ERROR: expected/$name must_find[$i].lines[$li] cites line $lval but $fixture_field has $fixture_line_count lines." >&2
            bad=1
            file_bad=1; file_reasons="$file_reasons,line out of range"
            c_range=$((c_range + 1))
          fi
          li=$((li + 1))
        done
      fi

      local kw_count dead_count
      kw_count=$(jq ".must_find[$i].matches | length" "$f")
      dead_count=0
      local k=0
      while [ "$k" -lt "$kw_count" ]; do
        local kw
        kw=$(jq -r ".must_find[$i].matches[$k]" "$f")
        case "$kw" in
          *-*)
            echo "WARNING: expected/$name must_find[$i].matches[$k] '$kw' contains a hyphen — score_fixture runs the log through tr '-' ' ' before matching, so this keyword can never match. Write it space-separated." >&2
            c_hyphen_warn=$((c_hyphen_warn + 1))
            dead_count=$((dead_count + 1)) ;;
        esac
        k=$((k + 1))
      done
      if [ "$kw_count" -gt 0 ] && [ "$dead_count" -eq "$kw_count" ]; then
        echo "ERROR: expected/$name must_find[$i] has every keyword hyphenated — this entry can never match after tr '-' ' ', not just a weakened one." >&2
        bad=1
        file_bad=1; file_reasons="$file_reasons,all keywords hyphenated"
        c_hyphen_error=$((c_hyphen_error + 1))
      fi

      i=$((i + 1))
    done

    # --- must_not_find dimension/line checks (independent of must_find) ----
    j=0
    while [ "$j" -lt "$fp_count" ]; do
      local mnf_dim
      mnf_dim=$(jq -r ".must_not_find[$j].dimension" "$f")
      if [ -n "$mnf_dim" ] && ! grep -qxF "$mnf_dim" <<< "$KNOWN_DIMENSIONS"; then
        echo "ERROR: expected/$name must_not_find[$j] has unknown dimension '$mnf_dim' (not one of find.js's ALL_DIMENSIONS or the documented quality/correctness aliases)." >&2
        bad=1
        file_bad=1; file_reasons="$file_reasons,unknown dimension"
        c_unknown_dim=$((c_unknown_dim + 1))
      fi
      local mnf_line
      mnf_line=$(jq -r ".must_not_find[$j].line // empty" "$f")
      if [ -n "$mnf_line" ] && [ "$fixture_is_file" -eq 1 ]; then
        if [ "$mnf_line" -le 0 ] 2>/dev/null || [ "$mnf_line" -gt "$fixture_line_count" ] 2>/dev/null; then
          echo "ERROR: expected/$name must_not_find[$j] cites line $mnf_line but $fixture_field has $fixture_line_count lines." >&2
          bad=1
          file_bad=1; file_reasons="$file_reasons,line out of range"
          c_range=$((c_range + 1))
        fi
      fi
      j=$((j + 1))
    done

    if [ "$file_bad" -eq 1 ]; then
      INVALID_EXPECTED[$key]="${file_reasons#,}"
      c_invalid_files=$((c_invalid_files + 1))
    fi
  done

  # Mirror of the missing-fixture check: a fixture with no expected/*.json can
  # never be scored, and nothing said so. `docs/component-test-vs-guard-test`
  # sat in the suite unscoreable until the 2026-09-11 docs run made the count
  # not add up (5 fixtures in the category, 4 scored). A warning, not an error:
  # a fixture parked deliberately while its expectation is being written is a
  # legitimate state, it just must not be a silent one.
  local c_orphan_fixture=0
  local fx b
  while IFS= read -r fx; do
    [ -n "$fx" ] || continue
    b=$(basename "$fx"); b="${b%%.*}"
    if [ ! -f "$EXPECTED_DIR/$b.json" ]; then
      echo "WARNING: fixture '${fx#"$FIXTURES_DIR"/}' has no expected/$b.json, so it can never be scored. Write one or remove the fixture."
      c_orphan_fixture=$((c_orphan_fixture + 1))
    fi
  done < <(find "$FIXTURES_DIR" -mindepth 2 -maxdepth 2 2>/dev/null | sort)

  echo
  echo "Validation summary"
  echo "-------------------"
  echo "  fixture without an expected file, never scoreable (warning):     $c_orphan_fixture"
  echo "  must_not_find missing line, same dimension as must_find (error): $c_mnf_error"
  echo "  must_not_find missing line, different dimension (warning):       $c_mnf_warning"
  echo "  window collisions (error):                                      $c_window"
  echo "  both line and lines present, ambiguous (error):                 $c_both_line_fields"
  echo "  line out of range (error):                                      $c_range"
  echo "  missing fixture file (error):                                   $c_missing_fixture"
  echo "  unknown dimension (error):                                      $c_unknown_dim"
  echo "  unknown severity (error):                                       $c_unknown_sev"
  echo "  hyphenated keyword, never matches (warning):                    $c_hyphen_warn"
  echo "  entry fully unsatisfiable, all keywords hyphenated (error):     $c_hyphen_error"
  echo "  fixtures invalidated (error, skipped in a normal run):          $c_invalid_files"

  if [ "$bad" -eq 1 ]; then
    echo "ERROR: one or more expected/*.json files failed validation (see above)." >&2
    # --validate-only exists to fail loudly in a pre-commit/CI context, so it
    # keeps aborting here. A normal run does NOT exit: score_fixture() skips
    # exactly the fixtures recorded in INVALID_EXPECTED and measures the rest
    # instead of refusing the whole suite over a few malformed files.
    if [ "$VALIDATE_ONLY" -eq 1 ]; then
      exit 1
    fi
  fi
}
if [ "$VALIDATE_ONLY" -eq 1 ]; then
  validate_expected
  echo
  echo "--validate-only: no fixtures were run."
  exit 0
fi
validate_expected

TOTAL_EXPECTED=0
TOTAL_FOUND=0
TOTAL_CORRECT=0
TOTAL_FALSE_POSITIVE=0
TOTAL_TIMEOUT=0
TOTAL_NO_AUDIT_LOG=0
# A fixture counts as a scoring CANDIDATE once it has a matching expected/*.json
# that also passed validate_expected() (i.e. it was neither SKIPped nor
# INVALID_EXPECTED). It becomes UNMEASURED if its session never produced
# anything scorable at all (mktemp failed before the audit could even run, or
# the audit log AND session stdout were both empty/absent) — that is a harness
# failure, not a zero-recall result, and must never be silently reported as one.
# TOTAL_INVALID_EXPECTED is a third, disjoint bucket: a fixture whose
# expected/*.json failed validate_expected() never became a candidate in the
# first place, so it is neither a recall miss nor an UNMEASURED harness
# failure — it was never scoreable to begin with.
TOTAL_CANDIDATES=0
TOTAL_UNMEASURED=0
TOTAL_INVALID_EXPECTED=0
# Scorer-gap tripwire counters (see score_against_log): a SCORER_GAP means the
# log clearly contains dimension findings the scorer credited none of; a
# SUSPICIOUS_CREDIT means the inverse, a credited hit with no matching
# dimension finding in the log at all. Both are diagnostic, never part of the
# recall calculation.
TOTAL_SCORER_GAP=0
TOTAL_SUSPICIOUS_CREDIT=0
declare -A CAT_FOUND
declare -A CAT_CORRECT
declare -A CAT_EXPECTED

# Trim a keyword's trailing 3 characters when doing so still leaves a >=6 char
# prefix, so ordinary morphological variants — plurals, -ed/-ing, and
# especially -ent/-ency (idempotent/idempotency, the case that motivated this)
# — still match as a substring, without the trim becoming a vague fragment
# that fires on unrelated words. Anchored at \b so the stem can only begin a
# word, never land mid-word. The >=6 char floor is load-bearing, not
# arbitrary: at a looser >=4 char floor, "browser" (7 chars) stemmed to "brow"
# and false-matched "eyebrow"/"brownout" in a negative-case test — verified
# fixed at this threshold, see audit/evals/README.md.
#
# `matches` entries are documented as literal substrings, not regexes, but
# several stem_match outputs get joined into one `grep -E` alternation
# (matches_csv below), so every entry is interpreted as ERE unless escaped
# here. Trim BEFORE escaping: escaping first could insert a backslash right
# at the trim boundary and cut it in half, turning a valid escape sequence
# into a dangling backslash. ere_escape backslash-escapes every ERE
# metacharacter (. ^ $ * + ? ( ) [ ] { } | \) so the trimmed keyword is
# matched as the literal text it is documented to be.
#
# \b is only prepended when the (trimmed) keyword starts with a word
# character. \b means "boundary between \w and \W", so before a keyword
# starting with a non-word character (e.g. "{!!", ".help(", "$attributes")
# it would only match when the character immediately preceding the keyword
# in the log text is itself a word character — the opposite of the common
# case, where such tokens are preceded by whitespace or punctuation (a space
# before "{!!", a line start before "$attributes"). Anchoring there would
# silently suppress the very matches it is meant to protect, so those
# keywords are matched unanchored instead; a word-starting keyword keeps the
# \b anchor as before.
ere_escape() {
  printf '%s' "$1" | sed 's/[][\.^$*+?(){}|]/\\&/g'
}

stem_match() {
  local kw="$1"
  local len=${#kw}
  if [ "$len" -ge 9 ]; then
    kw="${kw:0:$((len - 3))}"
  fi
  local escaped
  escaped=$(ere_escape "$kw")
  case "$kw" in
    [a-zA-Z0-9_]*) printf '\\b%s' "$escaped" ;;
    *) printf '%s' "$escaped" ;;
  esac
}

# Read both artifact files (audit log + session stdout, in that order, exactly
# as a live fixture run persists them) and join wrapped bullets into single
# physical lines. Shared by the live run (score_fixture, which passes tmp-dir
# paths) and --recheck (which passes stored results/<timestamp>/ paths), so the
# two can never parse the same artifact shape differently.
build_joined_log() {
  local logfile="$1" stdoutfile="$2"
  { cat "$logfile" 2>/dev/null; printf '\n'; cat "$stdoutfile" 2>/dev/null; } | normalize_findings
}

# Score one fixture's already-built log against its expected/*.json, and run
# the scorer-gap tripwire alongside it. Takes the joined (pre-tr, one bullet
# per physical line) and tr'd (hyphen-tolerant, what must_find/must_not_find
# actually grep against) log text so the tripwire and the real scoring share
# one parse, never two that could drift apart. `elapsed_label` is printed
# verbatim on the summary line ("42s" for a live run, "recheck" for a stored
# one).
#
# Scorer-gap tripwire: compares, per dimension present in this fixture's
# must_find, "how many real finding lines does the log carry tagged with this
# dimension" against "how many must_find hits did the strict scorer credit
# for this dimension". A finding line is recognized two ways: the canonical
# "[Severity][Dimension]" bracket tag, or the dimension's own worker-ID prefix
# ("dim-n-n", find.js's internal numbering) followed within ~20 characters by
# a bare severity word. The ID-based half exists because real sessions drift
# from the canonical bracket shape into several punctuation variants around
# that same ID — a bold bullet ("- **payments-0-1 — Critical (CONFIRMED)**"),
# a markdown table row ("| payments-0-1 | Critical | ... |"), and a numbered
# list ("1. payments-0-1 (Important, CONFIRMED) file:line") were all seen in
# real 2026-09-10 artifacts — and the ID+severity pair is the one thing that
# stays intact across all of them, unlike the surrounding markup. A fifth
# variant that also breaks the ID+severity adjacency is invisible to this
# detector, same known fragility as the rest of this harness (see README
# "Honest limitations"). It only fires on a hard 0-vs-nonzero mismatch in
# either direction, never on
# "audit found more/fewer than expected" — a dimension where the scorer
# credited at least one hit never trips it, no matter how many other findings
# the log carries in that dimension, so a fixture that scores correctly can
# never trigger it. Deliberately rough: it does not check that the reported
# bullet and the credited hit are about the SAME finding, only that the
# dimension-level counts agree in sign. That is the tripwire's known limit —
# it says "look at this fixture by hand", it is not a second scorer, and a
# malformed must_find entry (see the line/matches ERRORs above) that shares a
# dimension with a real finding can still fire it for a reason other than a
# scoring bug.
score_against_log() {
  local base="$1" expected_file="$2" log="$3" joined_log="$4" elapsed_label="$5"
  local category
  category=$(jq -r '.fixture' "$expected_file" | cut -d/ -f1)

  # Parse expected
  local expected_count
  expected_count=$(jq '.must_find | length' "$expected_file")
  TOTAL_EXPECTED=$((TOTAL_EXPECTED + expected_count))
  CAT_EXPECTED[$category]=$(( ${CAT_EXPECTED[$category]:-0} + expected_count ))

  local hits=0
  local -A dim_credited
  local i=0
  while [ "$i" -lt "$expected_count" ]; do
    local dim line matches_csv
    dim=$(jq -r ".must_find[$i].dimension" "$expected_file")
    line=$(jq -r ".must_find[$i].line // empty" "$expected_file")
    # Stem each keyword individually (see stem_match) rather than joining the
    # raw strings: a plain join would keep matching only the exact word form
    # named in the fixture, e.g. "idempotent", and miss a correct finding that
    # says "idempotency key" instead.
    matches_csv=""
    while IFS= read -r match; do
      [ -n "$matches_csv" ] && matches_csv="$matches_csv|"
      matches_csv="$matches_csv$(stem_match "$match")"
    done < <(jq -r ".must_find[$i].matches[]" "$expected_file")

    # An entry cites one or more line anchors, either via singular `line` or
    # via `lines` (validate_expected() rejects both being present at once). A
    # hit counts when a finding's cited line falls within the +/-3 window of
    # ANY one of them — some defects (a duplicate key, a gating bug) genuinely
    # live at two places in the source, and citing either is correct.
    local -a anchors=()
    if [ -n "$line" ]; then
      case "$line" in
        *[!0-9]*)
          echo "  ERROR: $base must_find[$i] has non-numeric line ('$line') — counted as miss" >&2
          i=$((i + 1))
          continue
          ;;
      esac
      anchors=("$line")
    else
      local lines_count li anchor_val
      lines_count=$(jq ".must_find[$i].lines // [] | length" "$expected_file")
      li=0
      while [ "$li" -lt "$lines_count" ]; do
        anchor_val=$(jq -r ".must_find[$i].lines[$li]" "$expected_file")
        anchors+=("$anchor_val")
        li=$((li + 1))
      done
    fi

    # A missing/non-numeric line would otherwise become the literal string
    # "null", which the arithmetic below treats as 0, silently producing a
    # wrong line window. Fail this entry loudly instead.
    if [ "${#anchors[@]}" -eq 0 ]; then
      echo "  ERROR: $base must_find[$i] has no usable line anchor ('line' and 'lines' both missing/empty) — counted as miss" >&2
      i=$((i + 1))
      continue
    fi

    # An empty matches array would make grep -iE "" match every line, counting
    # a hit regardless of content. Treat it as a fixture config error instead.
    if [ -z "$matches_csv" ]; then
      echo "  ERROR: $base must_find[$i] has empty matches list — counted as miss" >&2
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

    dim_credited[$dim]=${dim_credited[$dim]:-0}

    # Line numbers drift by a few lines between model judgment and fixture
    # ground truth (observed off-by-one on sqli-laravel): accept +/-3. A
    # range citation counts when it overlaps that window (see
    # line_window_match), not only when a single cited number falls inside it.
    # Reuse line_window_match per anchor rather than a second matcher: the
    # first anchor whose window is hit counts the entry as found.
    local matched=0 anchor lo hi
    for anchor in "${anchors[@]}"; do
      lo=$((anchor > 3 ? anchor - 3 : 1))
      hi=$((anchor + 3))
      if echo "$log" | grep -iE "\\[?$dim_pat\\]?" | grep -iE "$matches_csv" | line_window_match "$lo" "$hi" | grep -q .; then
        matched=1
        break
      fi
    done

    if [ "$matched" -eq 1 ]; then
      hits=$((hits + 1))
      dim_credited[$dim]=$((dim_credited[$dim] + 1))
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
  # Findings the pipeline itself rejected (see strip_discarded_findings) must
  # never count as false positives — computed once per fixture since $log is
  # the same for every must_not_find entry below.
  local fp_log
  fp_log=$(printf '%s\n' "$log" | strip_discarded_findings || true)
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
    fp_hits=$(echo "$fp_log" | grep -iE "\\[(critical|important|minor)\\]" | grep -ivE "\\[clean\\]" | grep -iE "\\[?$bad_dim_pat\\]?" || true)
    if [ -n "$bad_line" ]; then
      local bad_lo bad_hi
      bad_lo=$((bad_line > 3 ? bad_line - 3 : 1))
      bad_hi=$((bad_line + 3))
      fp_hits=$(echo "$fp_hits" | line_window_match "$bad_lo" "$bad_hi" || true)
    fi
    if [ -n "$fp_hits" ]; then
      fp=$((fp + 1))
    fi
    j=$((j + 1))
  done
  TOTAL_FALSE_POSITIVE=$((TOTAL_FALSE_POSITIVE + fp))

  # Scorer-gap tripwire (see this function's header comment for the design and
  # its limits). Read from joined_log (pre-tr) so hyphens in a "dim-n-n" ID
  # are intact; dim_pattern_for's own char class already tolerates a literal
  # hyphen in the bracket-tag half, so no tr is needed here.
  local dim
  for dim in "${!dim_credited[@]}"; do
    local gap_pat bracket_n id_n reported_n credited_n
    gap_pat=$(dim_pattern_for "$dim")
    bracket_n=$(printf '%s\n' "$joined_log" | grep -ivE '\[clean\]' | grep -iE '\[(critical|important|minor)\]' | grep -icE "\\[?${gap_pat}\\]?" || true)
    id_n=$(printf '%s\n' "$joined_log" | grep -ivE '\[clean\]' | grep -icE "${gap_pat}-[0-9]+-[0-9]+.{0,20}(critical|important|minor)" || true)
    reported_n=$((bracket_n + id_n))
    credited_n=${dim_credited[$dim]}
    if [ "$reported_n" -gt 0 ] && [ "$credited_n" -eq 0 ]; then
      echo "  SCORER_GAP $base dimension '$dim': log carries $reported_n finding(s) tagged $dim, scorer credited 0 must_find hits — look at this fixture by hand" >&2
      TOTAL_SCORER_GAP=$((TOTAL_SCORER_GAP + 1))
    elif [ "$reported_n" -eq 0 ] && [ "$credited_n" -gt 0 ]; then
      echo "  SUSPICIOUS_CREDIT $base dimension '$dim': scorer credited $credited_n hit(s), log carries no finding tagged $dim — may have matched something that is not a finding" >&2
      TOTAL_SUSPICIOUS_CREDIT=$((TOTAL_SUSPICIOUS_CREDIT + 1))
    fi
  done

  echo "    expected=$expected_count, hits=$hits, false-positives=$fp, $elapsed_label"
}

# Print once at the end of the live run and once at the end of --recheck, so
# the two gap counters are never reported by two separately maintained echo
# blocks that could drift apart.
print_gap_summary() {
  echo "  Scorer gaps (log had dimension findings, scorer credited none):   $TOTAL_SCORER_GAP"
  echo "  Suspicious credits (scorer credited a hit, log had no finding):   $TOTAL_SUSPICIOUS_CREDIT"
}

if [ -n "$RECHECK_DIR" ]; then
  if [ ! -d "$RECHECK_DIR" ]; then
    echo "ERROR: --recheck dir '$RECHECK_DIR' does not exist." >&2
    exit 1
  fi
  echo "Recheck: $RECHECK_DIR"
  echo "========$(printf '%*s' "${#RECHECK_DIR}" '' | tr ' ' '=')"
  echo
  recheck_count=0
  for expected_file in "$EXPECTED_DIR"/*.json; do
    [ -f "$expected_file" ] || continue
    base=$(basename "$expected_file" .json)
    [ -n "${INVALID_EXPECTED[$base]:-}" ] && continue
    logfile="$RECHECK_DIR/$base-auditlog.md"
    stdoutfile="$RECHECK_DIR/$base-stdout.txt"
    [ -f "$logfile" ] || [ -f "$stdoutfile" ] || continue
    joined_log=$(build_joined_log "$logfile" "$stdoutfile")
    if [ -z "$joined_log" ]; then
      echo "  RECHECK_SKIP $base: artifact(s) present but empty" >&2
      continue
    fi
    log=$(printf '%s' "$joined_log" | tr '-' ' ')
    echo "  $base"
    recheck_count=$((recheck_count + 1))
    score_against_log "$base" "$expected_file" "$log" "$joined_log" "recheck"
  done
  echo
  echo "Recheck summary ($recheck_count fixture(s) found in $RECHECK_DIR)"
  echo "-------------------------------------------------"
  if [ "$TOTAL_EXPECTED" -gt 0 ]; then
    recall=$(awk -v c="$TOTAL_CORRECT" -v e="$TOTAL_EXPECTED" 'BEGIN { printf "%.0f", (c/e)*100 }')
    echo "  Recall:    $TOTAL_CORRECT/$TOTAL_EXPECTED ($recall%)"
  fi
  echo "  False-positives: $TOTAL_FALSE_POSITIVE"
  print_gap_summary
  exit 0
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

  # expected/$base.json exists but validate_expected() flagged it: it was
  # never scoreable, so it does not become a CANDIDATE at all (same tier as
  # the SKIP above, not a run that failed). See INVALID_EXPECTED's definition
  # at validate_expected() for what counts as invalidating vs. a warning.
  if [ -n "${INVALID_EXPECTED[$base]:-}" ]; then
    echo "  INVALID_EXPECTED $fixture_rel (expected/$base.json: ${INVALID_EXPECTED[$base]}) — skipped, not scored"
    TOTAL_INVALID_EXPECTED=$((TOTAL_INVALID_EXPECTED + 1))
    return
  fi
  TOTAL_CANDIDATES=$((TOTAL_CANDIDATES + 1))

  # Setup temp repo. A failed mktemp must not silently vanish as a zero-recall
  # fixture (2026-09-10 incident: it did, with exit 0) — count it as UNMEASURED
  # and move on instead of relying on `set -e` to abort the whole run.
  local tmp_dir
  if ! tmp_dir=$(mktemp -d); then
    echo "  UNMEASURED $fixture_rel: mktemp failed, fixture never ran" >&2
    TOTAL_UNMEASURED=$((TOTAL_UNMEASURED + 1))
    return
  fi
  # Harness scratch lives OUTSIDE the audited repo. eval-settings.json and
  # claude-stdout.txt used to be written into $tmp_dir, which IS the throwaway
  # git repo the fixture audit runs against, so every session saw two foreign
  # files in its own working tree. The 2026-09-11 architecture run shows one
  # session spending a paragraph explaining that neither file is a task change.
  # Best case that is wasted attention; worse, a docs_sync or code_quality
  # specialist has grounds to report them, which would score as a false
  # positive the fixture author never wrote.
  local aux_dir
  if ! aux_dir=$(mktemp -d); then
    echo "  UNMEASURED $fixture_rel: mktemp failed for the harness scratch dir, fixture never ran" >&2
    TOTAL_UNMEASURED=$((TOTAL_UNMEASURED + 1))
    rm -rf "$tmp_dir"
    return
  fi
  trap "rm -rf '$tmp_dir' '$aux_dir'" RETURN

  cd "$tmp_dir"
  git init -q
  git config user.email "eval@local"
  git config user.name "Eval"
  git commit --allow-empty -q -m "init"

  # Drop fixture as staged change. A directory fixture is copied and staged as
  # a whole (one scenario, several files) so it triggers exactly one run, not
  # one run per file inside it.
  #
  # A directory fixture carrying a top-level `.eval-root` marker is copied to
  # the repo ROOT instead of under `<category>/<name>/`. This is an explicit
  # opt-in for fixtures whose scenario depends on repo-level detection (e.g.
  # payments: detect-stripe.sh only looks for composer.json at the repo root
  # and one level into each SOURCE_DIRS entry, never inside a nested fixture
  # directory, so a plain directory-fixture copy would score zero recall for
  # a reason indistinguishable from the dimension failing). The marker file
  # itself is never staged, only used to select this branch.
  if [ "$is_dir" -eq 1 ] && [ -f "$fixture_path/.eval-root" ]; then
    cp -R "$fixture_path/." "$tmp_dir/"
    rm -f "$tmp_dir/.eval-root"
    git add -A
  elif [ "$is_dir" -eq 1 ]; then
    mkdir -p "$fixture_rel"
    cp -R "$fixture_path/." "$fixture_rel/"
    git add "$fixture_rel"
  else
    mkdir -p "$(dirname "$fixture_rel")"
    cp "$fixture_path" "$fixture_rel"
    git add "$fixture_rel"
  fi

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
  local dim_env=""
  if [ "$SCOPED" -eq 1 ]; then
    local dim
    # The expectation KNOWS which dimension the fixture tests; the category
    # directory only guesses from a folder name. Derive from must_find first and
    # keep dimension_for_category as the fallback. Two things this fixes:
    # `quality` and `copy` were simply missing from that table, so 13 fixtures
    # silently ran a full unscoped audit despite --scoped; and `correctness` (7
    # fixtures) and `reliability` (1) are deliberately unmapped because they span
    # several dimensions as a CATEGORY, while every one of their fixtures names
    # exactly one dimension in its own must_find. Verified 2026-09-11: all 88
    # expected files name exactly one distinct must_find dimension, so this is
    # unambiguous for the whole suite, not just for the eight.
    dim=$(jq -r '[.must_find[]?.dimension] | unique | join(",")' "$expected_file" 2>/dev/null || true)
    # `quality` and `correctness` are SCORING synonyms for code_quality
    # (dim_pattern_for treats them as one), but they are not among the 14 ids
    # AUDIT_DIMENSIONS accepts, and the skill discards a value it does not know.
    # Normalize before handing it over, or the two fixtures that use those names
    # would run with an empty dimension selection.
    # A plain `case` rather than a sed substitution: every expected file names
    # exactly one dimension (verified across all 88 on 2026-09-11), so this is a
    # whole-value mapping, and BSD sed on macOS has no \b to anchor a word-wise
    # one with (tried, it silently left the value untouched).
    case "$dim" in
      correctness|quality) dim="code_quality" ;;
      ui)                  dim="ui_design" ;;
      docs)                dim="docs_sync" ;;
    esac
    [ -n "$dim" ] || dim=$(dimension_for_category "$category")
    # /audit takes no CLI arguments since the per-dimension pipeline rebuild
    # (2026-09-05): a scoped run sets AUDIT_DIMENSIONS instead, which also
    # suppresses the AskUserQuestion start prompt so the fixture session
    # never blocks on it.
    [ -n "$dim" ] && dim_env="AUDIT_DIMENSIONS=$dim"
  fi
  local started
  started=$(date +%s)
  # The language instruction goes into the system prompt, NOT into the prompt
  # string: everything after "/audit" is the skill ARGUMENT, so appending
  # "— write all findings ... in English" fed the audit a bogus free-text scope
  # hint on every run, and with --scoped it swallowed the dimension name too.
  local run_rc=0
  # Sandboxing off for the fixture session, via a CLI settings overlay that
  # merges over user settings and touches nothing else. A sandbox cannot start
  # inside a sandbox: when the harness itself is launched from a Claude session
  # whose Bash tool is sandboxed, the nested session dies at startup with
  # "Sandbox is required but failed to initialize: EPERM ... srt-mux-*.sock"
  # and every fixture scores zero, which reads exactly like a recall collapse.
  # The fixture audits run in a throwaway git repo under $tmp_dir, so the
  # boundary buys nothing here anyway.
  printf '{"sandbox":{"enabled":false}}\n' >"$aux_dir/eval-settings.json"
  # An unscoped run also needs a set variable so the fixture session never
  # blocks on the start-question AskUserQuestion (SKILL.md Phase 1.5: "a set
  # variable suppresses both questions").
  env CLAUDE_EFFORT=low AUDIT_SKIP_LEARNING_CHECK=1 ${dim_env:-AUDIT_FIX_SCOPE=none} \
    timeout "$PER_FIXTURE_TIMEOUT" claude -p "$audit_cmd" --effort low \
      --settings "$aux_dir/eval-settings.json" \
      --append-system-prompt "Write all findings, the audit log and your final summary in English, regardless of the language used in any CLAUDE.md." \
      </dev/null >"$aux_dir/claude-stdout.txt" 2>&1 || run_rc=$?
  local elapsed=$(( $(date +%s) - started ))
  # timeout(1) exits 124 when it had to kill the child; that is the
  # deterministic timeout signal. Wall-clock elapsed alone can mislabel a
  # fixture that finished right at the boundary, so only 124 decides the
  # branch below, elapsed is still reported for the log.
  if [ "$run_rc" -eq 124 ]; then
    # The old wording here claimed "scored as zero recall, treat this fixture as
    # unmeasured", which is not what happens: scoring proceeds below against
    # whatever the killed session had already written, so a timed-out fixture can
    # and does credit hits (2026-09-11: reset-clean-command-gate.sh timed out and
    # scored hits=1 under a line saying it had been scored zero). A result line
    # that contradicts the number next to it is worse than no line.
    echo "  TIMEOUT $fixture_rel after ${elapsed}s — session killed; whatever it had written so far is still scored below, so its number is a FLOOR, not a final result"
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
    # Name what WAS there. Without this the warning states a negative and nothing
    # else, so the next reader cannot tell a session that wrote nothing from one
    # that wrote a differently-named file, and the tmp repo is gone by then. A
    # 2026-09-10 run lost a fixture exactly this way: the session completed and
    # reported its findings, but its log could not be matched or diagnosed.
    local present
    present=$({ find "$tmp_dir/.claude/audits" -maxdepth 1 -name '*.md' -exec basename {} \; 2>/dev/null || true; } | sort | paste -sd', ' -)
    if [ -n "$present" ]; then
      echo "    present but unmatched: $present"
    else
      echo "    .claude/audits/ holds no .md file at all (the session wrote no log)"
    fi
    TOTAL_NO_AUDIT_LOG=$((TOTAL_NO_AUDIT_LOG + 1))
  fi

  # Persist artifacts so misses can be diagnosed/rescored without a paid rerun.
  cp "$aux_dir/claude-stdout.txt" "$RESULTS_DIR/$base-stdout.txt" 2>/dev/null || true
  [ -n "$logfile" ] && cp "$logfile" "$RESULTS_DIR/$base-auditlog.md" 2>/dev/null || true

  # build_joined_log joins each wrapped bullet into one physical line (see
  # normalize_findings' definition above); the blank line it inserts between
  # the two `cat`s guarantees a bullet from the log file can never absorb the
  # first line of stdout as a continuation. tr '-' ' ' runs AFTER the join, so
  # hyphenated variants ("SQL-Injection") match space-separated keyword
  # patterns ("sql injection"); dim/line matching is hyphen-tolerant either
  # way. joined_log (pre-tr) is kept too, for the scorer-gap tripwire in
  # score_against_log, which greps for intact "- [" / "- **" bullet markers.
  local joined_log log
  joined_log=$(build_joined_log "$logfile" "$aux_dir/claude-stdout.txt")
  log=$(printf '%s' "$joined_log" | tr '-' ' ')
  if [ -z "$log" ]; then
    # Second known incident (2026-09-10): every nested session died instantly,
    # leaving no audit log AND no stdout, and scored as zero recall — visually
    # identical to a real recall collapse. UNMEASURED, not a scored miss.
    echo "  UNMEASURED $fixture_rel: no audit log and no session output"
    TOTAL_UNMEASURED=$((TOTAL_UNMEASURED + 1))
    return
  fi

  # Third incident (2026-09-12): the CLI's OAuth token was revoked mid-batch, so
  # every later session exited in 2 to 4 seconds with "Failed to authenticate.
  # API Error: 401 OAuth access token has been revoked." That output is not
  # empty, so the branch above does not catch it, and the fixture was scored:
  # correctness came back "2/10 (20%)" when only two fixtures had run at all and
  # both had passed. A session that never reached the audit is UNMEASURED for
  # the same reason a failed mktemp is. Matching on the startup-failure text
  # rather than on the short runtime, because a genuinely fast audit is
  # legitimate and must not be discarded.
  if [ -z "$logfile" ] && printf '%s' "$joined_log" | grep -qiE 'Failed to authenticate|OAuth access token has been revoked|API Error: 401|Invalid API key|credit balance is too low'; then
    echo "  UNMEASURED $fixture_rel: the session never started (authentication or account error), nothing was audited"
    printf '%s' "$joined_log" | grep -iE 'Failed to authenticate|OAuth|API Error|Invalid API key|credit balance' | head -1 | sed 's/^/    /'
    TOTAL_UNMEASURED=$((TOTAL_UNMEASURED + 1))
    return
  fi

  score_against_log "$base" "$expected_file" "$log" "$joined_log" "${elapsed}s"
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
[ "$TOTAL_TIMEOUT" -gt 0 ] && echo "  TIMED OUT (killed mid-run; partial output still scored, so these are floors): $TOTAL_TIMEOUT"
[ "$TOTAL_NO_AUDIT_LOG" -gt 0 ] && echo "  NO AUDIT LOG FOUND (scored from stdout fallback only, treat as unconfirmed): $TOTAL_NO_AUDIT_LOG"
[ "$TOTAL_UNMEASURED" -gt 0 ] && echo "  UNMEASURED (no audit log AND no session output, excluded from recall above): $TOTAL_UNMEASURED / $TOTAL_CANDIDATES"
[ "$TOTAL_INVALID_EXPECTED" -gt 0 ] && echo "  INVALID EXPECTATION (expected/*.json failed validation, never became a candidate, not a recall miss): $TOTAL_INVALID_EXPECTED"
print_gap_summary
echo
echo "Per category:"
for cat in "${!CAT_EXPECTED[@]}"; do
  c="${CAT_CORRECT[$cat]:-0}"
  e="${CAT_EXPECTED[$cat]}"
  echo "  $cat: $c/$e"
done

# Exit-code contract: 0 means at least one fixture was actually measured.
# A run where every candidate fixture was UNMEASURED (mktemp failed, or every
# session died before producing an audit log or stdout) is indistinguishable
# from a genuine zero-recall result unless the exit code says otherwise — that
# ambiguity is exactly how the second 2026-09-10 incident went unnoticed since
# 2026-09-05. TOTAL_CANDIDATES == 0 (e.g. a typo'd --only) is the same failure
# mode: nothing was measured. A fixture skipped as INVALID_EXPECTED never
# becomes a candidate (see score_fixture), so a run where --only selects
# nothing but invalid fixtures already falls into TOTAL_CANDIDATES == 0 here —
# no separate branch needed: it is exactly as much "nothing was measured" as
# a typo'd --only, and the caller needs the same non-zero signal to notice.
if [ "$TOTAL_CANDIDATES" -eq 0 ] || [ "$TOTAL_UNMEASURED" -eq "$TOTAL_CANDIDATES" ]; then
  echo
  echo "ERROR: nothing was measured ($TOTAL_UNMEASURED/$TOTAL_CANDIDATES candidate fixtures unmeasured, $TOTAL_INVALID_EXPECTED skipped as invalid) — this is a harness failure, not a zero-recall result" >&2
  exit 1
fi
