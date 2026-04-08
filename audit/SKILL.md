---
name: audit
description: "Pre-push code audit. Dispatches up to 10 parallel subagents (architecture, security, performance, code quality, SEO, a11y, typography, UI design, UX, animation) against uncommitted and unpushed changes, runs secret/lockfile pre-checks, auto-fixes findings with a halluzination-validator, loops until clean, then verifies visual changes with Playwright screenshots before allowing git push. Triggers: /audit, before pushing, git push, pre-push review, review my changes, audit uncommitted changes, check before pushing."
argument-hint: "[optional: scope hint]"
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
hooks:
  PreToolUse:
    - matcher: "Bash"
      hook: bash "${CLAUDE_PROJECT_DIR:-$HOME/.claude/skills/audit}/hooks/block-unsafe-push.sh"
---

# Audit: Review aller offenen Änderungen

**SOFORT AUSFÜHREN — nicht erklären, nicht ankündigen. Direkt mit Schritt 1 beginnen.**

Wenn du unsicher bist welche Regeln gelten, lies `references/anti-patterns.md` — dort stehen die häufigsten Fehler im Loop.

## 1. Pre-Flight & Scope ermitteln

```bash
AUDIT_BIN="${CLAUDE_PROJECT_DIR:-$HOME/.claude/skills/audit}/bin"
AUDIT_AGENTS_DIR="${CLAUDE_PROJECT_DIR:-$HOME/.claude/skills/audit}/agents"

# 0. Fail-fast: alle Subagent-Definitionen vorhanden?
bash "$AUDIT_BIN/verify-agents.sh" "$AUDIT_AGENTS_DIR" || {
  echo "Audit abgebrochen — fehlende Agent-Dateien (siehe oben)."
  exit 1
}

# 1. Scope + Framework
bash "$AUDIT_BIN/collect-scope.sh"
bash "$AUDIT_BIN/detect-framework.sh"

# 2. Deterministische Pre-Checks (Secrets, Lockfile-Drift, Build-Artefakte)
bash "$AUDIT_BIN/pre-checks.sh"
```

`collect-scope.sh` liefert `DEFAULT_BRANCH`, `BASE_REF`, klassifizierte Dateilisten (`---FILES---`, `---FRONTEND---`, `---TRANSLATIONS---`) und den deduplizierten Unified-Diff (`---DIFF---`). `detect-framework.sh` liefert `FRAMEWORK` und `SOURCE_DIRS`. `pre-checks.sh` liefert drei Sektionen: `SECRET_SCAN_RESULT`, `LOCKFILE_DRIFT_RESULT`, `BINARY_ARTIFACTS_RESULT`.

**Pre-Check-Auswertung — sofort, vor jedem Subagent-Dispatch:**

| Pre-Check | Ergebnis | Aktion |
|---|---|---|
| `SECRET_SCAN_RESULT=FINDINGS` | — | Als **Critical** ins Audit-Log. User sofort warnen. Push wird blockiert bis Secrets entfernt + History bereinigt sind. |
| `LOCKFILE_DRIFT_RESULT=DRIFT` | — | Als **Important** ins Audit-Log. Manifest-Konsistenz prüfen, ggf. Lockfile regenerieren. |
| `BINARY_ARTIFACTS_RESULT=FINDINGS` | — | Als **Important**. Vorschlag: aus Index entfernen, `.gitignore` ergänzen. |

Wenn der Diff leer ist und alle Pre-Checks `CLEAN`: melden und beenden. Kein Git-Repo? Fehler melden.

Erstelle aus den Script-Outputs:

- **ALLE_DATEIEN:** Sektion `---FILES---` aus `collect-scope.sh`
- **FRONTEND_DATEIEN:** Sektion `---FRONTEND---`
- **TRANSLATION_DATEIEN:** Sektion `---TRANSLATIONS---`
- **VISUELL_RELEVANTE_DATEIEN:** `FRONTEND_DATEIEN` + Framework-spezifische Backend-Dateien (z. B. `app/Livewire/`, Controller mit `return view(...)`/`return Inertia::render(...)`). NICHT: reine Services, Models, Migrations, Commands, Jobs, Middleware — außer sie ändern was an den View übergeben wird.
- **UNIFIED_DIFF:** Sektion `---DIFF---`
- **SUPPRESSIONS:** `$(git rev-parse --show-toplevel)/.claude/audits/suppressions.json` laden falls vorhanden, `pattern`-Felder extrahieren. Sonst `"Keine Suppressions"`.
- **PROJECT_CONTEXT:** `## Audit Context` aus `CLAUDE.md` (falls vorhanden), via `awk '/^## Audit Context$/{f=1;next} /^## /{f=0} f'`. Sonst `"Kein projektspezifischer Kontext."`

Übergib `PROJECT_CONTEXT`, `FRAMEWORK`, `SOURCE_DIRS` und `UNIFIED_DIFF` an alle Subagents.

---

## 2. Audit-Loop

Führe die Prozedur `AUDIT_RUNDE` aus. Danach entscheide: nächste Runde oder Loop beenden. Maximal **5 Runden** — der Convergence-Check bricht typischerweise früher ab.

Initialisiere vor der ersten Runde:

```
RUNDE = 1
BEREITS_GEFIXT = []
FINDINGS_VORHERIGE_RUNDE = null
```

**Convergence-Check:** Nach jeder Runde wird `Critical + Important` der aktuellen Runde mit der vorherigen verglichen. Wenn die Anzahl NICHT sinkt UND `RUNDE >= 2`, Loop abbrechen mit `NO_CONVERGENCE`. Grund: Fixer baut neue Issues ein — weiteres Looping verbrennt nur Tokens.

### Prozedur AUDIT_RUNDE

Am Ende steht IMMER eine Entscheidung: nächste Runde oder Loop beenden.

**Schritt A — Ankündigung und Todos**

Ausgabe: `Audit-Runde {RUNDE}/5`

TodoWrite: Zwei Todos erstellen:
- `Audit Runde {RUNDE} — Subagents dispatchen` (in_progress)
- `Audit Runde {RUNDE} — Findings fixen` (pending)

**Schritt B — Scope aktualisieren (ab Runde 2)**

`collect-scope.sh` erneut aufrufen — Fixes haben den Diff verändert. `ALLE_DATEIEN` und `FRONTEND_DATEIEN` bleiben identisch, aber der komplette aktualisierte Diff wird allen Subagents erneut übergeben.

**Schritt C.0 — Triage-Agent (PFLICHT, vor allem anderen)**

Bevor die Spezial-Subagents laufen, dispatche EINEN Triage-Agent (Haiku, schnell, billig). Er liest den Diff einmal und erstellt ein JSON mit: welcher Dimension-Agent muss laufen, welche Hotspots pro Agent, was ist irrelevant.

```
Agent(
  subagent_type: general-purpose,
  model: haiku,
  prompt: "Lies agents/0-triage.md und fuehre die Triage fuer diesen Diff durch.

    UNIFIED_DIFF:
    {UNIFIED_DIFF}

    FRONTEND_DATEIEN: {FRONTEND_DATEIEN}
    TRANSLATION_DATEIEN: {TRANSLATION_DATEIEN}
    FRAMEWORK: {FRAMEWORK}
    PROJECT_CONTEXT: {PROJECT_CONTEXT}
    SUPPRESSIONS: {SUPPRESSIONS}

    Gib NUR das JSON zurueck, nichts anderes."
)
```

Parse das JSON. Ergebnis: `TRIAGE_RESULT` mit `relevance` pro Dimension.

**Schritt C — Spezial-Subagents parallel dispatchen**

**Regel:** Nur Agents mit `relevance.{dimension}.run == true` aus dem Triage-Ergebnis dispatchen. Security sollte fast immer laufen — Triage ist angewiesen nur bei reinen Doc/Translation-Changes zu skippen.

**PFLICHT: Alle nicht-geskippten Agents in JEDER Runde dispatchen.** Ein Security-Fix kann ein Performance-Problem einfuehren — aber nur wenn Performance vom Triage als relevant markiert wurde.

Dispatche in **einem einzigen Message-Block** via Agent-Tool. Uebergib:
- `TRIAGE_SUMMARY` (die 1-2 Zeilen aus dem Triage-JSON)
- `HOTSPOTS` (die fuer diesen Agent markierten Stellen)
- `UNIFIED_DIFF` (als Fallback, wenn der Agent breiteren Kontext braucht)

Dadurch parst jeder Agent nicht mehr den ganzen Diff von 0 — er fokussiert direkt auf seine Hotspots.

Agent-Definitionen liegen in `agents/*.md`. Jede Datei enthält `subagent_type`, `model` und Fokus.

| # | Agent-Datei | Kurzname |
|---|-------------|----------|
| 1 | `agents/1-architecture.md` | Architektur & Code Reuse |
| 2 | `agents/2-security.md` | Security |
| 3 | `agents/3-performance.md` | Performance & Efficiency |
| 4 | `agents/4-code-quality.md` | Code Quality & Simplification |
| 5 | `agents/5-seo.md` | SEO & Semantic HTML |
| 6 | `agents/6-a11y.md` | Accessibility (WCAG) |
| 7 | `agents/7-typography.md` | Typography |
| 8 | `agents/8-ui-design.md` | UI Visual Design |
| 9 | `agents/9-ux.md` | UX Patterns & Interaction |
| 10 | `agents/5-animation.md` | Animation & Motion Design |

Prompt-Template: `agents/prompt-template.md`, Abschnitt „Für /audit (Diff-basiert)".

**Überspringen-Regeln** — jeder Agent hat seine eigene, nicht gruppieren:

| Agent | Überspringen wenn |
|-------|-------------------|
| 5 (SEO) | Keine FRONTEND_DATEIEN im Diff |
| 6 (A11y) | Keine FRONTEND_DATEIEN im Diff |
| 7 (Typography) | Weder FRONTEND_DATEIEN noch TRANSLATION_DATEIEN im Diff |
| 8 (UI Design) | Keine FRONTEND_DATEIEN im Diff |
| 9 (UX) | Keine FRONTEND_DATEIEN im Diff |
| 10 (Animation) | Keine FRONTEND_DATEIEN im Diff |

**Scope-Regel (Diff-First):** Alle Subagents 1-10 fokussieren primär auf den **Diff** (committed-unpushed + working-tree). Interne Views, Admin-Panels, Dashboards sind nicht ausgenommen — aber nur wenn sie im Diff sind.

**Kontext-Erweiterung (on-demand):** Subagents 5-10 dürfen zusätzlich bis zu **5 Referenz-Dateien** aus `FRONTEND_DATEIEN` lesen, wenn der Diff allein keine Konsistenz-Bewertung erlaubt (z.B. neuer Button → bestehende Button-Komponente zum Vergleich). Das Lesen passiert on-demand via Read-Tool, nicht als Vorab-Scan. Obergrenze strikt: max 5 Files pro Agent pro Runde.

**Full-Scan?** Dafür gibt es `/full-audit`. `/audit` ist pre-push, schnell, diff-fokussiert.

**Schritt D — Konsolidieren und Deduplizieren**

Gleiche Stelle von mehreren Subagents → ein Finding, strengste Einstufung gewinnt.

Prüfe SELBST (nur in Runde 1):
- **Documentation:** Erfordern die Änderungen ein Update der README.md oder CLAUDE.md?
- **Öffentliche Seiten:** Landing Pages, Changelog, Hilfeseiten aktualisieren?
- **Tests:** Geänderte Logik ohne zugehörige Tests?
- **Mobile Apps:** `bash bin/detect-mobile.sh` ausführen. Wenn eine App erkannt wird, Impact anhand `references/mobile-impact.md` bewerten. Breaking Changes = Important, neue Felder = Minor.

Eigene Findings als Important einfügen.

**Ausgabe:**

```
## Audit Runde {RUNDE}/5 — X Dateien, Y Commits seit origin/{branch}

### Critical
- [Security] datei.ts:42 — Beschreibung

### Important
- [Code Quality] datei.ts:15 — Beschreibung

### Minor
- [SEO] page.tsx:8 — Beschreibung (optional, nicht Push-blockierend)

### Sauber
Performance, UI/UX/A11y
```

Markiere Todo `Subagents dispatchen` als completed.

**Schritt D.5 — Halluzinations-Validator (PFLICHT vor jedem Fix)**

LLMs halluzinieren Dateien, Zeilen, API-Namen. Pro Finding mit `Datei:Zeile`:

```bash
test -f "{datei}" || echo "HALLUCINATION: file missing"
lines=$(wc -l < "{datei}")
[ "$lines" -ge "{zeile}" ] || echo "HALLUCINATION: line out of range"
```

Pro Finding das eine externe API/Library erwähnt: `grep -r` im Projekt prüfen ob die Library überhaupt importiert wird. Existiert die referenzierte Dependency?

**Halluzinierte Findings rausfiltern — werden NICHT gefixt, nicht gemeldet, nicht gezählt.**

Ausgabe: `Validator: X/Y verifiziert, Z halluziniert (verworfen)`

**Schritt E — Auto-Fix**

Zähle die **verifizierten** Critical+Important. Speichere `FINDINGS_AKTUELLE_RUNDE`. Wenn `RUNDE >= 2` UND `FINDINGS_AKTUELLE_RUNDE >= FINDINGS_VORHERIGE_RUNDE`: Ergebnis `NO_CONVERGENCE`, keine weiteren Fixes. Dann `FINDINGS_VORHERIGE_RUNDE = FINDINGS_AKTUELLE_RUNDE`.

**0 Critical und 0 Important?** → Todo completed → Ergebnis: `SAUBER`.

**Sonst — Confidence-Gate:** Jedes Finding hat eine Confidence (`high`, `medium`, `low`). Bei vagen Formulierungen („könnte", „möglicherweise") = `low`.

- **High** → direkt fixen
- **Medium** → fixen, mit Hinweis `(medium confidence)`
- **Low** → NICHT auto-fixen, als Offener Punkt auflisten

Fixes:
1. Jedes high/medium Critical+Important direkt fixen
2. Minor: fixen wenn einfach und high confidence, sonst überspringen — blockieren Push nicht
3. Kurze Bestätigung pro Fix (`[Datei:Zeile] was gefixt wurde`)
4. Nicht fixbar (z. B. architektonische Entscheidung): als Offener Punkt mit Begründung
5. Gefixte Issues zu `BEREITS_GEFIXT` hinzufügen

Todo completed → Ergebnis: `FIXES_APPLIED`.

**PFLICHT — gib am Ende jeder Runde exakt diese Zeile aus:**

```
AUDIT_STATUS: SAUBER | RUNDE {RUNDE}/5
AUDIT_STATUS: FIXES_APPLIED | RUNDE {RUNDE}/5
AUDIT_STATUS: NO_CONVERGENCE | RUNDE {RUNDE}/5
```

### Nach jeder Runde: Entscheidung

| Ergebnis | RUNDE | Aktion |
|----------|-------|--------|
| `SAUBER` | egal | Loop beendet. Weiter mit Abschnitt 3. |
| `FIXES_APPLIED` | < 5 | `RUNDE = RUNDE + 1`, Prozedur erneut. **Kein Warten auf User.** |
| `FIXES_APPLIED` | = 5 | Loop beendet. Verbleibende Issues auflisten. |
| `NO_CONVERGENCE` | egal | Loop beendet. Warnung: „Findings konvergieren nicht". |

### Loop-Ende

Ausgabe:

```
Audit abgeschlossen nach {RUNDE} Runde(n).
- Runde 1: X Findings, Y gefixt
...
Verbleibende offene Issues: (falls vorhanden)
- [Typ] Datei:Zeile — Beschreibung — Grund warum nicht fixbar
```

**Audit-Log schreiben:**

```bash
AUDIT_DIR="$(git rev-parse --show-toplevel)/.claude/audits"
mkdir -p "$AUDIT_DIR"
BRANCH=$(git branch --show-current | tr '/' '-')
LOGFILE="$AUDIT_DIR/$(date +%Y-%m-%d_%H%M%S)-${BRANCH}.md"
```

Mehrere Audits am selben Tag/Branch werden so nicht überschrieben. Format des Logs:

```markdown
# Audit — {DATUM} — Branch: {BRANCH}

## Scope
- Commits seit origin/{base}: N
- Geänderte Dateien: Liste
- HEAD beim Audit: {git rev-parse HEAD}

## Ergebnis
- Runden: N/5
- Critical gefunden/gefixt: A/B
- Important gefunden/gefixt: C/D

## Gefixte Issues
- [Typ] datei:zeile — was gefixt wurde

## Design-Verification
- Screenshots: .claude/screenshots/{branch}-{hash}/ (oder "übersprungen")
- User-Entscheidung: Go / Manuell anpassen

## Offene Punkte
- (falls vorhanden)

## Sauber
Dimension1, Dimension2
```

Beim nächsten Audit-Lauf: wenn zwischen `{letzter-audit-HEAD}..HEAD` Commits auftauchen die **nicht** im Diff von `origin/$DEFAULT_BRANCH...HEAD` enthalten sind (weil inzwischen gepusht), `/full-audit` empfehlen — der `audit`-Skill sieht gepushte Commits nicht mehr.

**Audit-Log im Chat anzeigen:** Nach dem Schreiben den kompletten Inhalt des Log-Files via Read-Tool laden und als Markdown-Codeblock im Chat ausgeben, damit der User alles nachlesen kann:

```
Audit-Log: {LOGFILE}

---
{Inhalt des Log-Files}
---
```

Der Output erfolgt bevor Abschnitt 3 (Changelog/Linter/Tests/Design) startet — damit der User noch während der Verifikation das Ergebnis im Blick hat.

---

## 3. Changelog, Linter, Tests und Design-Verification (einmal, nach dem Loop)

### 3a. Changelog/Release-Notes

Prüfe selbst ob user-facing Changes einen Changelog-Eintrag brauchen. Kandidaten-Dateien: `CHANGELOG.md`, `changelog.md`, `release-notes/next.md`, `resources/changelog.md`, `CHANGES.md`.

Ignorieren: reine Test-Änderungen, interne Services ohne UI, Refactorings ohne Verhaltensänderung, Config, Migrations ohne neue Features.

Existiert kein passender Eintrag → Eintrag draften, Format orientiert sich am bestehenden Stil der Datei, chronologisch oben einfügen.

### 3b. Linter & Static Analysis · 3c. Test-Suite

Erkennungstabellen und Befehle stehen in `references/linters-and-tests.md`. Reihenfolge: Formatter → Linter → Static Analysis → Tests. Bei Failures: fixen, erneut laufen lassen. Unfixbare Test-Failures als Critical aufnehmen.

**Tests nur diff-scoped:** Nur Tests laufen lassen, die von den geänderten Dateien betroffen sind (Mapping siehe `references/linters-and-tests.md`). NIEMALS `composer test` / `npm test` in `/audit` — die volle Suite läuft in CI. Dieser Skill darf die Laufzeit nicht durch eine 2000+ Test-Suite explodieren lassen.

### 3d. Deterministischer Design-Check

```bash
bash "$HOME/.claude/skills/audit/bin/design-check.sh"
```

Das Script-Ergebnis ist verbindlich — kein LLM-Ermessen.

- `KEINE_VISUELLEN_DATEIEN` → weiter mit Abschnitt 4
- `SCREENSHOTS_ERFORDERLICH` → direkt Schritt 3e (Screenshot-Agent). **Keine Ja/Nein-Frage.** Visuelle Änderungen bedeuten Screenshots — Punkt. Der User kann im finalen GO/Stopp-Schritt immer noch abbrechen.

### 3e. Screenshot-Agent

**Ein einziger Tool-Call.** Du übergibst alles an den Agent und wartest. Kein Server starten, keine URLs ermitteln, kein Screenshot-Verzeichnis anlegen — das macht der Agent.

**Foreground** (NICHT `run_in_background`): er braucht `AskUserQuestion` und ggf. Computer Use.

```
Agent(
  subagent_type: general-purpose,
  model: sonnet,
  prompt: "Lies agents/screenshot-agent.md und führe den kompletten Ablauf aus.
    PROJECT_ROOT={PROJECT_ROOT}
    VISUELL_RELEVANTE_DATEIEN={DATEIEN_AUS_BASH_CHECK}
    FRAMEWORK={FRAMEWORK}"
)
```

`DESIGN_VERIFICATION_RESULT` auswerten:

| Ergebnis | Aktion |
|----------|--------|
| `GO` | Todo completed, weiter mit Abschnitt 4 |
| `SKIPPED_NO_TOOL` | Im Log vermerken, weiter mit Abschnitt 4 |

### Offene Punkte (optional)

Enthält das Audit-Log `## Offene Punkte`, User via AskUserQuestion fragen: „Alle umsetzen / einzeln entscheiden / später". Bei „alle umsetzen": implementieren, dann weiter mit Abschnitt 4.

---

## 4. Pre-Push-Verhalten

Wenn der Audit im Kontext eines blockierten `git push` läuft:

**Hard-Block (nie pushen):**
- `SECRET_SCAN_RESULT=FINDINGS` aus den Pre-Checks → Push abbrechen, User informieren dass Secrets entfernt UND History bereinigt werden müssen (BFG/`git filter-repo`).
- Noch unfixbare Critical/Important, Linter-Fehler oder Tests rot → `BLOCKED: Push abgebrochen.` + Liste der offenen Probleme.
- KEINE Marker-Datei schreiben.

**SPERRE:** Wenn `DESIGN_CHECK_RESULT=SCREENSHOTS_ERFORDERLICH` war und User „Ja, Screenshots" wählte, aber `DESIGN_VERIFICATION_RESULT` NICHT `GO` ist → NICHT pushen. Bei `SKIPPED_BY_USER` oder `SKIPPED_NO_TOOL` darf gepusht werden — der User hat bewusst entschieden.

**Alles gefixt, Tests grün, Design-Verification bestanden (oder keine visuellen Dateien):**

**KRITISCH — Marker und Push NIEMALS im selben Bash-Befehl.** Der Pre-Push-Hook prüft den Command-String auf `git push` und blockiert BEVOR der Marker geschrieben wird. Immer zwei separate Bash-Aufrufe.

```bash
# Schritt 1 — Marker schreiben (kein `git push` im Befehl):
hash=$(echo -n "$PWD" | md5 2>/dev/null || echo -n "$PWD" | md5sum 2>/dev/null | cut -d' ' -f1)
touch "/tmp/claude-audit-passed-$hash"
```

```bash
# Schritt 2 — Push (separater Bash-Aufruf):
git push
# Multi-Repo ohne cd:
git -C /pfad/zum/repo push
```

Danach: `Audit passed.` ausgeben, weiter mit Abschnitt 5 (Learning) und 6 (PR).

**Marker-Details:** Gilt nur für den nächsten Push, wird nach Verwendung gelöscht, < 5 Min gültig. Hash kommt aus `.cwd` des Tool-JSON (Session-Startverzeichnis, unabhängig von `cd`). Für Multi-Repo-Pushes: `git -C /pfad push` statt `cd /pfad && git push`. Nie `cd` im selben Bash-Aufruf wie `git push`.

---

## 5. Learning (nach Audit-Log)

```
Agent(
  prompt: "Lies agents/learning-agent.md und führe den Ablauf aus.
    PROJECT_ROOT={PROJECT_ROOT}
    AKTUELLES_LOG={Inhalt des gerade geschriebenen Audit-Logs}
    AUDIT_TYPE=audit"
  subagent_type: general-purpose
  mode: bypassPermissions
  run_in_background: true
)
```

Läuft im Hintergrund, blockiert weder Push noch PR. Wenn er Guideline-Vorschläge zurückgibt (`GUIDELINE_SUGGESTIONS > 0`), User via AskUserQuestion fragen: „Alle übernehmen / einzeln prüfen / später".

---

## 6. PR erstellen (nach Push)

Ablauf steht in `references/pr-creation.md`. Kurzfassung: Branch prüfen, Commits sammeln, optional Plan-Doc für Description nutzen, PR via `gh pr create` erstellen, URL ausgeben. Fehler blockieren nicht — einfach melden und weitermachen.
