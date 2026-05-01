---
name: full-audit
description: "Comprehensive one-time audit of an entire codebase (not just recent changes). Auto-detects framework (Laravel, Next.js, Nuxt, Django), batches large codebases, runs up to 10 parallel subagents per batch (architecture, security, performance, code quality, SEO, a11y, typography, UI, UX, animation), auto-fixes including Minor, runs a cross-reference pass, generates a manual test plan. Use when the user runs /full-audit, starts on a new project, asks for a comprehensive review, or wants the whole codebase checked. NOT for pre-push of recent changes — use /audit instead."
when_to_use: "/full-audit, full codebase audit, audit whole project, starting on a new project, comprehensive review"
argument-hint: "[optional: directory scope]"
model: claude-opus-4-7
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
  "${CLAUDE_PROJECT_DIR:+${CLAUDE_PROJECT_DIR%/full-audit}/audit}" \
  "$(dirname "${CLAUDE_PROJECT_DIR:-/nonexistent}")/audit" \
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

## Phase 1: Scope & Context

Bash-Logik (Framework-Detection, ALLE_DATEIEN, FRONTEND-Liste, Translation-Liste, PROJECT_CONTEXT, SUPPRESSIONS) und ARCHITEKTUR-NOTIZ-Erstellung in `references/scope-context-batching.md`. Resultierende Variablen: `TOTAL_FILES`, `ALLE_DATEIEN`, `VISUELL_RELEVANTE_DATEIEN`, `TRANSLATION_DATEIEN`, `PROJECT_CONTEXT`, `FRAMEWORK`, `SOURCE_DIRS`, `SUPPRESSIONS`, `ARCHITEKTUR-NOTIZ`.

Optionale Pre-Checks (nur bei lokalem Diff): `pre-checks.sh` ausfuehren.

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

Alle Dateien in einer Runde, max 3 Runden bis SAUBER. Springe zu **Prozedur AUDIT_RUNDE**.

### Modus BATCHED

```
for BATCH in 1..N:
    RUNDE = 1
    BATCH_SAUBER = false
    while RUNDE <= 3 AND NOT BATCH_SAUBER:
        AUDIT_RUNDE mit DATEILISTE = Batch-Dateien
        if SAUBER: BATCH_SAUBER = true
        else: RUNDE += 1
    AKTUELLER_BATCH += 1
```

### Prozedur AUDIT_RUNDE

**Schritt A — Ankuendigung**

BATCHED: `Full-Audit — Batch {AKTUELLER_BATCH}/{N} ({BATCH_VERZEICHNIS}) — {X} Dateien — Runde {RUNDE}/3`
SINGLE: `Full-Audit Runde {RUNDE}/3 — {TOTAL_FILES} Dateien`

TodoWrite: `Runde {RUNDE} — Subagents dispatchen` (in_progress), `Runde {RUNDE} — Findings fixen` (pending).

**Schritt A — 10 Subagents parallel dispatchen**

PFLICHT: ALLE zulaessigen Subagents in JEDER Runde. Fixes koennen Issues in beliebigen Dimensionen einfuehren.

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

Prompt-Template: `{AUDIT_AGENTS}/prompt-template.md` → Abschnitt "Fuer /full-audit".

**Ueberspringen-Regeln** (wenn Batch nicht den Datei-Typ enthaelt):
- 5 (SEO), 6 (A11y), 8 (UI Design), 9 (UX), 10 (Animation): keine Frontend-Dateien
- 7 (Typography): weder Frontend- noch Translation-Dateien

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
- Dokumentation: CLAUDE.md aktuell?
- Mobile Apps: `bash "$AUDIT_BIN/detect-mobile.sh"` — bei Treffer Impact-Matrix aus `{AUDIT_REFS}/mobile-impact.md`.

Ausgabe:
```
## Full Audit — Batch {AKTUELLER_BATCH}/{N} Runde {RUNDE}/3 — X Critical, Y Important, Z Minor

### Critical / Important / Minor / Sauber
[gleiche Struktur]
```

**Schritt C — Auto-Fix (ALLE Findings)**

TodoWrite: `Runde {RUNDE} — Findings fixen` (in_progress).

**Grundregel:** Alles wird gefixt — ausser `low confidence`.

Confidence-Gate:
- `high` → direkt fixen
- `medium` → fixen, im Log dokumentieren
- `low` → NICHT fixen, als Offener Punkt

**HARTE REGEL: Orchestrator editiert NIEMALS Code-Dateien selbst.** Jeder Fix, egal wie trivial, geht via paralleler Fix-Subagent (Haiku). Orchestrator-Edits auf Opus kosten ~5x so viel.

**Erlaubte Orchestrator-Edits:** `.claude/audits/*.md` (Log), `CLAUDE.md`-Context-Entwurf, `suppressions.json`, Changelog-Dateien.

- 0 Findings → `SAUBER`
- Sonst: alle high/medium fixen via Fix-Subagent. Findings nach Datei gruppieren, mehrere Findings pro Datei in einem Fix-Agent-Call bundeln.
- Jeden Fix zu `BEREITS_GEFIXT`. `GESAMT_*` inkrementieren.
- Unklarer Fix → kurz nachfragen. Keine "Offener Punkt" ohne explizite User-Zustimmung.
- Ergebnis: `FIXES_APPLIED`.

**Hinweis:** Full-Audit loopt intern (while-Schleife), NICHT ueber `audit-loop.sh` Stop-Hook. Kein `AUDIT_STATUS:` ausgeben.

### Nach jeder Runde

| Ergebnis | RUNDE | Aktion |
|---|---|---|
| `SAUBER` | — | Naechster Batch (oder Phase 2.5) |
| `FIXES_APPLIED` | < 3 | Convergence-Check; sonst RUNDE+1 |
| `FIXES_APPLIED` | = 3 | Naechster Batch (oder Phase 2.5) |
| `NO_CONVERGENCE` | — | Batch abbrechen, offene Findings als Offene Punkte |

---

## Phase 2.5: Cross-Reference-Runde (nur BATCHED)

Nach allen Batches. 2 Subagents parallel:

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

### 3d. Manueller Testplan

Wenn `VISUELL_RELEVANTE_DATEIEN` nicht leer: max. 15 Schritte (mehr als /audit, weil Full-Audit die gesamte Codebase umfasst). Format wie in /audit, siehe `{AUDIT_REFS}/testplan.md`.

---

## Phase 4: Audit-Log + GitHub-Issues

Detail in `references/audit-log-and-issues.md`. Kurz:

- Audit-Log nach `.claude/audits/{datum}-full-audit.md` schreiben (Format-Template in der reference)
- Log via Read-Tool laden und im Chat als Markdown-Codeblock anzeigen (PFLICHT)
- Offene Punkte + Minor als GitHub-Issues anlegen (PFLICHT bei gh + GitHub-Repo, Dedup pro Finding)
- User fragen ob Offene Punkte jetzt umgesetzt werden sollen

---

## Phase 5: Learning

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
- Modus: {BATCH_MODUS} ({N} Batches, {RUNDEN_GESAMT} Runden)
- {GESAMT_CRITICAL} Critical, {GESAMT_IMPORTANT} Important, {GESAMT_MINOR} Minor gefunden und gefixt
- Log: .claude/audits/{DATUM}-full-audit.md
- Learning: .claude/audits/learning-log.md
```
