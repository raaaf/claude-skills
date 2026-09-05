# Scope (SCOPE=repo file walk)

Detail bash for building the repo-wide file list for `/full-audit`, moved out of the old batching
doc (batching itself is gone, see the 2026-09-05 per-dimension rebuild). Read by
`full-audit/SKILL.md` Phase 0 in place of `collect-scope.sh --all`.

## Phase 0: Scope & Context — Bash

```bash
PROJECT_ROOT=$(git rev-parse --show-toplevel)
cd "$PROJECT_ROOT"

# Disable pathname expansion for the rest of this script. $EXCLUDE below is
# an intentionally unquoted string so it word-splits into multiple find
# flags (existing pattern, shellcheck-disabled where it's used) -- but an
# unquoted `*` is ALSO a glob, and bash expands it against real files before
# find ever sees it if any happen to match at that exact relative path. The
# original `*/node_modules/*`-style entries never matched a real path from
# repo root so this stayed latent; `.claude/audits/*` (added for the
# scope-extensions override below) does match real files in this repo, and
# without `set -f` bash silently rewrites `-not -path .claude/audits/*` into
# `-not -path <every file in that directory>`, corrupting the find
# expression -- confirmed by reproducing it (TOTAL_FILES collapsed to 0).
# `set -f` stops only pathname expansion; IFS word-splitting on $EXCLUDE,
# which the whole mechanism depends on, is unaffected.
set -f

# Framework detection (shared with /audit). detect-framework.sh emits three
# lines: FRAMEWORK=, SOURCE_DIRS=, PLATFORM=. SOURCE_DIRS is a list of
# directories, each %q-quoted individually and joined by plain (unescaped)
# spaces — a %q escape only ever protects a space that is actually INSIDE a
# directory name, so the separators stay real spaces.
#
# DO NOT collapse the four lines below back into the shorter-looking
#   eval "$(bash "$AUDIT_BIN/detect-framework.sh")"
# That single form is exactly the bug this comment exists to prevent: the
# SOURCE_DIRS line's unescaped separator spaces make it several shell words,
# not one assignment, so bash's "VAR=value word2 word3" sets SOURCE_DIRS only
# in word2's environment while word2 itself runs as a command -- FRAMEWORK
# and PLATFORM (plain single-word lines) come through fine, SOURCE_DIRS comes
# out silently empty, and the only visible symptom is an unrelated-looking
# bash error ("<dir>: is a directory") that never names SOURCE_DIRS as the
# casualty. Reproduced directly against this repo (2026-08-11). The four
# lines below are the only correct way to consume this script's output:
# capture the raw text first, pull each value out by key with sed, THEN
# reconstruct the array with its own targeted eval (below, after this block).
FW_OUT="$(bash "$AUDIT_BIN/detect-framework.sh")"
FRAMEWORK=$(printf '%s\n' "$FW_OUT" | sed -n 's/^FRAMEWORK=//p')
SOURCE_DIRS=$(printf '%s\n' "$FW_OUT" | sed -n 's/^SOURCE_DIRS=//p')
PLATFORM=$(printf '%s\n' "$FW_OUT" | sed -n 's/^PLATFORM=//p')

# Reconstruct the array from the %q-quoted, space-joined SOURCE_DIRS text.
# `NAME=(...)` compound-assignment syntax splits on unescaped whitespace and
# honors each element's own %q escaping, so every find call below gets each
# directory as its own argument, spaces-inside-names and all — the original
# `find $SOURCE_DIRS` broke as soon as a directory contained a space (this
# repo's own root, "Local Sites/claude-skills", is one). SOURCE_DIRS itself
# keeps its %q-quoted string form for anything that still reads it as text.
eval "SOURCE_DIRS_ARR=($SOURCE_DIRS)"

# Load PROJECT_CONTEXT from CLAUDE.md (awk instead of sed — more portable)
#
# Three outcomes, and the middle one is the one that used to fail silently:
#
#   heading present   -> use that section, as /audit does
#   file but no       -> CONTEXT_FALLBACK=WHOLE_FILE. The project has rules, they
#   heading              just do not live under this exact heading. Passing
#                        "no context" here is a lie about a file full of context.
#   no file           -> genuinely nothing
PROJECT_CLAUDE_MD="$PROJECT_ROOT/CLAUDE.md"
CONTEXT_FALLBACK=NONE
if [ -f "$PROJECT_CLAUDE_MD" ]; then
  PROJECT_CONTEXT=$(awk '/^## Audit Context$/{f=1;next} /^## /{f=0} f' "$PROJECT_CLAUDE_MD")
  if [ -z "$PROJECT_CONTEXT" ]; then
    CONTEXT_FALLBACK=WHOLE_FILE
    PROJECT_CONTEXT=$(cat "$PROJECT_CLAUDE_MD")
  fi
else
  CONTEXT_FALLBACK=NO_FILE
  PROJECT_CONTEXT="Kein projektspezifischer Kontext."
fi
echo "CONTEXT_FALLBACK=$CONTEXT_FALLBACK ($(printf '%s' "$PROJECT_CONTEXT" | wc -l) Zeilen Kontext)"

# Load SUPPRESSIONS (shared pattern with /audit)
SUPPRESSIONS_FILE="$PROJECT_ROOT/.claude/audits/suppressions.json"
if [ -f "$SUPPRESSIONS_FILE" ]; then
  SUPPRESSIONS=$(jq -r '[.suppressions[].pattern] | join(", ")' "$SUPPRESSIONS_FILE" 2>/dev/null || echo "Keine Suppressions")
else
  SUPPRESSIONS="Keine Suppressions"
fi

# All audit-relevant files — exclude build output, vendor and cache, and this
# skill's own generated log directories (never source, in any project that
# uses /audit or /full-audit; only matters once a project adds *.md to scope
# below, but pruning them is unconditional so it needs no project opt-in).
# Both a nested form (*/.claude/audits/*) and a root form (.claude/audits/*)
# are needed: when .claude/ is itself one of SOURCE_DIRS (true for this repo
# — detect-framework.sh's git-ls-files fallback lists every top-level tracked
# directory, .claude/ included), find's walked paths start with ".claude/..."
# with no leading "/" for "*/.claude/..." to match against. Proven by testing
# both forms directly: the leading-* pattern alone left the audits/plans logs
# in scope, silently, exactly the failure this exclusion exists to prevent.
EXCLUDE='-not -path */node_modules/* -not -path */vendor/* -not -path */.next/* -not -path */.nuxt/* -not -path */dist/* -not -path */build/* -not -path */coverage/* -not -path */.git/* -not -path */.claude/audits/* -not -path .claude/audits/* -not -path */.claude/plans/logs/* -not -path .claude/plans/logs/*'
# shellcheck disable=SC2086 -- EXCLUDE is a fixed, static flag list (no
# interpolated paths), meant to expand as multiple words; SOURCE_DIRS_ARR is
# a quoted array below and no longer subject to SC2086.
find "${SOURCE_DIRS_ARR[@]}" \( -name "*.php" -o -name "*.blade.php" -o -name "*.ts" -o -name "*.tsx" -o -name "*.js" -o -name "*.jsx" -o -name "*.vue" -o -name "*.svelte" -o -name "*.astro" -o -name "*.py" -o -name "*.swift" -o -name "*.kt" -o -name "*.java" -o -name "*.m" -o -name "*.mm" -o -name "*.h" -o -name "*.go" -o -name "*.rs" -o -name "*.sh" -o -name "*.bash" -o -name "*.zsh" \) $EXCLUDE 2>/dev/null | sort > /tmp/full-audit-files.txt
# Prompt template files — LLM prompt templates (*.md under prompt[s]/) are security targets
# (untrusted-placeholder isolation, see guidelines/security.md section XII) but are not caught
# by the standard globs. Include them so template files are never missed.
# shellcheck disable=SC2086 -- EXCLUDE only, see note above.
find "${SOURCE_DIRS_ARR[@]}" \( -path "*/prompts/*" -o -path "*/prompt/*" \) -name "*.md" $EXCLUDE 2>/dev/null | sort >> /tmp/full-audit-files.txt
# Extension-less executable scripts (deploy, pre-commit, CI helpers named
# without a suffix). The extension globs above miss these entirely. Restricted
# to files that are already executable AND start with a shebang, which keeps
# this cheap: the 2-byte read only fires for the small candidate set that
# survives `-perm -u+x` and the dotless-name filter, never for every file in
# the tree. `! -name "*.*"` excludes any name containing a dot (so ordinary
# extensioned files and dotfile configs like .eslintrc.json are skipped here,
# not because they are unimportant but because they are already covered above
# or are not scripts).
# shellcheck disable=SC2086 -- EXCLUDE only, see note above.
while IFS= read -r f; do
  [ "$(head -c 2 "$f" 2>/dev/null)" = "#!" ] && printf '%s\n' "$f"
done < <(find "${SOURCE_DIRS_ARR[@]}" -type f -perm -u+x ! -name "*.*" $EXCLUDE 2>/dev/null) >> /tmp/full-audit-files.txt

# Project-level scope override (optional, ADD-only): a project whose real
# source is Markdown — this repo's own SKILL.md orchestrators, agents/*.md,
# guidelines/*.md — declares extra extensions via a `scope-extensions:` line
# in .claude/audit-guidelines.md, the same file and declared-line convention
# already used by `perf-measure:` (audit/bin/perf-measure.sh):
#   scope-extensions: md
# Multiple extensions are space-separated on the one line. No file present,
# no matching line, or a line that sanitizes down to nothing (see below) all
# collapse to the same result: SCOPE_EXTRA_LIST stays empty and the block
# below is skipped, so scope collection behaves exactly as it always has.
# ADD-only by design: it can only widen the fixed glob above, never replace
# or narrow it, so there is no override syntax that can silently shrink
# coverage on a project that had none. REPLACE/SUBTRACT are not implemented
# — no real project needs less than the default source globs, and a narrowing
# override would be indistinguishable from the exact bug the plausibility
# assert below exists to catch.
SCOPE_EXTRA_LIST=""
if [ -f "$PROJECT_ROOT/.claude/audit-guidelines.md" ]; then
  SCOPE_EXTENSIONS_RAW=$(grep -m1 '^scope-extensions:[[:space:]]*' "$PROJECT_ROOT/.claude/audit-guidelines.md" \
    | sed 's/^scope-extensions:[[:space:]]*//')
  SCOPE_EXTRA_COUNT=0
  for ext in $SCOPE_EXTENSIONS_RAW; do
    # Sanitize: bare alnum tokens only. No dots, slashes, spaces, globs or
    # find flags survive this — a malformed or hostile line (a stray `*`,
    # a `-not -path /` fragment, anything) degrades to "not an extension,
    # skip it" instead of reaching the find command. This is what keeps
    # "an override that matches everything" impossible: the one token that
    # WOULD match everything, `*`, is rejected here, not by a downstream
    # size check.
    case "$ext" in
      ''|*[!A-Za-z0-9]*) continue ;;
    esac
    # Sanity bound: 5 extra extensions is generous for a real case (this
    # repo needs exactly one, `md`) and keeps the find expression built
    # below bounded regardless of what the line contains.
    [ "$SCOPE_EXTRA_COUNT" -ge 5 ] && break
    SCOPE_EXTRA_LIST="$SCOPE_EXTRA_LIST $ext"
    SCOPE_EXTRA_COUNT=$((SCOPE_EXTRA_COUNT + 1))
  done
  SCOPE_EXTRA_LIST="${SCOPE_EXTRA_LIST# }"
fi
if [ -n "$SCOPE_EXTRA_LIST" ]; then
  echo "Scope override: scope-extensions adds: $SCOPE_EXTRA_LIST"
  # Build the -o -name clauses as an array (not string word-splitting like
  # EXCLUDE above) so the *.$ext patterns stay quoted literals and never risk
  # pathname expansion against the cwd. Only entered when SCOPE_EXTRA_LIST is
  # non-empty, so the array always has >= 2 elements here — bash 3.2 treats
  # an empty array as an unbound variable under `set -u`, this path never
  # constructs one.
  SCOPE_EXTRA_FIND_ARGS=()
  for ext in $SCOPE_EXTRA_LIST; do
    if [ ${#SCOPE_EXTRA_FIND_ARGS[@]} -eq 0 ]; then
      SCOPE_EXTRA_FIND_ARGS=(-name "*.$ext")
    else
      SCOPE_EXTRA_FIND_ARGS+=(-o -name "*.$ext")
    fi
  done
  find "${SOURCE_DIRS_ARR[@]}" \( "${SCOPE_EXTRA_FIND_ARGS[@]}" \) $EXCLUDE 2>/dev/null | sort >> /tmp/full-audit-files.txt
fi

sort -u -o /tmp/full-audit-files.txt /tmp/full-audit-files.txt
TOTAL_FILES=$(wc -l < /tmp/full-audit-files.txt)

# --- Scope plausibility assert (MANDATORY, before dispatch) ---
# Guards the failure mode where scope collection silently returns nothing (or
# next to nothing) and the audit reports "clean" over files nobody enumerated.
# Real incident: an unquoted SOURCE_DIRS made `eval` drop it for every
# multi-directory framework, "find $SOURCE_DIRS ..." ran with no starting
# path, and TOTAL_FILES stayed at 0 all the way to a clean-looking run.
if [ "$TOTAL_FILES" -eq 0 ]; then
  echo "ABORT: TOTAL_FILES=0 -- scope collection found nothing under SOURCE_DIRS ($SOURCE_DIRS)."
  echo "  Likely cause: SOURCE_DIRS is empty or wrong (check the detect-framework.sh eval output"
  echo "  above), or a directory-scope argument that matches no source files."
  echo "  A full audit must never report success over an empty scope -- stopping."
  exit 1
fi

REPO_FILE_COUNT=$(git ls-files | wc -l | tr -d ' ')

if [ "$REPO_FILE_COUNT" -gt 0 ]; then
  # 2% of ALL tracked files (docs, configs, lockfiles, assets included, not
  # just source) is a deliberately low bar: real source-to-tracked ratios in
  # audited repos run far higher (20-70%+), so this fires only on the class
  # of bug that collapses the scope near-empty, never on a repo that is
  # legitimately code-light. Floor of 1 keeps a repo with few tracked files
  # total from demanding more files than it has.
  SCOPE_THRESHOLD=$(( REPO_FILE_COUNT * 2 / 100 ))
  [ "$SCOPE_THRESHOLD" -lt 1 ] && SCOPE_THRESHOLD=1
  if [ "$TOTAL_FILES" -lt "$SCOPE_THRESHOLD" ]; then
    echo "ABORT: TOTAL_FILES=$TOTAL_FILES looks implausibly small against the repo (git ls-files: $REPO_FILE_COUNT tracked files, expected >= $SCOPE_THRESHOLD)."
    echo "  Likely cause: SOURCE_DIRS wrong or incomplete ($SOURCE_DIRS), or an over-broad EXCLUDE."
    exit 1
  fi
fi
echo "Scope plausibility: TOTAL_FILES=$TOTAL_FILES vs $REPO_FILE_COUNT tracked files (git ls-files) -- OK"

# Frontend files
# shellcheck disable=SC2086 -- EXCLUDE only, see note above.
# Native UI files count as frontend (same set as FRONTEND_EXT_RE in audit/bin/lib-git-base.sh):
# a pure SwiftUI project produced an empty frontend list and skipped agents 5-10 until a manual
# override (learning 2026-08-03).
find "${SOURCE_DIRS_ARR[@]}" \( -name "*.blade.php" -o -name "*.css" -o -name "*.scss" -o -name "*.vue" -o -name "*.tsx" -o -name "*.jsx" -o -name "*.svelte" -o -name "*.astro" -o -name "*.html" -o -name "*.swift" -o -name "*.kt" -o -name "*.kts" -o -name "*.dart" -o -name "*.storyboard" -o -name "*.xib" \) $EXCLUDE 2>/dev/null | sort > /tmp/full-audit-frontend.txt

# Translation files
# shellcheck disable=SC2086 -- EXCLUDE only, see note above.
find "${SOURCE_DIRS_ARR[@]}" \( -path "*/lang/*" -o -path "*/locales/*" -o -path "*/locale/*" -o -path "*/translations/*" -o -path "*/messages/*" -o -path "*/i18n/*" \) \( -name "*.php" -o -name "*.json" -o -name "*.yaml" -o -name "*.yml" -o -name "*.po" -o -name "*.pot" -o -name "*.ts" -o -name "*.js" \) $EXCLUDE 2>/dev/null | sort > /tmp/full-audit-translations.txt
```

Variables from the outputs:
- **ALLE_DATEIEN:** `/tmp/full-audit-files.txt` — includes any `scope-extensions:` extra extensions, already merged and deduplicated. This is the `files` array passed to `find.js` as `args.files` (`scope: 'repo'`).
- **VISUELL_RELEVANTE_DATEIEN:** `/tmp/full-audit-frontend.txt`
- **TRANSLATION_DATEIEN:** `/tmp/full-audit-translations.txt`
- **TOTAL_FILES**, **PROJECT_CONTEXT**, **FRAMEWORK**, **SOURCE_DIRS**, **SUPPRESSIONS**, **CONTEXT_FALLBACK**

**Project-level scope override (`scope-extensions:`).** No functional effect on `/audit`: its scope is diff-based (`audit/bin/collect-scope.sh` lists whatever changed, regardless of extension), not a fixed-glob tree scan, so a changed `SKILL.md` is already in `/audit`'s scope today. This override exists for `/full-audit` only, where the fixed extension list above is otherwise the sole gate. `.claude/audit-guidelines.md` is a general per-project file, though — a project using both commands declares the line once and only `/full-audit` acts on it.
