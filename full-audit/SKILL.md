---
name: full-audit
description: "Comprehensive one-time audit of an entire codebase (not just recent changes). Auto-detects framework (Laravel, Next.js, Nuxt, Django), splits large codebases into batches, runs up to 10 parallel subagents per batch (architecture, security, performance, code quality, SEO, a11y, typography, UI design, UX, animation), auto-fixes findings including Minor, runs a cross-reference pass across batches, and generates a manual test plan for visual verification. Triggers: /full-audit, full codebase audit, audit whole project, starting on a new project, comprehensive review. For pre-push audits only, use /audit instead."
argument-hint: "[optional: directory scope]"
model: sonnet
effort: high
context: fork
allowed-tools:
  - Agent
  - Bash
  - Read
  - Edit
  - Write
  - Glob
  - Grep
  - TodoWrite
  - AskUserQuestion
---

# Full Codebase Audit

**SOFORT AUSFÜHREN — nicht erklären, nicht ankündigen. Direkt mit Schritt 1 beginnen.**

Anti-Patterns (rote Flaggen) siehe `~/.claude/skills/audit/references/anti-patterns.md` — Full-Audit fixt zusätzlich ALLE Minor-Findings.

---

## 0. Pre-Flight: Audit-Pfade + Agent-Verifikation

```bash
if [ -d "$HOME/.claude/skills/audit/agents" ]; then
  AUDIT_AGENTS="$HOME/.claude/skills/audit/agents"
  AUDIT_BIN="$HOME/.claude/skills/audit/bin"
  AUDIT_REFS="$HOME/.claude/skills/audit/references"
elif [ -d "$HOME/.claude/skills/claude-skills/audit/agents" ]; then
  AUDIT_AGENTS="$HOME/.claude/skills/claude-skills/audit/agents"
  AUDIT_BIN="$HOME/.claude/skills/claude-skills/audit/bin"
  AUDIT_REFS="$HOME/.claude/skills/claude-skills/audit/references"
else
  echo "ERROR: audit skill not found. Install audit alongside full-audit."
  exit 1
fi
echo "AUDIT_AGENTS=$AUDIT_AGENTS"

# Fail-fast: alle Subagent-Definitionen vorhanden?
bash "$AUDIT_BIN/verify-agents.sh" "$AUDIT_AGENTS" || {
  echo "Full-Audit abgebrochen — fehlende Agent-Dateien."
  exit 1
}
```

---

## 1. Scope & Context ermitteln

```bash
PROJECT_ROOT=$(git rev-parse --show-toplevel)
cd "$PROJECT_ROOT"

# Framework-Erkennung (shared mit /audit) — Output als eval einlesen
eval "$(bash "$AUDIT_BIN/detect-framework.sh")"

# PROJECT_CONTEXT aus CLAUDE.md laden
PROJECT_CLAUDE_MD="$PROJECT_ROOT/CLAUDE.md"
if [ -f "$PROJECT_CLAUDE_MD" ]; then
  PROJECT_CONTEXT=$(sed -n '/^## Audit Context$/,/^## [^A]/p' "$PROJECT_CLAUDE_MD" | head -n -1)
  [ -z "$PROJECT_CONTEXT" ] && PROJECT_CONTEXT="Kein projektspezifischer Kontext."
else
  PROJECT_CONTEXT="Kein projektspezifischer Kontext."
fi

# Alle auditrelevanten Dateien — Build-Output, Vendor und Cache ausschliessen
EXCLUDE='-not -path */node_modules/* -not -path */vendor/* -not -path */.next/* -not -path */.nuxt/* -not -path */dist/* -not -path */build/* -not -path */coverage/* -not -path */.git/*'
# shellcheck disable=SC2086
find $SOURCE_DIRS \( -name "*.php" -o -name "*.blade.php" -o -name "*.ts" -o -name "*.tsx" -o -name "*.js" -o -name "*.jsx" -o -name "*.vue" -o -name "*.svelte" -o -name "*.astro" -o -name "*.py" \) $EXCLUDE 2>/dev/null | sort > /tmp/full-audit-files.txt
TOTAL_FILES=$(wc -l < /tmp/full-audit-files.txt)

# shellcheck disable=SC2086
find $SOURCE_DIRS \( -name "*.blade.php" -o -name "*.css" -o -name "*.scss" -o -name "*.vue" -o -name "*.tsx" -o -name "*.jsx" -o -name "*.svelte" -o -name "*.astro" -o -name "*.html" \) $EXCLUDE 2>/dev/null | sort > /tmp/full-audit-frontend.txt
```

Variablen:
- **ALLE_DATEIEN:** `/tmp/full-audit-files.txt`
- **VISUELL_RELEVANTE_DATEIEN:** `/tmp/full-audit-frontend.txt`
- **TOTAL_FILES**, **PROJECT_CONTEXT**, **FRAMEWORK**, **SOURCE_DIRS**

**Context-Building (einmalig):** Lies `CLAUDE.md`, Package-Manifest, Top-2-Ebenen der SOURCE_DIRS. Erstelle kompakte **ARCHITEKTUR-NOTIZ** (max 20 Zeilen): wiederverwendbare Module/Traits/Mixins, Services/Utils, Framework-Patterns.

**Optionale Pre-Checks** (nur sinnvoll wenn ein lokaler Diff existiert — bei Greenfield-Audit überspringen):

```bash
[ -n "$(git status --porcelain)" ] && bash "$AUDIT_BIN/pre-checks.sh"
```

`SECRET_SCAN_RESULT=FINDINGS` → als **Critical** ins Audit-Log. `LOCKFILE_DRIFT_RESULT=DRIFT` und `BINARY_ARTIFACTS_RESULT=FINDINGS` → als **Important**.

---

## 1.5. Batching-Entscheidung

| TOTAL_FILES | Modus | Begründung |
|-------------|-------|------------|
| ≤ 80 | `SINGLE` | Ein Durchlauf |
| > 80 | `BATCHED` | Automatisch in Batches |

### Batch-Erstellung (nur BATCHED)

```bash
for dir in $(find $SOURCE_DIRS -mindepth 1 -maxdepth 2 -type d 2>/dev/null | sort); do
  count=$(find "$dir" -maxdepth 1 \( -name "*.php" -o -name "*.blade.php" -o -name "*.ts" -o -name "*.tsx" -o -name "*.js" -o -name "*.jsx" -o -name "*.vue" -o -name "*.py" \) 2>/dev/null | wc -l)
  [ "$count" -gt 0 ] && echo "$count $dir"
done | sort -rn
```

**Batch-Regeln:**
- Max ~30-40 Dateien pro Batch
- Zusammengehöriges im selben Batch (Komponente + Template)
- Verzeichnis >40 Dateien: Unterverzeichnisse aufsplitten
- Verzeichnis <10 Dateien: mit verwandtem zusammenlegen
- Models/Entities + Traits/Mixins zusammen
- Config + Routing zusammen

Batch-Übersicht ausgeben (`Batch N: verzeichnis (X Dateien)`).

---

## 2. Audit-Loop

Initialisiere:
```
RUNDE = 1
BEREITS_GEFIXT = []
GESAMT_CRITICAL = 0; GESAMT_IMPORTANT = 0; GESAMT_MINOR = 0
AKTUELLER_BATCH = 1
FINDINGS_VORHERIGE_RUNDE = null   # pro Batch zurücksetzen
```

**Convergence-Check:** Pro Batch, nach jeder Runde: Wenn Critical+Important NICHT sinken UND RUNDE ≥ 2 → `NO_CONVERGENCE`, verbleibende Findings als Offene Punkte.

### Modus SINGLE (TOTAL_FILES ≤ 80)

Alle Dateien in einer Runde, max 3 Runden bis SAUBER. → Springe zu **Prozedur AUDIT_RUNDE**.

### Modus BATCHED

```
for BATCH in 1..N:
    RUNDE = 1
    BATCH_SAUBER = false
    while RUNDE <= 3 AND NOT BATCH_SAUBER:
        Führe AUDIT_RUNDE aus mit DATEILISTE = Batch-Dateien
        if SAUBER: BATCH_SAUBER = true
        else: RUNDE += 1
    AKTUELLER_BATCH += 1
```

---

### Prozedur AUDIT_RUNDE

**Schritt A — Ankündigung**

BATCHED: `Full-Audit — Batch {AKTUELLER_BATCH}/{N} ({BATCH_VERZEICHNIS}) — {X} Dateien — Runde {RUNDE}/3`
SINGLE: `Full-Audit Runde {RUNDE}/3 — {TOTAL_FILES} Dateien`

TodoWrite: `Runde {RUNDE} — Subagents dispatchen` (in_progress), `Runde {RUNDE} — Findings fixen` (pending).

**Schritt A — 10 Subagents parallel dispatchen**

**PFLICHT: In JEDER Runde werden ALLE zulässigen Subagents dispatcht.** Fixes können Issues in beliebigen Dimensionen einführen. Einzige Ausnahme: Frontend-Subagents (5-10) bei Batches ohne Frontend-Dateien.

Dispatche alle in **einem Message-Block**. Übergib ARCHITEKTUR-NOTIZ + PROJECT_CONTEXT + FRAMEWORK + SOURCE_DIRS + **nur die Batch-Dateien**.

Agent-Definitionen: `{AUDIT_AGENTS}/*.md` — jede Datei definiert `subagent_type` und `model`.

| # | Agent | Kurzname |
|---|---|---|
| 1 | `1-architecture.md` | Architektur & Code Reuse |
| 2 | `2-security.md` | Security |
| 3 | `3-performance.md` | Performance |
| 4 | `4-code-quality.md` | Code Quality |
| 5 | `5-seo.md` | SEO & Semantic HTML |
| 6 | `6-a11y.md` | Accessibility (WCAG) |
| 7 | `7-typography.md` | Typography |
| 8 | `8-ui-design.md` | UI Visual Design |
| 9 | `9-ux.md` | UX Patterns & Interaction |
| 10 | `10-animation.md` | Animation & Motion Design |

Prompt-Template: `{AUDIT_AGENTS}/prompt-template.md` → Abschnitt "Für /full-audit".

**Überspringen-Regeln:**

| Agent | Überspringen wenn |
|-------|-------------------|
| 5 (SEO) | Keine Frontend-Dateien |
| 6 (A11y) | Keine Frontend-Dateien |
| 7 (Typography) | Weder Frontend- noch Translation-Dateien |
| 8 (UI Design) | Keine Frontend-Dateien |
| 9 (UX) | Keine Frontend-Dateien |
| 10 (Animation) | Keine Frontend-Dateien |

Agents 5-10 laufen bei ALLEN Frontend-Dateien — auch app-interne Views. "Öffentlich vs. intern" irrelevant.

**Schritt B — Konsolidieren**

Deduplizierung: Gleiche Stelle von mehreren Subagents → ein Finding, strengste Einstufung.

**Schritt B.5 — Hallucination Validator (PFLICHT)**

Vor jedem Fix deterministisch prüfen:

1. **Datei existiert:** `test -f "{datei}"` — nein → verwerfen
2. **Zeile in Range:** `wc -l "{datei}"` — Zeile > Dateilänge → verwerfen
3. **Externe APIs:** Library/Framework/Paket nicht direkt im Projekt sichtbar? → via context7 oder Grep in `vendor/`/`node_modules/` verifizieren. Nicht verifizierbar → `low confidence`.

Verworfene als `HALLUCINATED: ...` loggen, nicht fixen.

Prüfe SELBST (nur Runde 1, Batch 1):
- Tests: wichtige Services/Commands ohne Tests?
- Dokumentation: CLAUDE.md aktuell?
- Mobile Apps: `bash "$AUDIT_BIN/detect-mobile.sh"` — bei Treffer Impact-Matrix aus `{AUDIT_REFS}/mobile-impact.md` anwenden.

Ausgabe:
```
## Full Audit — Batch {AKTUELLER_BATCH}/{N} Runde {RUNDE}/3 — X Critical, Y Important, Z Minor

### Critical
- [Dimension] datei:zeile — Beschreibung
### Important
- [Dimension] datei:zeile — Beschreibung
### Minor
- [Dimension] datei:zeile — Vorschlag
### Sauber
Dimension1, Dimension2
```

**Schritt C — Auto-Fix (ALLE Findings)**

TodoWrite: `Runde {RUNDE} — Findings fixen` (in_progress).

**Grundregel: Alles wird gefixt — außer `low confidence`.**

Confidence-Gate:
- `high` → direkt fixen
- `medium` → fixen, im Log dokumentieren
- `low` → NICHT fixen, als Offener Punkt

- 0 Findings → `SAUBER`
- Sonst: alle high/medium fixen. Einfach selbst, komplex parallele Fix-Subagents (Problem, Datei:Zeile, Erwartung, Testbefehl).
- Jeden Fix zu BEREITS_GEFIXT. GESAMT_* inkrementieren.
- Ergebnis: `FIXES_APPLIED`.

**Kein "Offener Punkt" ohne explizite User-Zustimmung.** Unklarer Fix → kurz nachfragen.

### Nach jeder Runde

| Ergebnis | RUNDE | Aktion |
|---|---|---|
| `SAUBER` | — | Nächster Batch (oder 2.5) |
| `FIXES_APPLIED` | < 3 | Convergence-Check; sonst RUNDE+1 |
| `FIXES_APPLIED` | = 3 | Nächster Batch (oder 2.5) |
| `NO_CONVERGENCE` | — | Batch abbrechen, offene Findings als Offene Punkte |

---

## 2.5. Cross-Reference-Runde (nur BATCHED)

Nach allen Batches — 2 Subagents parallel:

| # | Fokus | Scope |
|---|---|---|
| 1 | Cross-Module-Abhängigkeiten | Services ↔ UI falsch aufgerufen, Models ↔ Traits/Mixins falsch genutzt, Controller-View-Mismatches |
| 2 | Konsistenz | Gleiche Patterns einheitlich? (Auth-Checks, Cache-Keys, Error-Handling) |

Input: ARCHITEKTUR-NOTIZ + BEREITS_GEFIXT + Zusammenfassung aller Batch-Findings.
Fixes wie Schritt C. Keine weiteren Runden danach.

---

## 3. Changelog, Linter, Tests, Design-Verification

### 3a. Changelog

Suche `CHANGELOG.md`, `changelog.md`, `release-notes/next.md`, `resources/changelog.md`, `CHANGES.md`. Keine gefunden → überspringen. User-facing Fixes (UI, API, Routing, Translations) → Eintrag draften.

### 3b. Linter & Static Analysis

Siehe `{AUDIT_REFS}/linters-and-tests.md`. **Im Full-Audit-Modus laufen alle Linter/Formatter global** (nicht datei-scoped). Bei Fehlern: manuell fixen, erneut laufen.

### 3c. Tests

Siehe `{AUDIT_REFS}/linters-and-tests.md` (Test-Runner-Tabelle). Alle erkannten Runner ausführen. Failures fixen, erneut. Unfixbare als Offener Punkt.

### 3d. Manueller Testplan erstellen

```bash
bash "$AUDIT_BIN/design-check.sh" --full
```

Wenn `DESIGN_CHECK_RESULT=SCREENSHOTS_ERFORDERLICH`: Erstelle einen manuellen Testplan mit den wichtigsten Seiten/Komponenten, die visuell geprueft werden sollten. Gleiches Format wie in `/audit` — konkrete Schritte, URLs/Routes, max. 15 Schritte (mehr als /audit, weil Full-Audit die gesamte Codebase umfasst).

Wenn `KEINE_VISUELLEN_DATEIEN` → weiter mit Abschnitt 4.

---

## 4. Audit-Log schreiben

```bash
AUDIT_DIR="$(git rev-parse --show-toplevel)/.claude/audits"
mkdir -p "$AUDIT_DIR"
LOGFILE="$AUDIT_DIR/$(date +%Y-%m-%d_%H%M%S)-full-audit.md"
```

Format:

```markdown
# Full Audit — {DATUM}

## Scope
- Modus: SINGLE | BATCHED ({N} Batches)
- Backend-Dateien: X
- Frontend-Dateien: Y
- Runden gesamt: Z

## Ergebnis
- Critical gefunden/gefixt: A/B
- Important gefunden/gefixt: C/D
- Minor gefunden/gefixt: E/F

## Gefixte Issues
- [Security] app/Foo.php:42 — XSS via {!! !!} → durch {{ }} ersetzt

## Manueller Testplan
- (Testplan-Schritte, falls visuelle Dateien vorhanden)

## Offene Punkte
- [Code Quality] app/Baz.php — Refactoring nötig (nicht auto-fixbar)

## Sauber
Performance, SEO
```

**Offene Punkte umsetzen:** Wenn `## Offene Punkte` Einträge enthält, User via AskUserQuestion fragen.

Optionen:
- **Ja, alle** — alle jetzt umsetzen
- **Einzeln entscheiden** — pro Punkt bestätigen
- **Nein, später** — im Log belassen

---

## 5. Learning

```
Agent(
  prompt: "Lies {AUDIT_AGENTS}/learning-agent.md und führe den Ablauf aus.
    PROJECT_ROOT={PROJECT_ROOT}
    AKTUELLES_LOG={Inhalt des Audit-Logs}
    AUDIT_TYPE=full-audit",
  subagent_type: general-purpose,
  mode: bypassPermissions,
  run_in_background: true
)
```

Läuft im Hintergrund. Wenn `GUIDELINE_SUGGESTIONS > 0` zurückkommt: User via AskUserQuestion zeigen (gleiche Logik wie /audit).

---

## Abschluss

```
Full Audit abgeschlossen.
- Modus: {BATCH_MODUS} ({N} Batches, {RUNDEN_GESAMT} Runden)
- {GESAMT_CRITICAL} Critical, {GESAMT_IMPORTANT} Important, {GESAMT_MINOR} Minor gefunden und gefixt
- Log: .claude/audits/{DATUM}-full-audit.md
- Learning: läuft im Hintergrund → .claude/audits/learning-log.md
```
