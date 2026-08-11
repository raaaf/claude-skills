#!/usr/bin/env bash
#
# check-docs-claims.sh — mechanical half of "meta doc drift": documented
# claims that point at things which do not exist. Docs drift (CLAUDE.md /
# README / SKILL.md going stale) is this repo's most recurrent finding
# category (7 occurrences, top category in four consecutive audits, per
# `patterns-store.sh recurrences`). check-docs-path-drift.sh already
# mechanises the "a doc names a file THIS DIFF just deleted" half; this
# script covers the complementary, diff-independent half: a claim that has
# been false for a while, found by checking every doc against the tree as
# it stands right now.
#
# Scans CLAUDE.md, README.md, and every top-level */SKILL.md for:
#   - `bash <path>.sh` / bare `<path>.sh` command references -> script must exist
#   - other repo-relative paths quoted in backticks -> path must resolve
#   - the Skill roster table in CLAUDE.md vs the real SKILL.md directories
#
# Repo-path heuristic (the hard part — see also references/scope-and-pre-checks.md):
# a backtick-quoted token is only treated as a claim about THIS repo if its
# first path segment names one of this repo's own top-level directories
# (computed at runtime via `find -maxdepth 1`, so it never goes stale as
# skills are added/removed). Everything else — `app/Models/Customer.php`,
# `src/services/`, `.claude/audit-guidelines.md` — is a foreign-project
# illustrative example and is skipped on purpose: those are patterns a
# TARGET project might have, not a claim about this repo. `.claude/` and
# `.claude-plugin/` are deliberately excluded from the top-level directory
# list for the same reason plus one more: this repo's own `.claude/` holds
# gitignored, runtime-generated audit state (learning-log.md,
# suppressions.json, ...) that legitimately does not exist yet on a fresh
# checkout, so checking it would produce a false positive on day one.
#
# Bias is toward precision, not recall (a false positive here would fire on
# every future audit forever): bare filenames without a "/", glob patterns
# (`*`), template placeholders (`{name}`), variable interpolation (`$...`,
# `${...}`), tilde/absolute/URL paths, and anything under `audit/evals/`
# (deliberately-broken fixtures) are all skipped. Only single-line inline
# code spans are scanned — fenced multi-line ```bash blocks are out of
# scope, matching the "Markdown table or inline code" brief; those blocks
# mostly carry variables and loops that this lightweight scanner cannot
# parse safely.
#
# Work/output bounds (this repo runs the check unconditionally, in Phase 1
# of every audit, against arbitrary third-party repos — the input is not
# trusted). Without a bound, one pathological line ("many short backtick
# spans on one line") or one pathological doc ("thousands of lines that
# each produce a finding") makes both the scan time and the emitted finding
# count scale with attacker-controlled input, and the bulk of the observed
# cost was the naive `OUT="${OUT}...` string-append pattern below, which is
# O(N^2) in the number of findings. Four caps, chosen against this repo's
# own real content (max line length ~1950 chars, max backtick spans on one
# real line 36) so none of them ever fire on legitimate docs:
#   - MAX_LINE_LEN        4000  chars/line considered for span scanning
#   - MAX_SPANS_PER_LINE    60  backtick spans scanned per line
#   - MAX_FINDINGS_PER_DOC  20  findings recorded per document
#   - MAX_FINDINGS_TOTAL    50  findings recorded across the whole run
# A cap that fires is never silent: it is reported as its own DOCSCLAIM
# line (same contract as a real finding, so it survives into the audit log
# instead of being swallowed) naming which bound was hit. Coverage under a
# hit cap is genuinely partial — say so rather than claim a clean scan.
#
# Output:
#   DOCSCLAIM {doc}:{line}: {short reason}      (zero or more, one per finding)
#   DOCSCLAIM_RESULT=OK                          (no false claims found)
#   DOCSCLAIM_RESULT=FINDINGS (N)                (N false claims, including
#                                                  any cap-hit notice lines)
#   DOCSCLAIM_RESULT=SKIP (reason)               (nothing to check)
#
# Fails open: anything unparseable is skipped, never turned into a finding,
# and the script never dies mid-scan — a broken check must not break an
# audit run.
#
# Usage: bash check-docs-claims.sh [ROOT]
set -uo pipefail

ROOT="${1:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
cd "$ROOT" 2>/dev/null || { echo "DOCSCLAIM_RESULT=SKIP (root not found)"; exit 0; }

# Canonical (symlink-resolved) repo root, used by path_exists_in_repo below
# to stop a symlink from making an outside-the-repo path look like it
# satisfies a documented in-repo claim.
ROOT_REAL=$(pwd -P 2>/dev/null) || ROOT_REAL="$ROOT"

# ---- Work/output bounds — see header comment for the reasoning ----
MAX_LINE_LEN=4000
MAX_SPANS_PER_LINE=60
MAX_FINDINGS_PER_DOC=20
MAX_FINDINGS_TOTAL=50

# ---- Docs to scan: CLAUDE.md, README.md, every top-level */SKILL.md ----
DOCS=""
[ -f "CLAUDE.md" ] && DOCS="${DOCS}CLAUDE.md
"
[ -f "README.md" ] && DOCS="${DOCS}README.md
"
SKILL_DOCS=$(find . -mindepth 2 -maxdepth 2 -name 'SKILL.md' \
  -not -path '*/node_modules/*' -not -path '*/vendor/*' -not -path '*/.git/*' 2>/dev/null \
  | sed 's|^\./||' | sort)
[ -n "$SKILL_DOCS" ] && DOCS="${DOCS}${SKILL_DOCS}
"
DOCS=$(printf '%s\n' "$DOCS" | grep -v '^$' || true)

if [ -z "$DOCS" ]; then
  echo "DOCSCLAIM_RESULT=SKIP (no docs found)"
  exit 0
fi

# ---- Top-level repo directories: the "is this a repo path" heuristic ----
TOPDIRS=$(find . -mindepth 1 -maxdepth 1 -type d \
  -not -name '.git' -not -name '.claude' -not -name '.claude-plugin' 2>/dev/null \
  | sed 's|^\./||')

is_topdir() {
  seg="$1"
  [ -n "$seg" ] || return 1
  td=""
  while IFS= read -r td; do
    [ "$td" = "$seg" ] && return 0
  done <<TOPDIRSEOF
$TOPDIRS
TOPDIRSEOF
  return 1
}

# path_exists_in_repo TOKEN
#
# Like `[ -e TOKEN ]`, but a symlink (at the final component or at any
# directory in the path) whose resolved target lands outside $ROOT_REAL
# does NOT count as existing. `-e` alone follows symlinks unconditionally,
# so a repo could contain e.g. `evil/etclink -> /etc` and a doc claim of
# `evil/etclink/passwd` would resolve on the audit HOST filesystem and mask
# what is, from the repo's own point of view, still a false claim. A
# symlink that stays inside the repo is followed normally — that is a
# legitimate way for a documented path to exist.
path_exists_in_repo() {
  pe_tok="$1"
  [ -e "$pe_tok" ] || return 1

  # Resolve the final component if it is itself a symlink (bounded hop
  # count guards against a symlink cycle).
  pe_path="$pe_tok"
  pe_hops=0
  while [ -L "$pe_path" ] && [ "$pe_hops" -lt 10 ]; do
    pe_target=$(readlink "$pe_path") || return 1
    case "$pe_target" in
      /*) pe_path="$pe_target" ;;
      *) pe_path="$(dirname "$pe_path")/$pe_target" ;;
    esac
    pe_hops=$((pe_hops + 1))
  done

  # Resolve the (possibly symlinked) containing directory physically and
  # confirm it is still under the repo root.
  pe_dir=$(dirname "$pe_path")
  pe_real_dir=$(cd -P -- "$pe_dir" 2>/dev/null && pwd -P) || return 1
  case "$pe_real_dir" in
    "$ROOT_REAL"|"$ROOT_REAL"/*) return 0 ;;
    *) return 1 ;;
  esac
}

FINDINGS=0
OUT=""
TOTAL_FINDINGS=0
TOTAL_CAPPED=0

# check_candidate DOC LINE TOKEN KIND
check_candidate() {
  cc_doc="$1"; cc_line="$2"; cc_tok="$3"; cc_kind="$4"

  # Global or per-doc finding cap already hit: nothing further to do.
  [ "$TOTAL_CAPPED" -eq 1 ] && return
  [ "$DOC_CAPPED" -eq 1 ] && return

  # Strip one layer of common surrounding punctuation that can end up
  # inside a backtick span next to the path itself.
  cc_tok="${cc_tok#\(}"; cc_tok="${cc_tok#\[}"; cc_tok="${cc_tok#\{}"
  cc_tok="${cc_tok#\'}"; cc_tok="${cc_tok#\"}"
  cc_tok="${cc_tok%,}"; cc_tok="${cc_tok%.}"; cc_tok="${cc_tok%;}"; cc_tok="${cc_tok%:}"
  cc_tok="${cc_tok%\)}"; cc_tok="${cc_tok%\]}"; cc_tok="${cc_tok%\}}"
  cc_tok="${cc_tok%\'}"; cc_tok="${cc_tok%\"}"

  [ -n "$cc_tok" ] || return

  # Not a literal repo-relative claim: home-relative, absolute, URL,
  # variable interpolation, glob, or template placeholder.
  case "$cc_tok" in
    ~*|/*|\$*|http://*|https://*|*'${'*|*'*'*|*'{'*|*'}'*) return ;;
  esac

  case "$cc_tok" in
    */*) : ;;
    *) return ;;  # bare filename, no directory — too ambiguous, skip
  esac

  cc_first="${cc_tok%%/*}"
  is_topdir "$cc_first" || return

  # Eval fixtures deliberately contain broken/missing content — never a finding.
  case "$cc_tok" in
    audit/evals/*) return ;;
  esac

  # Directory-only mentions (no extension on the final segment) are skipped:
  # a bare directory is often describing an OPTIONAL/conditional source (e.g.
  # "globbed from `docs/adr/`, `docs/decisions/`" — a glob pattern for
  # directories a project may or may not have, not a claim that they exist
  # in this repo right now). Checking only extensioned paths removed a real
  # false positive on this exact repo during verification; directory
  # existence for skills is covered separately by the roster check below.
  cc_base="${cc_tok##*/}"
  case "$cc_base" in
    *.*) : ;;
    *) return ;;
  esac

  path_exists_in_repo "$cc_tok" && return

  FINDINGS=1
  TOTAL_FINDINGS=$((TOTAL_FINDINGS + 1))
  DOC_FINDINGS=$((DOC_FINDINGS + 1))
  if [ "$cc_kind" = "cmd" ]; then
    OUT="${OUT}DOCSCLAIM ${cc_doc}:${cc_line}: references script ${cc_tok}, no such file
"
  else
    OUT="${OUT}DOCSCLAIM ${cc_doc}:${cc_line}: references path ${cc_tok}, does not resolve
"
  fi

  if [ "$DOC_FINDINGS" -ge "$MAX_FINDINGS_PER_DOC" ]; then
    DOC_CAPPED=1
  fi
  if [ "$TOTAL_FINDINGS" -ge "$MAX_FINDINGS_TOTAL" ]; then
    TOTAL_CAPPED=1
  fi
}

# ---- Scan every doc, line by line, backtick span by backtick span ----
while IFS= read -r doc; do
  [ -n "$doc" ] || continue
  [ -f "$doc" ] || continue
  [ "$TOTAL_CAPPED" -eq 1 ] && break

  DOC_FINDINGS=0
  DOC_CAPPED=0
  LONG_LINES_SKIPPED=0
  SPANS_CAPPED=0

  line_no=0
  while IFS= read -r line || [ -n "$line" ]; do
    line_no=$((line_no + 1))
    [ "$DOC_CAPPED" -eq 1 ] && break

    # Bound the work a single line can cost: an attacker-sized line (many
    # thousands of chars, needed to fit a large number of backtick spans)
    # is skipped outright rather than parsed.
    if [ "${#line}" -gt "$MAX_LINE_LEN" ]; then
      LONG_LINES_SKIPPED=$((LONG_LINES_SKIPPED + 1))
      continue
    fi

    rest="$line"
    span_count=0
    while :; do
      case "$rest" in
        *'`'*) : ;;
        *) break ;;
      esac
      after="${rest#*\`}"
      span="${after%%\`*}"
      rest="${after#*\`}"
      closed=1
      [ "$rest" = "$after" ] && closed=0
      [ -n "$span" ] || { [ "$closed" -eq 0 ] && break; continue; }

      span_count=$((span_count + 1))
      if [ "$span_count" -gt "$MAX_SPANS_PER_LINE" ]; then
        SPANS_CAPPED=1
        break
      fi

      set -f
      for tok in $span; do
        case "$tok" in
          *.sh) check_candidate "$doc" "$line_no" "$tok" "cmd" ;;
          */*)  check_candidate "$doc" "$line_no" "$tok" "path" ;;
        esac
      done
      set +f

      [ "$DOC_CAPPED" -eq 1 ] && break
      [ "$TOTAL_CAPPED" -eq 1 ] && break
      [ "$closed" -eq 0 ] && break
    done
  done < "$doc"

  # Report any bound that fired for this doc — one summary line, not one
  # per skipped line/span, so the notice itself cannot become the next
  # unbounded-output problem.
  if [ "$LONG_LINES_SKIPPED" -gt 0 ] || [ "$SPANS_CAPPED" -eq 1 ]; then
    OUT="${OUT}DOCSCLAIM ${doc}:${line_no}: scan bound hit (${LONG_LINES_SKIPPED} line(s) over ${MAX_LINE_LEN} chars skipped, or a line had more than ${MAX_SPANS_PER_LINE} backtick spans) — some spans in this file were not checked
"
    FINDINGS=1
  fi
  if [ "$DOC_CAPPED" -eq 1 ]; then
    OUT="${OUT}DOCSCLAIM ${doc}:${line_no}: doc-claims scan capped at ${MAX_FINDINGS_PER_DOC} findings for this file, remaining lines not checked
"
    FINDINGS=1
  fi
done <<DOCSEOF
$DOCS
DOCSEOF

if [ "$TOTAL_CAPPED" -eq 1 ]; then
  OUT="${OUT}DOCSCLAIM (scan-cap):0: doc-claims scan capped at ${MAX_FINDINGS_TOTAL} total findings, remaining docs/lines not checked — coverage is partial, review manually
"
  FINDINGS=1
fi

# ---- Skill roster: every SKILL.md dir <-> CLAUDE.md roster table ----
# (Small and bounded by this repo's own skill count, not attacker input —
# still respects the total-findings cap for consistency.)
if [ -f "CLAUDE.md" ] && [ "$TOTAL_CAPPED" -eq 0 ]; then
  REAL_SKILLS=$(printf '%s\n' "$SKILL_DOCS" | sed -E 's|^([^/]+)/SKILL\.md$|\1|' | grep -v '^$' | sort -u)

  ROSTER_START=$(grep -n '^## Skill roster$' CLAUDE.md | head -1 | cut -d: -f1)
  if [ -n "$ROSTER_START" ]; then
    ROSTER_END=$(awk -v start="$ROSTER_START" 'NR>start && /^## /{print NR; exit}' CLAUDE.md)
    # No later "## " heading: the roster table runs to EOF. ROSTER_END is used
    # as an exclusive upper bound (NR<e) below, so it must be one PAST the
    # last line or that last row is silently dropped.
    [ -z "$ROSTER_END" ] && ROSTER_END=$(( $(wc -l < CLAUDE.md | tr -d ' ') + 1 ))

    ROSTER_ROWS=$(awk -v s="$ROSTER_START" -v e="$ROSTER_END" 'NR>s && NR<e && /^\| `\// {print NR"\t"$0}' CLAUDE.md)

    # Roster row -> real directory must exist.
    if [ -n "$ROSTER_ROWS" ]; then
      while IFS= read -r row; do
        [ -n "$row" ] || continue
        [ "$TOTAL_CAPPED" -eq 1 ] && break
        r_line="${row%%$'\t'*}"
        r_rest="${row#*$'\t'}"
        # sed -n '.../p': a non-matching row must yield NOTHING, not the
        # unmodified input line. Plain `sed 's/.../\1/'` prints the whole
        # original row verbatim when the pattern does not match, which
        # turned a false doc claim into a false-positive finding that
        # quoted raw repo table text into the (committed) audit log.
        r_name=$(printf '%s' "$r_rest" | sed -nE 's/^\| `\/([a-zA-Z0-9_-]+)`.*/\1/p')
        [ -n "$r_name" ] || continue
        if [ ! -f "${r_name}/SKILL.md" ]; then
          FINDINGS=1
          TOTAL_FINDINGS=$((TOTAL_FINDINGS + 1))
          OUT="${OUT}DOCSCLAIM CLAUDE.md:${r_line}: skill roster lists /${r_name}, no ${r_name}/SKILL.md on disk
"
          [ "$TOTAL_FINDINGS" -ge "$MAX_FINDINGS_TOTAL" ] && TOTAL_CAPPED=1
        fi
      done <<ROSTEROF
$ROSTER_ROWS
ROSTEROF
    fi

    # Real directory -> must appear in the roster table.
    if [ -n "$REAL_SKILLS" ] && [ "$TOTAL_CAPPED" -eq 0 ]; then
      while IFS= read -r skill; do
        [ -n "$skill" ] || continue
        [ "$TOTAL_CAPPED" -eq 1 ] && break
        printf '%s\n' "$ROSTER_ROWS" | grep -qF "\`/${skill}\`" && continue
        FINDINGS=1
        TOTAL_FINDINGS=$((TOTAL_FINDINGS + 1))
        OUT="${OUT}DOCSCLAIM CLAUDE.md:${ROSTER_START}: ${skill}/SKILL.md exists but is missing from the skill roster table
"
        [ "$TOTAL_FINDINGS" -ge "$MAX_FINDINGS_TOTAL" ] && TOTAL_CAPPED=1
      done <<REALOF
$REAL_SKILLS
REALOF
    fi
  fi
fi

if [ "$FINDINGS" -eq 1 ]; then
  N=$(printf '%s' "$OUT" | grep -c '^DOCSCLAIM ')
  echo "DOCSCLAIM_RESULT=FINDINGS ($N)"
  printf '%s' "$OUT"
else
  echo "DOCSCLAIM_RESULT=OK"
fi
