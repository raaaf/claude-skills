# Scope, Context, Batching (Phase 1 + 1.5 Detail)

Detail bash and batching heuristic for Phase 1 (Scope & Context) and Phase 1.5 (Batching Decision). Read by the orchestrator.

Content: Phase 1 scope bash · context building · optional pre-checks · Phase 1.5 batching · concurrent tree check

## Phase 1: Scope & Context — Bash

```bash
PROJECT_ROOT=$(git rev-parse --show-toplevel)
cd "$PROJECT_ROOT"

# Framework-Erkennung (shared mit /audit) — Output als eval einlesen
eval "$(bash "$AUDIT_BIN/detect-framework.sh")"

# PROJECT_CONTEXT aus CLAUDE.md laden (awk statt sed — portabler)
PROJECT_CLAUDE_MD="$PROJECT_ROOT/CLAUDE.md"
if [ -f "$PROJECT_CLAUDE_MD" ]; then
  PROJECT_CONTEXT=$(awk '/^## Audit Context$/{f=1;next} /^## /{f=0} f' "$PROJECT_CLAUDE_MD")
  [ -z "$PROJECT_CONTEXT" ] && PROJECT_CONTEXT="Kein projektspezifischer Kontext."
else
  PROJECT_CONTEXT="Kein projektspezifischer Kontext."
fi

# SUPPRESSIONS laden (shared pattern mit /audit)
SUPPRESSIONS_FILE="$PROJECT_ROOT/.claude/audits/suppressions.json"
if [ -f "$SUPPRESSIONS_FILE" ]; then
  SUPPRESSIONS=$(jq -r '[.suppressions[].pattern] | join(", ")' "$SUPPRESSIONS_FILE" 2>/dev/null || echo "Keine Suppressions")
else
  SUPPRESSIONS="Keine Suppressions"
fi

# Alle auditrelevanten Dateien — Build-Output, Vendor und Cache ausschliessen
EXCLUDE='-not -path */node_modules/* -not -path */vendor/* -not -path */.next/* -not -path */.nuxt/* -not -path */dist/* -not -path */build/* -not -path */coverage/* -not -path */.git/*'
# shellcheck disable=SC2086
find $SOURCE_DIRS \( -name "*.php" -o -name "*.blade.php" -o -name "*.ts" -o -name "*.tsx" -o -name "*.js" -o -name "*.jsx" -o -name "*.vue" -o -name "*.svelte" -o -name "*.astro" -o -name "*.py" \) $EXCLUDE 2>/dev/null | sort > /tmp/full-audit-files.txt
# Prompt-Template-Dateien — LLM-Prompt-Templates (*.md unter prompt[s]/) sind Security-Targets
# (Untrusted-Placeholder-Isolation, siehe guidelines/security.md Section XII), werden aber von
# den Standard-Globs nicht erfasst. Mit aufnehmen, damit Template-Dateien nie uebersehen werden.
# shellcheck disable=SC2086
find $SOURCE_DIRS \( -path "*/prompts/*" -o -path "*/prompt/*" \) -name "*.md" $EXCLUDE 2>/dev/null | sort >> /tmp/full-audit-files.txt
sort -u -o /tmp/full-audit-files.txt /tmp/full-audit-files.txt
TOTAL_FILES=$(wc -l < /tmp/full-audit-files.txt)

# Frontend-Dateien
# shellcheck disable=SC2086
find $SOURCE_DIRS \( -name "*.blade.php" -o -name "*.css" -o -name "*.scss" -o -name "*.vue" -o -name "*.tsx" -o -name "*.jsx" -o -name "*.svelte" -o -name "*.astro" -o -name "*.html" \) $EXCLUDE 2>/dev/null | sort > /tmp/full-audit-frontend.txt

# Translation-Dateien
# shellcheck disable=SC2086
find $SOURCE_DIRS \( -path "*/lang/*" -o -path "*/locales/*" -o -path "*/locale/*" -o -path "*/translations/*" -o -path "*/messages/*" -o -path "*/i18n/*" \) \( -name "*.php" -o -name "*.json" -o -name "*.yaml" -o -name "*.yml" -o -name "*.po" -o -name "*.pot" -o -name "*.ts" -o -name "*.js" \) $EXCLUDE 2>/dev/null | sort > /tmp/full-audit-translations.txt
```

Variables from the outputs:
- **ALLE_DATEIEN:** `/tmp/full-audit-files.txt`
- **VISUELL_RELEVANTE_DATEIEN:** `/tmp/full-audit-frontend.txt`
- **TRANSLATION_DATEIEN:** `/tmp/full-audit-translations.txt`
- **TOTAL_FILES**, **PROJECT_CONTEXT**, **FRAMEWORK**, **SOURCE_DIRS**, **SUPPRESSIONS**

## Context Building (one-time)

Read `CLAUDE.md`, package manifest, top 2 levels of SOURCE_DIRS. Create a compact **ARCHITEKTUR-NOTIZ** (max 20 lines): reusable modules/traits/mixins, services/utils, framework patterns.

## Optional Pre-Checks

Only useful when a local diff exists. Skip on a greenfield audit.

```bash
[ -n "$(git status --porcelain)" ] && bash "$AUDIT_BIN/pre-checks.sh"
```

`SECRET_SCAN_RESULT=FINDINGS` → **Critical** in the audit log. `LOCKFILE_DRIFT_RESULT=DRIFT` and `BINARY_ARTIFACTS_RESULT=FINDINGS` → **Important**.

## Phase 1.5: Batching Decision

| TOTAL_FILES | Mode | Rationale |
|---|---|---|
| ≤ 80 | `SINGLE` | One pass |
| > 80 | `BATCHED` | Automatically split into batches |

### Batch Creation (BATCHED only)

```bash
# shellcheck disable=SC2086
for dir in $(find $SOURCE_DIRS -mindepth 1 -maxdepth 2 -type d 2>/dev/null | sort); do
  count=$(find "$dir" -maxdepth 1 \( -name "*.php" -o -name "*.blade.php" -o -name "*.ts" -o -name "*.tsx" -o -name "*.js" -o -name "*.jsx" -o -name "*.vue" -o -name "*.py" \) 2>/dev/null | wc -l)
  [ "$count" -gt 0 ] && echo "$count $dir"
done | sort -rn
```

**Batch rules:**
- Max ~30-40 files per batch
- Related items in the same batch (component + template)
- Directory with >40 files: split into subdirectories
- Directory with <10 files: merge with a related one
- Models/entities + traits/mixins together
- Config + routing together

Output batch overview: `Batch N: directory (X files)`.

## Concurrent Tree Check (Detail)

A full audit runs for minutes across many batches. If the user (or another process) changes the working tree in the meantime, later batches audit a stale state. So record the baseline in Phase 1 and compare again after every batch:

```bash
AUDIT_TREE_HASH=$(git diff HEAD | { md5 2>/dev/null || md5sum | cut -d' ' -f1; })
```

If the value deviates after a batch: warning into the audit log (`## Notes: Tree changed during audit`), reset the next batch to the current state (re-run this reference document's scope collection), update `AUDIT_TREE_HASH`. Discard findings on lines that have meanwhile been overwritten (hallucination risk).

## Intent Docs / Decided Tradeoffs (DECIDED_TRADEOFFS)

Same derivation as /audit (`../audit/references/scope-and-pre-checks.md`, section "Intent-Docs"): glob `docs/adr/`, `docs/adrs/`, `docs/decisions/`, `DESIGN.md`, `PRODUCT.md`, `CONTEXT.md`, summarize decisions in max 15 lines, pass through to all workers. Documented tradeoffs are not findings; code drift from the decision is a docs_sync finding.
