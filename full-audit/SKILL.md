---
name: full-audit
disable-model-invocation: true
description: "Comprehensive one-time audit of an entire codebase (not just recent changes). Auto-detects framework (Laravel, Next.js, Nuxt, Django), batches large codebases, runs up to 12 parallel subagents per batch (architecture incl. migrations and observability, security, performance, code quality, SEO, a11y, typography, UI, UX, animation, docs sync, copy), auto-fixes including Minor, runs a cross-reference pass, generates a manual test plan. Use when the user runs /full-audit, starts on a new project, asks for a comprehensive review, or wants the whole codebase checked. NOT for pre-push of recent changes — use /audit instead."
when_to_use: "/full-audit, full codebase audit, audit whole project, starting on a new project, comprehensive review"
argument-hint: "[optional: directory scope]"
model: opus
effort: xhigh
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

**SOFORT AUSFÜHREN — nicht erklären, nicht ankündigen. Direkt mit Phase 0 beginnen.**

> **Architektur-Hinweis:** Dieser Skill hat KEINE eigenen Worker-Agents. Er nutzt die Definitionen aus `../audit/agents/*.md` (im Skill ueber `{AUDIT_AGENTS}` referenziert). Wenn du Worker-Konfiguration aendern willst, editiere dort. Das prompt-template.md hat zwei Sektionen ("Fuer /audit" und "Fuer /full-audit") — Workers dispatchen die passende Sektion je nach Skill.

Anti-Patterns (rote Flaggen) siehe `{AUDIT_REFS}/anti-patterns.md` (Pfad aus Phase 0) — Full-Audit fixt zusaetzlich ALLE Minor-Findings.

---

## Phase 0: Pre-Flight — Audit-Pfade + Agent-Verifikation

```bash
# Resolve audit skill root — try multiple known locations.
AUDIT_ROOT=""
for candidate in \
  "$(dirname "${CLAUDE_SKILL_DIR:-/nonexistent}")/audit" \
  "${CLAUDE_PROJECT_DIR:+${CLAUDE_PROJECT_DIR%/full-audit}/audit}" \
  "$HOME/.claude/skills/audit" \
  "$HOME/.claude/skills/claude-skills/audit"; do
  [ -n "$candidate" ] && [ -d "$candidate/agents" ] && { AUDIT_ROOT="$candidate"; break; }
done

if [ -z "$AUDIT_ROOT" ]; then
  echo "ERROR: audit skill not found. Install audit alongside full-audit."
  exit 1
fi

AUDIT_AGENTS="$AUDIT_ROOT/agents"
AUDIT_BIN="$AUDIT_ROOT/bin"
AUDIT_REFS="$AUDIT_ROOT/references"

bash "$AUDIT_BIN/verify-agents.sh" "$AUDIT_AGENTS" || { echo "Full-Audit abgebrochen — fehlende Agent-Dateien."; exit 1; }
```

---

## Phase 0.3: Learning-Backlog-Check

Identisch zu `/audit` Phase 0. Pruefe ob unverarbeitete Lerning-Vorschlaege aus frueheren Audits offen sind:

```bash
LOG="$(git rev-parse --show-toplevel)/.claude/audits/learning-log.md"
[ -f "$LOG" ] && grep -c "^- \[ \] " "$LOG" 2>/dev/null || echo 0
```

Wenn `>= 1`: User via `AskUserQuestion` fragen mit Optionen:
- **Vorschlaege jetzt umsetzen** → Vorschlaege auflisten, User waehlt welche, Orchestrator dispatcht passende Aenderungen an `audit/guidelines/*.md` oder `audit/agents/*.md` (das sind die GLOBALEN Skill-Files, die alle Projekte betreffen). **WICHTIG — ins Quell-Repo editieren:** `~/.claude/skills/*` kann ein Sync-Ziel sein (Symlink oder entpacktes `.skill`-Bundle), dessen Inhalt ueberschrieben wird. Vor dem ersten Edit Quelle aufloesen: `readlink` pruefen bzw. das Skill-Quell-Repo finden (z.B. `~/Local Sites/claude-skills`) und DORT editieren. Edits in der entpackten Kopie gehen beim naechsten Sync verloren. Nach Umsetzung: `[ ]` zu `[x]` aendern in learning-log.md. Dann Full-Audit weiter mit Phase 0.5.
- **Spaeter, Full-Audit jetzt** → Phase 0.5 starten, Vorschlaege bleiben offen.
- **Nie wieder fragen fuer diese Punkte** → `[skip]`-Marker an betroffene Zeilen anhaengen, sie zaehlen nicht mehr.

Wenn `0`: weiter ohne Frage.

**Zusaetzlich — Offene Audit-Issues & PRs** (identisch zu `/audit` Phase 0.2):

```bash
if gh repo view >/dev/null 2>&1 && git remote get-url origin 2>/dev/null | grep -q github.com; then
  OPEN_AUDIT_ISSUES=$(gh issue list --state open --label audit-finding --json number,title --jq '.[] | "#\(.number) \(.title)"' 2>/dev/null || true)
  OPEN_PRS=$(gh pr list --state open --json number,title,headRefName --jq '.[] | "#\(.number) \(.title) [\(.headRefName)]"' 2>/dev/null || true)
fi
```

Offene `audit-finding`-Issues → AskUserQuestion: **Jetzt mitfixen** (als verifizierte Findings in Batch 1 einspeisen, nach Fix `gh issue close` mit Kommentar) / **Offen lassen**. `OPEN_PRS` als Kontext: Phase-4-Dedup prueft dagegen, PR-Datei-Ueberschneidungen kommen als Hinweis ins Log.

**Skip dieser Phase wenn:** ENV `AUDIT_SKIP_LEARNING_CHECK=1` ODER `FULL_AUDIT_SKIP_LEARNING_CHECK=1` gesetzt (fuer CI/Batch-Runs).

---

## Phase 0.4: Test-Runner-Streak-Check

Hard-Check: Fehlt ein konfigurierter Test-Runner ueber mehrere Full-Audits hinweg, wird die Luecke zur Critical-Finding eskaliert (statt nur Gap-Note). Ohne Runner kann kein Fix-Agent Regressionen verifizieren.

```bash
ROOT=$(git rev-parse --show-toplevel)
STREAK_FILE="$ROOT/.claude/audits/no-test-runner-streak"
HAS_RUNNER=0
# JS/TS-Runner in package.json oder Config-Dateien
if [ -f "$ROOT/package.json" ] && grep -Eq '"(vitest|jest|mocha)"|node:test|node --test' "$ROOT/package.json" 2>/dev/null; then HAS_RUNNER=1; fi
# find statt Glob — zsh bricht bei nicht-matchenden Globs ab
[ -n "$(find "$ROOT" -maxdepth 1 \( -name 'vitest.config.*' -o -name 'jest.config.*' \) 2>/dev/null)" ] && HAS_RUNNER=1
# PHP / Python
{ [ -f "$ROOT/phpunit.xml" ] || [ -f "$ROOT/phpunit.xml.dist" ]; } && HAS_RUNNER=1
[ -f "$ROOT/pytest.ini" ] && HAS_RUNNER=1
grep -q "\[tool.pytest" "$ROOT/pyproject.toml" 2>/dev/null && HAS_RUNNER=1

if [ "$HAS_RUNNER" -eq 1 ]; then
  rm -f "$STREAK_FILE"; TEST_RUNNER_ESCALATE=0
  echo "Test-Runner: vorhanden (Streak zurueckgesetzt)"
else
  STREAK=$(( $(cat "$STREAK_FILE" 2>/dev/null || echo 0) + 1 ))
  echo "$STREAK" > "$STREAK_FILE"
  if [ "$STREAK" -ge 3 ]; then TEST_RUNNER_ESCALATE=1; else TEST_RUNNER_ESCALATE=0; fi
  echo "Test-Runner: FEHLT (Streak=$STREAK, Escalate=$TEST_RUNNER_ESCALATE)"
fi
```

`TEST_RUNNER_ESCALATE=1` → in Phase 3c die fehlende Test-Infrastruktur als **Critical** ins Audit-Log und als GitHub-Issue (Phase 4) aufnehmen, nicht als Gap-Note. `=0` → wie bisher Gap-Note.

**Skip wenn:** ENV `FULL_AUDIT_SKIP_TESTRUNNER_CHECK=1`.

---

## Phase 0.5: Dimension Selection

Bevor Scope gesammelt wird, klaeren welche Dimensionen geprueft werden sollen. Spart Tokens und Zeit wenn der User z.B. nur Security pruefen will.

**Skip via ENV (fuer CI/Batch):**

```bash
if [ -n "${FULL_AUDIT_DIMENSIONS:-}" ]; then
  case "$FULL_AUDIT_DIMENSIONS" in
    all|"") SELECTED_DIMENSIONS="architecture,security,performance,code_quality,seo,a11y,typography,ui_design,ux,animation,docs_sync,copy" ;;
    *)      SELECTED_DIMENSIONS="$FULL_AUDIT_DIMENSIONS" ;;
  esac
  echo "Dimensions via ENV: $SELECTED_DIMENSIONS"
fi
```

**Sonst via AskUserQuestion (1 oder 2 Fragen):**

Frage 1 — Preset:

| Option | Dimensionen |
|---|---|
| Alles (Standard) | architecture, security, performance, code_quality, seo, a11y, typography, ui_design, ux, animation, docs_sync, copy |
| Nur Backend | architecture, security, performance, code_quality, docs_sync |
| Nur Frontend | seo, a11y, typography, ui_design, ux, animation, copy |
| Custom | (loest Frage 2 aus) |

Frage 2 (nur bei Custom) — Multi-Select aller 12 Dimensionen. User waehlt beliebige Kombination.

**Validierung:** `SELECTED_DIMENSIONS` muss min. 1 gueltige Dimension enthalten. Ungueltige Werte verwerfen.

**Anzeige:** `Full-Audit Scope: {N}/12 Dimensionen — {Liste}`.

---

## Phase 0.7: Effort Configuration

Skaliert Tiefe nach `${CLAUDE_EFFORT}`. Default `xhigh` (Full-Audit ist per Definition gruendlich, kein `medium`).

```bash
CLAUDE_EFFORT="${CLAUDE_EFFORT:-xhigh}"
case "$CLAUDE_EFFORT" in
  low)
    MAX_RUNDEN_PRO_BATCH=1; FIX_MINOR=0; SKIP_LEARNING=1
    SKIP_CROSS_REF=1; CONFIDENCE_FLOOR=high
    ;;
  medium)
    MAX_RUNDEN_PRO_BATCH=2; FIX_MINOR=1; SKIP_LEARNING=0
    SKIP_CROSS_REF=0; CONFIDENCE_FLOOR=medium
    ;;
  high|xhigh|*)
    MAX_RUNDEN_PRO_BATCH=3; FIX_MINOR=1; SKIP_LEARNING=0
    SKIP_CROSS_REF=0; CONFIDENCE_FLOOR=low
    FORCE_CROSS_REF_SINGLE=1   # auch im SINGLE-Modus Cross-Ref durchfuehren
    ;;
esac
echo "Effort=$CLAUDE_EFFORT | Runden=$MAX_RUNDEN_PRO_BATCH | FixMinor=$FIX_MINOR | Cross-Ref=$([ $SKIP_CROSS_REF -eq 1 ] && echo skip || echo run)"
```

| Level | Runden/Batch | Fix Minor | Cross-Ref | Learning | Confidence-Floor |
|---|---|---|---|---|---|
| low | 1 | nein | skip | skip | high |
| medium | 2 | ja | nur BATCHED | ja | medium |
| high / xhigh (Default) | 3 | ja | immer (auch SINGLE) | ja | low |

Im Folgenden bedeutet `{MAX_RUNDEN_PRO_BATCH}` der hier gesetzte Wert.

---

## Phase 1: Scope & Context

Bash-Logik (Framework-Detection, ALLE_DATEIEN, FRONTEND-Liste, Translation-Liste, PROJECT_CONTEXT, SUPPRESSIONS) und ARCHITEKTUR-NOTIZ-Erstellung in `references/scope-context-batching.md`. Resultierende Variablen: `TOTAL_FILES`, `ALLE_DATEIEN`, `VISUELL_RELEVANTE_DATEIEN`, `TRANSLATION_DATEIEN`, `PROJECT_CONTEXT`, `FRAMEWORK`, `SOURCE_DIRS`, `SUPPRESSIONS`, `ARCHITEKTUR-NOTIZ`.

Optionale Pre-Checks (nur bei lokalem Diff): `pre-checks.sh` ausfuehren.

**i18n-Vollstaendigkeit (deterministisch):** `bash "$AUDIT_BIN/check-i18n-keys.sh"` — bei `I18N_RESULT=MISSING` wird jede Zeile ein Important-Finding `[i18n]` (Full-Audit prueft die ganze Codebase, daher alle Gaps melden).

**Dependency-Health (deterministisch):** `bash "$AUDIT_BIN/check-outdated.sh"` (voller Modus) —
- `DEP_SECURITY_RESULT=VULNS` → jede verwundbare Dependency ein **Critical**-Finding `[Security]`
- `DEP_OUTDATED_RESULT=OUTDATED` → als **Minor**-Findings `[Dependencies]` sammeln (gruppiert, nicht pro Paket ein Issue); Major-Spruenge mit Breaking-Change-Risiko (z.B. `stripe-php 17 → 20`) als Offener Punkt statt Auto-Update — Dependency-Updates macht NIE der Fix-Agent automatisch

**Project-Specific Guidelines:**

```bash
PROJECT_GUIDELINES_FILE="$(git rev-parse --show-toplevel)/.claude/audit-guidelines.md"
PROJECT_GUIDELINES=""
if [ -f "$PROJECT_GUIDELINES_FILE" ]; then
  PROJECT_GUIDELINES=$(cat "$PROJECT_GUIDELINES_FILE")
  echo "Project guidelines: $PROJECT_GUIDELINES_FILE ($(wc -l < "$PROJECT_GUIDELINES_FILE") lines)"
fi
```

`PROJECT_GUIDELINES` an alle Workers durchreichen (siehe prompt-template).

**Concurrent-Tree-Check (Baseline):** Ein Full-Audit laeuft minutenlang ueber viele Batches. Aendert der User (oder ein anderer Prozess) waehrenddessen den Working-Tree, auditieren spaetere Batches einen veralteten Stand. Baseline-Hash festhalten:

```bash
AUDIT_TREE_HASH=$(git diff HEAD | { md5 2>/dev/null || md5sum | cut -d' ' -f1; })
```

Nach JEDEM Batch (in "Nach jeder Runde", bevor der naechste Batch startet) erneut hashen und vergleichen: weicht der Wert ab → **Warnung ins Audit-Log** (`## Hinweise: Tree waehrend Audit veraendert`), den naechsten Batch auf den aktuellen Stand (`collect-scope.sh` erneut) resetten und `AUDIT_TREE_HASH` aktualisieren. Findings auf inzwischen ueberschriebenen Zeilen verwerfen (Halluzinations-Risiko).

---

## Phase 1.5: Batching-Entscheidung

| TOTAL_FILES | Modus |
|---|---|
| ≤ 80 | `SINGLE` |
| > 80 | `BATCHED` |

Batch-Regeln und Bash-Logik in `references/scope-context-batching.md`. Max ~30-40 Dateien pro Batch, zusammengehoeriges zusammen.

---

## Phase 2: Audit-Loop

Initialisiere:
```
RUNDE = 1
BEREITS_GEFIXT = []
GESAMT_CRITICAL = 0; GESAMT_IMPORTANT = 0; GESAMT_MINOR = 0
AKTUELLER_BATCH = 1
FINDINGS_VORHERIGE_RUNDE = null   # pro Batch zuruecksetzen
```

**Convergence-Check:** Pro Batch nach jeder Runde. Wenn Critical+Important NICHT sinken UND RUNDE >= 2 → `NO_CONVERGENCE`, verbleibende Findings als Offene Punkte.

### Modus SINGLE (TOTAL_FILES <= 80)

Alle Dateien in einer Runde, max {MAX_RUNDEN_PRO_BATCH} Runden bis SAUBER. Springe zu **Prozedur AUDIT_RUNDE**.

### Modus BATCHED

```
for BATCH in 1..N:
    RUNDE = 1
    BATCH_SAUBER = false
    while RUNDE <= {MAX_RUNDEN_PRO_BATCH} AND NOT BATCH_SAUBER:
        AUDIT_RUNDE mit DATEILISTE = Batch-Dateien
        if SAUBER: BATCH_SAUBER = true
        else: RUNDE += 1
    AKTUELLER_BATCH += 1
```

### Prozedur AUDIT_RUNDE

**Schritt A — Ankuendigung**

BATCHED: `Full-Audit — Batch {AKTUELLER_BATCH}/{N} ({BATCH_VERZEICHNIS}) — {X} Dateien — Runde {RUNDE}/{MAX_RUNDEN_PRO_BATCH}`
SINGLE: `Full-Audit Runde {RUNDE}/{MAX_RUNDEN_PRO_BATCH} — {TOTAL_FILES} Dateien`

TodoWrite: `Runde {RUNDE} — Subagents dispatchen` (in_progress), `Runde {RUNDE} — Findings fixen` (pending).

**Schritt A — Subagents parallel dispatchen**

PFLICHT: ALLE in `SELECTED_DIMENSIONS` (aus Phase 0.5) enthaltenen Subagents in JEDER Runde dispatchen. Nicht-selektierte Dimensionen werden komplett uebersprungen — auch nicht in spaeteren Runden nachholen. Fixes koennen Issues in den ausgewaehlten Dimensionen einfuehren.

Dispatche alle in einem Message-Block. Uebergib ARCHITEKTUR-NOTIZ + PROJECT_CONTEXT + FRAMEWORK + SOURCE_DIRS + SUPPRESSIONS + TRANSLATION_DATEIEN + **nur die Batch-Dateien**.

Agent-Definitionen: `{AUDIT_AGENTS}/*.md`.

| # | Agent | Kurzname |
|---|---|---|
| 1 | `1-architecture.md` | Architektur & Code Reuse |
| 2 | `2-security.md` | Security |
| 3 | `3-performance.md` | Performance |
| 4 | `4-code-quality.md` | Code Quality |
| 5 | `5-seo.md` | SEO |
| 6 | `6-a11y.md` | Accessibility (WCAG) |
| 7 | `7-typography.md` | Typography |
| 8 | `8-ui-design.md` | UI Visual Design |
| 9 | `9-ux.md` | UX Patterns |
| 10 | `10-animation.md` | Animation |
| 11 | `11-docs-sync.md` | Docs Sync & Style |
| 12 | `12-copy.md` | Copy & UX-Writing |

Prompt-Template: `{AUDIT_AGENTS}/prompt-template.md` → Abschnitt "Fuer /full-audit".

**Ueberspringen-Regeln:**
- Dimension NICHT in `SELECTED_DIMENSIONS` → Agent gar nicht dispatchen
- **5 (SEO): projektweit ueberspringen, wenn das Projekt gar kein Web-Frontend hat.** Einmal pro Full-Audit pruefen: `find . -path ./node_modules -prune -o \( -name '*.html' -o -name '*.tsx' -o -name '*.jsx' -o -name '*.vue' -o -name '*.svelte' -o -name '*.astro' -o -name '*.blade.php' \) -print -quit` gibt nichts zurueck → reines natives/CLI/JSON-API-Projekt (z.B. nur Swift + bun-Backend), SEO hat keine Angriffsflaeche → Agent 5 nie dispatchen (kein Token verbrennen). Bei Treffer normal nach Batch-Inhalt entscheiden.
- 5 (SEO), 6 (A11y), 8 (UI Design), 9 (UX), 10 (Animation): keine Frontend-Dateien im Batch
- 7 (Typography), 12 (Copy): weder Frontend- noch Translation-Dateien im Batch
- 11 (Docs Sync): laeuft genau einmal pro Full-Audit (im ersten Batch oder als eigener finaler Pass nach Phase 2.5) — nicht pro Batch.

Agents 5-10 laufen bei ALLEN Frontend-Dateien — auch app-interne Views.

**Schritt B — Konsolidieren**

Deduplizierung: Gleiche Stelle von mehreren Subagents → ein Finding, strengste Einstufung.

**Schritt B.5 — Hallucination Validator (PFLICHT)**

Vor jedem Fix:
1. `test -f "{datei}"` — nein → verwerfen
2. `wc -l "{datei}"` — Zeile > Dateilaenge → verwerfen
3. Externe APIs/Libraries: via context7 oder Grep in `vendor/`/`node_modules/` verifizieren. Nicht verifizierbar → `low confidence`.

Verworfene als `HALLUCINATED: ...` loggen, nicht fixen.

Pruefe SELBST (nur Runde 1, Batch 1):
- Tests: wichtige Services/Commands ohne Tests?
- Mobile Apps: `bash "$AUDIT_BIN/detect-mobile.sh"` — bei Treffer Impact-Matrix aus `{AUDIT_REFS}/mobile-impact.md`.

(Hinweis: Dokumentation laeuft als Agent 11 — eigener Pass, kein Orchestrator-Check.)

Ausgabe:
```
## Full Audit — Batch {AKTUELLER_BATCH}/{N} Runde {RUNDE}/3 — X Critical, Y Important, Z Minor

### Critical / Important / Minor / Sauber
[gleiche Struktur]
```

**Schritt C — Auto-Fix (ALLE Findings)**

TodoWrite: `Runde {RUNDE} — Findings fixen` (in_progress).

**Grundregel:** Alles wird gefixt — ausser `low confidence`.

Confidence-Gate (skaliert mit `CONFIDENCE_FLOOR` aus Phase 0.7):
- `floor=high` (low effort): nur `high` fixen, Rest bleibt im Log
- `floor=medium` (medium effort): `high`+`medium` fixen. `low` → Nachverifikation: Stelle gezielt lesen; bestaetigt → fixen, sonst verwerfen (kein Offener Punkt, kein Issue)
- `floor=low` (high/xhigh effort, Default): alle fixen, `low` mit Warn-Marker

Minor-Findings fixen wenn `FIX_MINOR=1` (medium/high/xhigh). Nicht gefixte Minor bleiben NUR im Log.

**Offene Punkte sind NUR echte Entscheidungs-Punkte** (Architektur-Tradeoffs, Verhaltens-Aenderungen) — alles andere wird gefixt oder verworfen.

**HARTE REGEL: Orchestrator editiert NIEMALS Code-Dateien selbst.** Jeder Fix, egal wie trivial, geht via paralleler Fix-Subagent (Sonnet). Orchestrator-Edits auf Opus kosten ein Mehrfaches.

**Erlaubte Orchestrator-Edits:** `.claude/audits/*.md` (Log), `CLAUDE.md`-Context-Entwurf, `suppressions.json`, Changelog-Dateien.

- 0 Findings → `SAUBER`
- Sonst: alle high/medium fixen via Fix-Subagent. Findings nach Datei gruppieren, mehrere Findings pro Datei in einem Fix-Agent-Call bundeln.
- **Zentralisierungs-Findings (neue Shared-Utility / Helper / Trait):** Wenn ein Finding ein dupliziertes Pattern in eine neue `lib/*.js` (o.ae.) extrahiert, ZUERST alle Vorkommen greppen (`grep -rn "{altes_pattern}" src/`, Glob an Projektsprache anpassen) und ALLE Treffer-Dateien an EINEN einzigen Fix-Agent uebergeben (kein paralleler Split, sonst Datei-Kollision). Als Zentralisierungs-Fix markieren, damit der Fix-Agent die erweiterte Datei-Grenze (siehe `fix-agent.md` Sonderfall) anwendet und jede Fundstelle migriert.
- Jeden Fix zu `BEREITS_GEFIXT`. `GESAMT_*` inkrementieren.
- Unklarer Fix → kurz nachfragen. Keine "Offener Punkt" ohne explizite User-Zustimmung.
- Ergebnis: `FIXES_APPLIED`.

**Hinweis:** Full-Audit loopt intern (while-Schleife), NICHT ueber `audit-loop.sh` Stop-Hook. Kein `AUDIT_STATUS:` ausgeben.

### Nach jeder Runde

| Ergebnis | RUNDE | Aktion |
|---|---|---|
| `SAUBER` | — | Naechster Batch (oder Phase 2.5) |
| `FIXES_APPLIED` | < {MAX_RUNDEN_PRO_BATCH} | Convergence-Check; sonst RUNDE+1 |
| `FIXES_APPLIED` | = {MAX_RUNDEN_PRO_BATCH} | Naechster Batch (oder Phase 2.5) |
| `NO_CONVERGENCE` | — | Batch abbrechen, offene Findings als Offene Punkte |

---

## Phase 2.5: Cross-Reference-Runde

**Skip-Bedingungen** (in dieser Reihenfolge pruefen):
- `SKIP_CROSS_REF=1` aus Phase 0.7 (low effort) → komplett skippen
- Weder `architecture` noch `code_quality` in `SELECTED_DIMENSIONS` → skippen
- SINGLE-Modus UND `FORCE_CROSS_REF_SINGLE` nicht gesetzt (medium effort) → skippen

Sonst nach allen Batches: 2 Subagents parallel:

| # | Fokus | Scope |
|---|---|---|
| 1 | Cross-Module-Abhaengigkeiten | Services ↔ UI falsch aufgerufen, Models ↔ Traits/Mixins falsch genutzt, Controller-View-Mismatches |
| 2 | Konsistenz | Gleiche Patterns einheitlich? (Auth-Checks, Cache-Keys, Error-Handling) |

Input: ARCHITEKTUR-NOTIZ + BEREITS_GEFIXT + Zusammenfassung aller Batch-Findings.
Fixes wie Schritt C. Keine weiteren Runden.

---

## Phase 3: Changelog, Linter, Tests, Testplan

### 3a. Changelog

Suche `CHANGELOG.md`, `changelog.md`, `release-notes/next.md`, `resources/changelog.md`, `CHANGES.md`. User-facing Fixes (UI, API, Routing, Translations) → Eintrag draften.

### 3b. Linter & Static Analysis

Siehe `{AUDIT_REFS}/linters-and-tests.md`. Im Full-Audit-Modus laufen alle Linter/Formatter global (nicht datei-scoped). Bei Fehlern: manuell fixen, erneut.

### 3c. Tests

Siehe `{AUDIT_REFS}/linters-and-tests.md` (Test-Runner-Tabelle). Alle erkannten Runner ausfuehren. Failures fixen. Unfixbare als Offener Punkt.

**Kein Test-Runner konfiguriert:** Bei `TEST_RUNNER_ESCALATE=1` (Phase 0.4, Streak >= 3) die fehlende Test-Infrastruktur als **Critical** ins Audit-Log und als GitHub-Issue (Phase 4) aufnehmen. Sonst nur Gap-Note (`Tests: uebersprungen — kein Runner konfiguriert`).

### 3d. Manueller Testplan

Wenn `VISUELL_RELEVANTE_DATEIEN` nicht leer: max. 15 Schritte (mehr als /audit, weil Full-Audit die gesamte Codebase umfasst). Format wie in /audit, siehe `{AUDIT_REFS}/testplan.md`.

---

## Phase 4: Audit-Log + GitHub-Issues

Detail in `references/audit-log-and-issues.md`. Kurz:

- Audit-Log nach `.claude/audits/{datum}-full-audit.md` schreiben (Format-Template in der reference). Im Header `SELECTED_DIMENSIONS` festhalten, damit spaetere Audits wissen welche Dimensionen nicht geprueft wurden.
- **Open-Point-Aging:** Vor dem Vorlegen die offenen Punkte gegen die vorherigen `.claude/audits/*-full-audit.md` (chronologisch) abgleichen. Ein Punkt, der inhaltlich (gleiche Datei + gleiche Kernaussage) bereits in `>= 2` frueheren Audit-Logs als offen stand, bekommt im aktuellen Log einen **`AGED`**-Marker und erscheint als priorisierter Block ganz oben im Offene-Punkte-Abschnitt ("3x+ offen — Entscheidung ueberfaellig"). So versanden Tradeoff-Entscheidungen nicht audit-um-audit.
- Log via Read-Tool laden und im Chat als Markdown-Codeblock anzeigen (PFLICHT)
- Offene Punkte dem User vorlegen (AskUserQuestion): **Jetzt entscheiden + fixen / Als Issue vertagen / Verwerfen**. `AGED`-Punkte zuerst vorlegen. Issues NUR fuer Vertagtes (Dedup pro Finding). Minor bekommt NIE Issues — bleibt im Log.

---

## Phase 5: Learning

**Skip wenn `SKIP_LEARNING=1`** (low effort). Direkt zu Abschluss.

```
Agent(
  prompt: "Lies {AUDIT_AGENTS}/learning-agent.md und fuehre den Ablauf aus.
    PROJECT_ROOT={PROJECT_ROOT}
    AKTUELLES_LOG={Inhalt des Audit-Logs}
    AUDIT_TYPE=full-audit",
  subagent_type: general-purpose,
  mode: bypassPermissions
)
```

**Foreground-Mode wichtig:** Background-Subagents koennen `.claude/audits/learning-log.md` nicht schreiben (hardcoded `.claude/`-Schutz, der auch bei `bypassPermissions` greift, und Background-Subagents koennen den User nicht prompten). Foreground umgeht das mit ~5-10s Mehrkosten am Ende.

---

## Abschluss

**Push-Marker schreiben (PFLICHT):**

```bash
# Marker schreiben — KEIN git push im selben Bash-Aufruf!
hash=$(echo -n "$PWD" | md5 2>/dev/null || echo -n "$PWD" | md5sum 2>/dev/null | cut -d' ' -f1)
touch "/tmp/claude-audit-passed-$hash"
```

Marker: TTL 30 Min, wird nicht geloescht (mehrere Hooks pruefen sequenziell).

```
Full Audit abgeschlossen.
- Scope: {N}/12 Dimensionen — {SELECTED_DIMENSIONS}
- Modus: {BATCH_MODUS} ({N} Batches, {RUNDEN_GESAMT} Runden)
- {GESAMT_CRITICAL} Critical, {GESAMT_IMPORTANT} Important, {GESAMT_MINOR} Minor gefunden und gefixt
- Log: .claude/audits/{DATUM}-full-audit.md
- Learning: .claude/audits/learning-log.md
```
