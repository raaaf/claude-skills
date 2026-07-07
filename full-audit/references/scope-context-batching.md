# Scope, Context, Batching (Phase 1 + 1.5 Detail)

Detail-Bash und Batching-Heuristik fuer Phase 1 (Scope & Context) und Phase 1.5 (Batching-Entscheidung). Wird vom Orchestrator gelesen.

Inhalt: Phase 1 Scope-Bash · Context-Building · Optionale Pre-Checks · Phase 1.5 Batching · Concurrent-Tree-Check

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

Variablen aus den Outputs:
- **ALLE_DATEIEN:** `/tmp/full-audit-files.txt`
- **VISUELL_RELEVANTE_DATEIEN:** `/tmp/full-audit-frontend.txt`
- **TRANSLATION_DATEIEN:** `/tmp/full-audit-translations.txt`
- **TOTAL_FILES**, **PROJECT_CONTEXT**, **FRAMEWORK**, **SOURCE_DIRS**, **SUPPRESSIONS**

## Context-Building (einmalig)

Lies `CLAUDE.md`, Package-Manifest, Top-2-Ebenen der SOURCE_DIRS. Erstelle kompakte **ARCHITEKTUR-NOTIZ** (max 20 Zeilen): wiederverwendbare Module/Traits/Mixins, Services/Utils, Framework-Patterns.

## Optionale Pre-Checks

Nur sinnvoll wenn ein lokaler Diff existiert. Bei Greenfield-Audit ueberspringen.

```bash
[ -n "$(git status --porcelain)" ] && bash "$AUDIT_BIN/pre-checks.sh"
```

`SECRET_SCAN_RESULT=FINDINGS` → als **Critical** ins Audit-Log. `LOCKFILE_DRIFT_RESULT=DRIFT` und `BINARY_ARTIFACTS_RESULT=FINDINGS` → als **Important**.

## Phase 1.5: Batching-Entscheidung

| TOTAL_FILES | Modus | Begruendung |
|---|---|---|
| ≤ 80 | `SINGLE` | Ein Durchlauf |
| > 80 | `BATCHED` | Automatisch in Batches |

### Batch-Erstellung (nur BATCHED)

```bash
# shellcheck disable=SC2086
for dir in $(find $SOURCE_DIRS -mindepth 1 -maxdepth 2 -type d 2>/dev/null | sort); do
  count=$(find "$dir" -maxdepth 1 \( -name "*.php" -o -name "*.blade.php" -o -name "*.ts" -o -name "*.tsx" -o -name "*.js" -o -name "*.jsx" -o -name "*.vue" -o -name "*.py" \) 2>/dev/null | wc -l)
  [ "$count" -gt 0 ] && echo "$count $dir"
done | sort -rn
```

**Batch-Regeln:**
- Max ~30-40 Dateien pro Batch
- Zusammengehoeriges im selben Batch (Komponente + Template)
- Verzeichnis >40 Dateien: Unterverzeichnisse aufsplitten
- Verzeichnis <10 Dateien: mit verwandtem zusammenlegen
- Models/Entities + Traits/Mixins zusammen
- Config + Routing zusammen

Batch-Uebersicht ausgeben: `Batch N: verzeichnis (X Dateien)`.

## Concurrent-Tree-Check (Detail)

Ein Full-Audit laeuft minutenlang ueber viele Batches. Aendert der User (oder ein anderer Prozess) waehrenddessen den Working-Tree, auditieren spaetere Batches einen veralteten Stand. Deshalb in Phase 1 die Baseline festhalten und nach jedem Batch vergleichen:

```bash
AUDIT_TREE_HASH=$(git diff HEAD | { md5 2>/dev/null || md5sum | cut -d' ' -f1; })
```

Weicht der Wert nach einem Batch ab: Warnung ins Audit-Log (`## Hinweise: Tree waehrend Audit veraendert`), den naechsten Batch auf den aktuellen Stand resetten (Scope-Erhebung dieses references-Dokuments erneut ausfuehren), `AUDIT_TREE_HASH` aktualisieren. Findings auf inzwischen ueberschriebenen Zeilen verwerfen (Halluzinations-Risiko).
