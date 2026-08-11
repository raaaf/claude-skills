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
# (deliberately-broken fixtures, never a finding) are all skipped. Only
# single-line inline code spans are scanned — fenced multi-line ```bash
# blocks are out of scope, matching the "Markdown table or inline code"
# brief; those blocks mostly carry variables and loops that this
# lightweight scanner cannot parse safely.
#
# Output:
#   DOCSCLAIM {doc}:{line}: {short reason}      (zero or more, one per finding)
#   DOCSCLAIM_RESULT=OK                          (no false claims found)
#   DOCSCLAIM_RESULT=FINDINGS (N)                (N false claims)
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

FINDINGS=0
OUT=""

# check_candidate DOC LINE TOKEN KIND
check_candidate() {
  cc_doc="$1"; cc_line="$2"; cc_tok="$3"; cc_kind="$4"

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

  [ -e "$cc_tok" ] && return

  FINDINGS=1
  if [ "$cc_kind" = "cmd" ]; then
    OUT="${OUT}DOCSCLAIM ${cc_doc}:${cc_line}: references script ${cc_tok}, no such file
"
  else
    OUT="${OUT}DOCSCLAIM ${cc_doc}:${cc_line}: references path ${cc_tok}, does not resolve
"
  fi
}

# ---- Scan every doc, line by line, backtick span by backtick span ----
while IFS= read -r doc; do
  [ -n "$doc" ] || continue
  [ -f "$doc" ] || continue

  line_no=0
  while IFS= read -r line || [ -n "$line" ]; do
    line_no=$((line_no + 1))
    rest="$line"
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

      set -f
      for tok in $span; do
        case "$tok" in
          *.sh) check_candidate "$doc" "$line_no" "$tok" "cmd" ;;
          */*)  check_candidate "$doc" "$line_no" "$tok" "path" ;;
        esac
      done
      set +f

      [ "$closed" -eq 0 ] && break
    done
  done < "$doc"
done <<DOCSEOF
$DOCS
DOCSEOF

# ---- Skill roster: every SKILL.md dir <-> CLAUDE.md roster table ----
if [ -f "CLAUDE.md" ]; then
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
        r_line="${row%%$'\t'*}"
        r_rest="${row#*$'\t'}"
        r_name=$(printf '%s' "$r_rest" | sed -E 's/^\| `\/([a-zA-Z0-9_-]+)`.*/\1/')
        [ -n "$r_name" ] || continue
        if [ ! -f "${r_name}/SKILL.md" ]; then
          FINDINGS=1
          OUT="${OUT}DOCSCLAIM CLAUDE.md:${r_line}: skill roster lists /${r_name}, no ${r_name}/SKILL.md on disk
"
        fi
      done <<ROSTEROF
$ROSTER_ROWS
ROSTEROF
    fi

    # Real directory -> must appear in the roster table.
    if [ -n "$REAL_SKILLS" ]; then
      while IFS= read -r skill; do
        [ -n "$skill" ] || continue
        printf '%s\n' "$ROSTER_ROWS" | grep -qF "\`/${skill}\`" && continue
        FINDINGS=1
        OUT="${OUT}DOCSCLAIM CLAUDE.md:${ROSTER_START}: ${skill}/SKILL.md exists but is missing from the skill roster table
"
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
