---
name: full-audit
description: "Use when the user says /full-audit, wants a comprehensive one-time audit of the entire codebase, is starting on a new project, or hasn't audited in a while. Processes large codebases in batches with 7 parallel subagents. For pre-push audits of unpushed commits only, use /audit instead."
model: sonnet
effort: high
context: fork
disable-model-invocation: true
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

**ROTE FLAGGEN — sofort stoppen wenn du denkst:**
- "Ich warte auf Bestätigung vom User bevor ich die nächste Runde starte" → FALSCH. Loop läuft autonom.
- "Eine Runde reicht" → FALSCH. Erst wenn `SAUBER`, ist der Loop beendet.
- "Ich erkläre jetzt den Plan" → FALSCH. Direkt ausführen.
- "Das Finding ist Minor, das überspringe ich" → FALSCH. Full-Audit fixt ALLES.
- "Design-Verification kann ich überspringen weil..." → FALSCH. Das Bash-Script entscheidet deterministisch ob Screenshots gemacht werden. Wenn `DESIGN_CHECK_RESULT=SCREENSHOTS_ERFORDERLICH`, wird der Screenshot-Agent dispatcht. Du hast kein Ermessen. Du interpretierst das Script-Ergebnis nicht.

---

## 0. Audit-Agents-Pfad auflösen

```bash
# Find the audit agents directory (works with symlinks, mono-repo, or standalone install)
if [ -d "$HOME/.claude/skills/audit/agents" ]; then
  AUDIT_AGENTS="$HOME/.claude/skills/audit/agents"
elif [ -d "$HOME/.claude/skills/claude-skills/audit/agents" ]; then
  AUDIT_AGENTS="$HOME/.claude/skills/claude-skills/audit/agents"
else
  echo "ERROR: audit/agents/ not found. Install the audit skill alongside full-audit."
  exit 1
fi
echo "AUDIT_AGENTS=$AUDIT_AGENTS"
```

Setze `{AUDIT_AGENTS}` in allen folgenden Agent-Referenzen auf den gefundenen Pfad.

---

## 1. Scope & Context ermitteln

```bash
PROJECT_ROOT=$(git rev-parse --show-toplevel)
cd "$PROJECT_ROOT"

# Framework-Erkennung
if [ -f "artisan" ]; then
  FRAMEWORK="laravel"
  SOURCE_DIRS="app/ resources/ database/ routes/ config/"
elif [ -f "package.json" ] && grep -q '"next"' package.json 2>/dev/null; then
  FRAMEWORK="nextjs"
  SOURCE_DIRS="src/ app/ pages/ components/ lib/"
elif [ -f "nuxt.config.ts" ] || [ -f "nuxt.config.js" ]; then
  FRAMEWORK="nuxt"
  SOURCE_DIRS="components/ composables/ pages/ layouts/ server/"
elif [ -f "manage.py" ]; then
  FRAMEWORK="django"
  SOURCE_DIRS="$(find . -name 'apps.py' -exec dirname {} \; | head -20 | tr '\n' ' ')"
else
  FRAMEWORK="generic"
  SOURCE_DIRS="src/ lib/ app/"
fi

echo "FRAMEWORK=$FRAMEWORK"
echo "SOURCE_DIRS=$SOURCE_DIRS"

# PROJECT_CONTEXT laden
PROJECT_CLAUDE_MD="$PROJECT_ROOT/CLAUDE.md"
if [ -f "$PROJECT_CLAUDE_MD" ]; then
  PROJECT_CONTEXT=$(sed -n '/^## Audit Context$/,/^## [^A]/p' "$PROJECT_CLAUDE_MD" | head -n -1)
  [ -z "$PROJECT_CONTEXT" ] && PROJECT_CONTEXT="Kein projektspezifischer Kontext."
else
  PROJECT_CONTEXT="Kein projektspezifischer Kontext."
fi
echo "PROJECT_CONTEXT: $PROJECT_CONTEXT"

# Alle auditrelevanten Dateien sammeln
find $SOURCE_DIRS -name "*.php" -o -name "*.blade.php" -o -name "*.ts" -o -name "*.tsx" -o -name "*.js" -o -name "*.jsx" -o -name "*.vue" -o -name "*.py" 2>/dev/null | grep -v node_modules | grep -v vendor | sort > /tmp/full-audit-files.txt
TOTAL_FILES=$(wc -l < /tmp/full-audit-files.txt)

find $SOURCE_DIRS -name "*.blade.php" -o -name "*.css" -o -name "*.js" -o -name "*.vue" -o -name "*.tsx" -o -name "*.jsx" -o -name "*.scss" -o -name "*.html" 2>/dev/null | grep -v node_modules | grep -v vendor | sort > /tmp/full-audit-frontend.txt

# Verzeichnisstruktur
for dir in $SOURCE_DIRS; do [ -d "$dir" ] && ls "$dir" 2>/dev/null; done
```

Erstelle:
- **ALLE_DATEIEN:** Alle auditrelevanten Dateien (aus `/tmp/full-audit-files.txt`)
- **VISUELL_RELEVANTE_DATEIEN:** Alle Frontend-Dateien (aus `/tmp/full-audit-frontend.txt`)
- **TOTAL_FILES:** Gesamtanzahl auditrelevanter Dateien
- **PROJECT_CONTEXT:** Projektspezifischer Audit-Kontext (aus CLAUDE.md)
- **FRAMEWORK:** Erkanntes Framework
- **SOURCE_DIRS:** Erkannte Source-Verzeichnisse

**Context-Building (einmalig, vor dem Audit-Loop):**

Lies folgende Dateien für Architektur-Kontext:
- `CLAUDE.md` (Konventionen, Projektspezifisches)
- Package-Manifest (`composer.json`, `package.json`, `pyproject.toml` — je nach Framework)
- Projekt-Verzeichnisstruktur (oberste 2 Ebenen von SOURCE_DIRS)

Erstelle daraus eine kompakte **ARCHITEKTUR-NOTIZ** (max 20 Zeilen):
- Welche wiederverwendbaren Module/Traits/Mixins existieren
- Welche Services/Utils existieren
- Welche Framework-spezifischen Patterns das Projekt verwendet (aus PROJECT_CONTEXT)

---

## 1.5. Batching-Entscheidung

```
DESIGN_CHECK: TOTAL_FILES = {TOTAL_FILES}
```

**Entscheidungslogik:**

| TOTAL_FILES | Modus | Begründung |
|-------------|-------|------------|
| <= 80 | `SINGLE` | Codebase klein genug — alle Dateien in einem Durchlauf |
| > 80 | `BATCHED` | Codebase zu groß für einen Durchlauf — automatisch in Batches aufteilen |

Ausgabe:

```
BATCH_MODUS: SINGLE | BATCHED
Codebase-Größe: {TOTAL_FILES} Dateien
```

### Batch-Erstellung (nur wenn BATCH_MODUS = BATCHED)

Dateien automatisch nach Verzeichnisstruktur gruppieren:

```bash
# Verzeichnisse mit Dateianzahl auflisten
for dir in $(find $SOURCE_DIRS -mindepth 1 -maxdepth 2 -type d 2>/dev/null | sort); do
  count=$(find "$dir" -maxdepth 1 \( -name "*.php" -o -name "*.blade.php" -o -name "*.ts" -o -name "*.tsx" -o -name "*.js" -o -name "*.jsx" -o -name "*.vue" -o -name "*.py" \) 2>/dev/null | wc -l)
  [ "$count" -gt 0 ] && echo "$count $dir"
done | sort -rn
```

**Batch-Regeln:**
- Max ~30-40 Dateien pro Batch
- Zusammengehörige Dateien im selben Batch (UI-Komponente + zugehöriges Template)
- Wenn ein Verzeichnis >40 Dateien hat: Unterverzeichnisse als separate Batches
- Wenn ein Verzeichnis <10 Dateien hat: mit verwandtem Verzeichnis zusammenlegen
- Models/Entities + Traits/Mixins zusammen (brauchen gegenseitigen Kontext)
- Config + Routing zusammen (klein, zusammengehörig)

**Batch-Übersicht ausgeben:**

```
Batches: {N}
  Batch 1: src/components/events/ (32 Dateien)
  Batch 2: src/components/groups/ (28 Dateien)
  Batch 3: src/services/ + src/utils/ (25 Dateien)
  Batch 4: src/models/ + src/types/ (18 Dateien)
  Batch 5: templates/pages/ (35 Dateien)
  Batch 6: templates/layouts/ + templates/components/ (22 Dateien)
  Batch 7: config/ + routes/ + database/ (15 Dateien)
```

---

## 2. Audit-Loop

Initialisiere:
```
RUNDE = 1
BEREITS_GEFIXT = []
GESAMT_CRITICAL = 0
GESAMT_IMPORTANT = 0
GESAMT_MINOR = 0
AKTUELLER_BATCH = 1
```

### Modus SINGLE (TOTAL_FILES <= 80)

Wie bisher: Alle Dateien in einer Runde auditieren. Max 3 Runden bis SAUBER.

→ Springe zu **Prozedur AUDIT_RUNDE** mit DATEILISTE = alle Dateien.

### Modus BATCHED (TOTAL_FILES > 80)

Äußere Schleife über alle Batches. Pro Batch max 3 Runden.

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

**Schritt 0 — Ankündigung und Todos**

Ausgabe (BATCHED):
```
Full-Audit — Batch {AKTUELLER_BATCH}/{N} ({BATCH_VERZEICHNIS}) — {BATCH_DATEIEN_ANZAHL} Dateien — Runde {RUNDE}/3
```

Ausgabe (SINGLE):
```
Full-Audit Runde {RUNDE}/3 — {TOTAL_FILES} Dateien
```

TodoWrite: Erstelle Todos:
- `Batch {AKTUELLER_BATCH}/{N} Runde {RUNDE} — Subagents dispatchen` (in_progress)
- `Batch {AKTUELLER_BATCH}/{N} Runde {RUNDE} — Findings fixen` (pending)

(Im SINGLE-Modus ohne "Batch"-Prefix.)

**Schritt A — 7 Subagents parallel dispatchen**

**PFLICHT: In JEDER Runde werden ALLE zulässigen Subagents dispatcht.** Keine Subagents weglassen weil in der vorherigen Runde keine Findings in einer Dimension waren. Fixes können Issues in beliebigen Dimensionen einführen. Einzige Ausnahme: Frontend-Subagents (5-7) werden übersprungen wenn der Batch keine Frontend-Dateien enthält.

Dispatche alle Subagents **in einem einzigen Message-Block**. Übergib ARCHITEKTUR-NOTIZ + PROJECT_CONTEXT + FRAMEWORK + SOURCE_DIRS + **nur die Dateien des aktuellen Batches** (nicht alle Dateien!).

Lies die Agent-Definitionen aus {AUDIT_AGENTS}/*.md.

Jede Agent-Datei definiert `subagent_type` (bestimmt die verfügbaren Tools des Subagents) und `model` (opus = Claude Opus, haiku = Claude Haiku — Opus für tiefere Analyse, Haiku für schnellere Pattern-Checks).

| # | Agent-Datei | Kurzname |
|---|-------------|----------|
| 1 | `{AUDIT_AGENTS}/1-architecture.md` | Architektur & Code Reuse |
| 2 | `{AUDIT_AGENTS}/2-security.md` | Security |
| 3 | `{AUDIT_AGENTS}/3-performance.md` | Performance |
| 4 | `{AUDIT_AGENTS}/4-code-quality.md` | Code Quality |
| 5 | `{AUDIT_AGENTS}/5-seo.md` | SEO & Semantic HTML |
| 6 | `{AUDIT_AGENTS}/6-a11y.md` | UI/UX & A11y |
| 7 | `{AUDIT_AGENTS}/7-typography.md` | Typography |

Prompt-Template: Siehe `{AUDIT_AGENTS}/prompt-template.md` — verwende den Abschnitt "Für /full-audit (Codebase-basiert)".

**Überspringen-Regeln:**
- Keine Frontend-Dateien im Batch? Subagents 5 und 6 überspringen.
- Subagent 5 (SEO) überspringen wenn keine Layout-Dateien mit `<head>` im Batch.
- Subagent 7 (Typography) überspringen wenn weder Frontend-Dateien noch Translation-Dateien im Batch.

**Schritt B — Konsolidieren**

Deduplizierung: Gleiche Stelle von mehreren Subagents → ein Finding, strengste Einstufung.

Prüfe SELBST (nur in Runde 1, Batch 1):
- Tests: Wichtige Services/Commands ohne Tests?
- Dokumentation: CLAUDE.md aktuell?
- Mobile Apps: Gibt es eine zugehörige iOS-/Android-App im Repo? (Prüfe auf `.xcodeproj`, `build.gradle`, `react-native` in package.json, `pubspec.yaml`, `capacitor.config.*`) Wenn ja: API-Kompatibilität, Shared Code, Deep Links, Push-Payloads prüfen. Breaking Changes als Important melden.

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

TodoWrite: `Batch {AKTUELLER_BATCH}/{N} Runde {RUNDE} — Findings fixen` (in_progress)

**Grundregel: Alles wird gefixt. Kein Finding bleibt offen.**

- 0 Critical + 0 Important + 0 Minor → Markiere Todo als completed. Ergebnis: `SAUBER`
- Sonst: **Alle** Critical, Important und Minor fixen — ohne Ausnahme.
  - Einfache Fixes direkt selbst durchführen.
  - Komplexe/größere Fixes: parallele Subagents dispatchen (je ein Agent pro unabhängigem Fix-Bereich).
  - Subagents bekommen: genaues Problem, Datei:Zeile, erwartetes Ergebnis, Testbefehl.
  - Warten bis alle Subagents abgeschlossen, dann Ergebnisse prüfen.
- Jeden Fix zu BEREITS_GEFIXT hinzufügen.
- GESAMT_CRITICAL += dieser Runde. GESAMT_IMPORTANT += dieser Runde. GESAMT_MINOR += dieser Runde.
- Markiere Todo als completed. Ergebnis: `FIXES_APPLIED`

**Kein "Offener Punkt" ohne explizite User-Zustimmung.** Wenn ein Fix unklar ist: kurz nachfragen, dann umsetzen.

### Nach jeder Runde

| Ergebnis | RUNDE | Aktion |
|----------|-------|--------|
| `SAUBER` | egal | Batch abgeschlossen → nächster Batch (oder Schritt 2.5 wenn letzter Batch) |
| `FIXES_APPLIED` | < 3 | RUNDE + 1 → Prozedur erneut |
| `FIXES_APPLIED` | = 3 | Batch abgeschlossen → nächster Batch (oder Schritt 2.5 wenn letzter Batch) |

---

## 2.5. Cross-Reference-Runde (nur BATCHED-Modus)

Nach allen Batches eine letzte Runde über Batch-Grenzen hinweg:

Dispatche 2 Subagents parallel:

| # | Fokus | Scope |
|---|-------|-------|
| 1 | Cross-Module-Abhängigkeiten | Services die von UI-Komponenten falsch aufgerufen werden, Models/Entities die Mixins/Traits falsch nutzen, Controller/Handler-View-Mismatches |
| 2 | Konsistenz | Gleiche Patterns überall einheitlich? (z.B. Auth-Checks, Cache-Key-Formate, Error-Handling) |

Jeder bekommt: ARCHITEKTUR-NOTIZ + BEREITS_GEFIXT + Zusammenfassung aller Batch-Findings.

Findings fixen wie in Schritt C.

Keine weiteren Runden — Cross-Reference-Findings werden einmalig gefixt. Danach weiter mit Abschnitt 3.

---

## 3. Changelog, Linter, Tests und Design-Verification (einmal, nach dem Loop)

### 3a. Changelog/Release-Notes prüfen

Prüfe ob die Fixes user-facing Changes enthalten die einen Changelog-Eintrag brauchen.

Suche nach typischen Changelog-Dateien: `CHANGELOG.md`, `changelog.md`, `release-notes/next.md`, `resources/changelog.md`, `CHANGES.md`. Keine gefunden → Abschnitt überspringen.

Wenn Changelog-Datei existiert und Fixes user-facing sind (UI, API, Routing, Translations): Eintrag draften.

### 3b. Linter & Static Analysis

Reihenfolge: Formatter → Linter → Static Analysis. Automatisch erkennen:

**PHP:**

| Erkennungsmerkmal | Befehl | Scope |
|---|---|---|
| `composer.json` mit `pint`-Dependency | `./vendor/bin/pint` | Global (Full-Audit) |
| `.php-cs-fixer.php` | `./vendor/bin/php-cs-fixer fix` | Global |
| `composer.json` mit `phpcs`-Script | `composer phpcs:fix` | Global |
| `phpstan.neon` | `./vendor/bin/phpstan analyse` | Global |

**JavaScript/CSS:**

| Erkennungsmerkmal | Befehl | Scope |
|---|---|---|
| `eslint.config.*` oder `.eslintrc*` | `npx eslint --fix .` | Global |
| `.prettierrc*` oder `prettier.config.*` | `npx prettier --write .` | Global |
| `.stylelintrc*` | `npx stylelint --fix "**/*.css"` | Global |

Bei Static-Analysis-Fehlern: manuell fixen, erneut laufen lassen. Wiederholen bis sauber.

**PHPCS: pre-existierende Fehler**

IMMER alle PHPCS-Fehler beheben — auch in Dateien die nicht vom Audit gefixt wurden. CI prüft das gesamte Repo. Nur Warnings (nicht Errors) können ignoriert werden.

### 3c. Tests

Test-Runner automatisch erkennen:

| Erkennungsmerkmal | Befehl |
|---|---|
| `composer.json` mit `test`-Script | `composer test` |
| `package.json` mit `test`-Script | `npm test` |
| `phpunit.xml` (ohne Composer-Script) | `php artisan test` oder `./vendor/bin/phpunit` |
| `vitest.config.*` | `npx vitest run` |
| `jest.config.*` | `npx jest` |
| `pytest.ini` oder `pyproject.toml` mit pytest | `pytest` |

Alle erkannten Runner ausführen. Bei Failures: fixen, erneut laufen lassen. Unfixbare Failures als Offener Punkt.

**CHECKPOINT — PFLICHT-AUSGABE nach Tests (vor Schritt 3d):**

**CHECKPOINT — DETERMINISTISCHER DESIGN-CHECK (kein LLM-Ermessen)**

Führe dieses Bash-Script aus. Das Ergebnis bestimmt ob Design-Verification stattfindet — nicht deine Einschätzung.

```bash
PROJECT_ROOT=$(git rev-parse --show-toplevel)
# Für /full-audit: alle Frontend-Dateien in der Codebase
VISUAL_FILES=$(find "$PROJECT_ROOT" -type f \( -name "*.blade.php" -o -name "*.html" -o -name "*.vue" -o -name "*.tsx" -o -name "*.jsx" -o -name "*.css" -o -name "*.scss" \) -not -path "*/vendor/*" -not -path "*/node_modules/*" 2>/dev/null)

# Framework-spezifische visuell relevante Backend-Dateien
if [ -f "$PROJECT_ROOT/artisan" ]; then
  BACKEND_VISUAL_FILES=$(find "$PROJECT_ROOT/app/Livewire" -name "*.php" 2>/dev/null)
elif [ -f "$PROJECT_ROOT/package.json" ] && grep -q '"next"' "$PROJECT_ROOT/package.json" 2>/dev/null; then
  BACKEND_VISUAL_FILES=$(find "$PROJECT_ROOT/src" "$PROJECT_ROOT/app" -name "*.tsx" -o -name "*.jsx" 2>/dev/null)
elif [ -f "$PROJECT_ROOT/nuxt.config.ts" ] || [ -f "$PROJECT_ROOT/nuxt.config.js" ]; then
  BACKEND_VISUAL_FILES=$(find "$PROJECT_ROOT/components" "$PROJECT_ROOT/pages" "$PROJECT_ROOT/layouts" -name "*.vue" 2>/dev/null)
else
  BACKEND_VISUAL_FILES=""
fi

ALL_VISUAL="$VISUAL_FILES"$'\n'"$BACKEND_VISUAL_FILES"
ALL_VISUAL=$(echo "$ALL_VISUAL" | grep -v '^$' | sort -u)
if [ -n "$ALL_VISUAL" ]; then
  COUNT=$(echo "$ALL_VISUAL" | wc -l | tr -d ' ')
  echo "DESIGN_CHECK_RESULT=SCREENSHOTS_ERFORDERLICH"
  echo "DATEIEN: $COUNT visuelle Dateien in Codebase"
else
  echo "DESIGN_CHECK_RESULT=KEINE_VISUELLEN_DATEIEN"
fi
```

**Auswertung — binär, EINE Zeile Code:**

```
if output contains "SCREENSHOTS_ERFORDERLICH" → dispatche Screenshot-Agent (Schritt 3d)
if output contains "KEINE_VISUELLEN_DATEIEN" → weiter mit Abschnitt 4
```

Du interpretierst NICHTS. Du führst das Script aus und folgst der Logik oben.

### 3d. Design-Verification — Screenshot-Agent dispatchen

**DIESER SCHRITT IST EIN EINZIGER TOOL-CALL.** Du übergibst alles an den Screenshot-Agent und wartest auf sein Ergebnis. Du machst NICHTS selbst — kein Server starten, keine URLs ermitteln, kein Screenshot-Verzeichnis anlegen. Das macht alles der Screenshot-Agent.

```
Agent(
  subagent_type: general-purpose,
  model: sonnet,
  prompt: "Lies {AUDIT_AGENTS}/screenshot-agent.md und führe den kompletten Ablauf aus.
    PROJECT_ROOT={PROJECT_ROOT}
    VISUELL_RELEVANTE_DATEIEN={DATEIEN_AUS_BASH_CHECK}
    FRAMEWORK={FRAMEWORK}"
)
```

Warte auf das Ergebnis. Werte `DESIGN_VERIFICATION_RESULT` aus:

| Ergebnis | Aktion |
|----------|--------|
| `GO` | TodoWrite completed. Weiter mit Abschnitt 4. |
| `MANUELL` | Warte auf User-Nachricht ("go" / "weiter"). Dann weiter mit Abschnitt 4. |
| `SKIPPED_NO_TOOL` | Im Audit-Log vermerken. Weiter mit Abschnitt 4. |

---

## 4. Audit-Log schreiben

```bash
AUDIT_DIR="$(git rev-parse --show-toplevel 2>/dev/null)/.claude/audits"
mkdir -p "$AUDIT_DIR"
DATUM=$(date +%Y-%m-%d)
LOGFILE="$AUDIT_DIR/$DATUM-full-audit.md"
```

Format:

```markdown
# Full Audit — {DATUM}

## Scope
- Modus: SINGLE | BATCHED ({N} Batches)
- PHP-Dateien: X
- Frontend-Dateien: Y
- Runden gesamt: Z

## Ergebnis
- Critical gefunden/gefixt: A/B
- Important gefunden/gefixt: C/D
- Minor gefunden/gefixt: E/F

## Gefixte Issues
- [Security] app/Foo.php:42 — XSS via {!! !!} → durch {{ }} ersetzt
- [Architektur] app/Bar.php — SanitizesInput Trait fehlte → hinzugefügt

## Design-Verification
- Screenshots: .claude/screenshots/{branch}-{hash}/ (oder "übersprungen — keine Frontend-Dateien")
- Gescreenshottete URLs: Liste
- User-Entscheidung: Go / Manuell anpassen

## Offene Punkte
- [Code Quality] app/Baz.php — Architektur-Refactoring nötig (nicht auto-fixbar)

## Sauber
Performance, SEO
```

**Empfehlungen umsetzen (Offene Punkte):**

Wenn `## Offene Punkte` im Audit-Log Einträge enthält — frage den User via AskUserQuestion:

```
Audit-Empfehlungen: {N} offene Punkte gefunden.

{Liste der Offenen Punkte}

Soll ich diese direkt umsetzen?
```

Optionen:
- **Ja, alle** — Alle Offenen Punkte jetzt umsetzen
- **Einzeln entscheiden** — Jeden Punkt einzeln bestätigen
- **Nein, später** — Punkte bleiben im Audit-Log für später

| Antwort | Aktion |
|---------|--------|
| **Ja, alle** | Jeden Offenen Punkt implementieren, dann weiter mit Abschnitt 5 |
| **Einzeln entscheiden** | Pro Punkt AskUserQuestion → bestätigt: implementieren, abgelehnt: überspringen |
| **Nein, später** | Nichts ändern, weiter mit Abschnitt 5 |

Keine Offenen Punkte? Diesen Schritt überspringen, direkt weiter mit Abschnitt 5.

---

## 5. Learning

Nach dem Audit-Log dispatche den Learning-Agent als Subagent:

```
Agent(
  prompt: Lies {AUDIT_AGENTS}/learning-agent.md und führe den Ablauf aus.
    PROJECT_ROOT={PROJECT_ROOT}
    AKTUELLES_LOG={Inhalt des gerade geschriebenen Audit-Logs}
    AUDIT_TYPE=full-audit
  subagent_type: general-purpose
  mode: bypassPermissions
  run_in_background: true
)
```

Der Learning-Agent läuft im Hintergrund und blockiert nicht.

Wenn Guideline-Vorschläge zurückkommen (`GUIDELINE_SUGGESTIONS > 0`), zeige sie dem User per AskUserQuestion (gleiche Logik wie im /audit Skill).

---

## Abschluss

```
Full Audit abgeschlossen.
- Modus: {BATCH_MODUS} ({N} Batches, {RUNDEN_GESAMT} Runden)
- {GESAMT_CRITICAL} Critical, {GESAMT_IMPORTANT} Important, {GESAMT_MINOR} Minor gefunden und gefixt
- Log: .claude/audits/{DATUM}-full-audit.md
- Learning: läuft im Hintergrund → Ergebnisse in .claude/audits/learning-log.md

Offene Punkte: (falls vorhanden)
- ...
```

