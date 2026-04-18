---
name: audit
description: "Pre-push code audit. Triage-Agent routes diff to relevant subagents (architecture, security, performance, code quality, SEO, a11y, typography, UI design, UX, animation), runs secret/lockfile pre-checks, auto-fixes findings via parallel fix-agents, loops until clean, generates a manual test plan for visual changes, then allows git push. Triggers: /audit, before pushing, git push, pre-push review, review my changes, audit uncommitted changes, check before pushing."
argument-hint: "[optional: scope hint]"
model: claude-opus-4-7
effort: medium
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

# 3. Diff-Size-Gate
bash "$AUDIT_BIN/diff-size-gate.sh"
```

**Diff-Size-Gate auswerten:**

| `DIFF_SIZE_RESULT` | Aktion |
|---|---|
| `OK` | Weiter. `MODEL_OVERRIDE=null` (Subagents nutzen ihre Default-Modelle). |
| `LARGE` (>2000 Zeilen ODER >20 Dateien) | Gezielte Escalation: Nur die zwei reasoning-schweren Dimensionen (Architektur, Security) laufen auf Opus 4.7. Ausgabe: „Diff ist gross ({LINES} Zeilen / {FILES} Dateien) — Architektur + Security laufen auf Opus 4.7 für tieferes Reasoning." Setze `HEAVY_REASONING_OVERRIDE=claude-opus-4-7`. Weiter mit Audit. |
| `HUGE` (>5000 Zeilen ODER >50 Dateien) | Hard-Block: Abbrechen mit klarer Meldung „Diff zu gross fuer sinnvollen Audit. Bitte in mehrere Commits/PRs splitten." Kein Audit-Lauf. |

**Warum nur zwei Dimensionen:** Architektur (Code-Reasoning über mehrere Module) und Security (subtile Angriffsvektoren) profitieren messbar von Opus. Performance, Code Quality, SEO, A11y, Typography, UI, UX, Animation sind überwiegend regel- oder musterbasiert — Sonnet reicht. Triage- und Fix-Agents bleiben auf Haiku.

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

**Audit-Context-Check (PFLICHT bei fehlendem Context):**

Wenn `PROJECT_CONTEXT` leer ist oder die `CLAUDE.md` keinen `## Audit Context`-Abschnitt hat, **vor dem ersten Subagent-Dispatch** den User via `AskUserQuestion` fragen:

```
Dieses Projekt hat keinen "## Audit Context"-Abschnitt in der CLAUDE.md.

Mit Project-Context werden Audit-Findings drastisch praeziser:
- Stack/Framework-spezifische Regeln
- Bewusst akzeptierte Architektur-Entscheidungen
- Skalierungsziele, Zielgruppe, Deployment
- Kritische Schnittstellen (z.B. Mobile-API, Public-Routes)

Soll ich jetzt einen Vorschlag fuer "## Audit Context" entwerfen und in
CLAUDE.md ergaenzen?
```

Optionen:
- **Ja, jetzt anlegen** → Repo-Struktur kurz analysieren (Stack aus `composer.json`/`package.json`, Routes, README), Vorschlag entwerfen, in `CLAUDE.md` einfuegen, dann Audit fortsetzen.
- **Nein, einmal ueberspringen** → Audit fortsetzen ohne Context.
- **Nie wieder fragen** → Marker `.claude/audit-no-context.flag` anlegen, Audit fortsetzen. Beim naechsten Audit prueft der Skill diesen Marker und ueberspringt die Frage.

Marker-Check vor der Frage:
```bash
[ -f "$(git rev-parse --show-toplevel)/.claude/audit-no-context.flag" ] && SKIP_CONTEXT_PROMPT=true
```

Übergib `PROJECT_CONTEXT`, `FRAMEWORK`, `SOURCE_DIRS` und `UNIFIED_DIFF` an alle Subagents.

---

## 2. Audit-Loop

Führe die Prozedur `AUDIT_RUNDE` aus. Danach entscheide: nächste Runde oder Loop beenden. Maximal **3 Runden** — der Convergence-Check bricht typischerweise früher ab.

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

Ausgabe: `Audit-Runde {RUNDE}/3`

TodoWrite: Zwei Todos erstellen:
- `Audit Runde {RUNDE} — Subagents dispatchen` (in_progress)
- `Audit Runde {RUNDE} — Findings fixen` (pending)

**Schritt B — Scope aktualisieren (ab Runde 2)**

`collect-scope.sh` erneut aufrufen — Fixes haben den Diff verändert. `ALLE_DATEIEN` und `FRONTEND_DATEIEN` bleiben identisch, aber der komplette aktualisierte Diff wird allen Subagents erneut übergeben.

**Schritt B.5 — Incremental-Cache pruefen**

```bash
# ALLE_DATEIEN als Zeilen an cache-check uebergeben (safe bei Leerzeichen):
echo "$ALLE_DATEIEN" | tr '\n' '\0' | xargs -0 bash "$AUDIT_BIN/cache-check.sh"
```

Ergebnis: `CACHED_FILES` (unveraenderte Dateien seit letztem Audit) und `CACHED_FINDINGS` (deren historische Findings).

- Cached Files werden **aus dem Triage-Input entfernt** — sie werden dem Triage-Agent nicht mehr gezeigt.
- `CACHED_FINDINGS` werden direkt in die aktuelle Runde uebernommen (gelten weiter).
- Nur veraenderte Dateien gehen durch Triage + Subagents.

**Hinweis:** Der Cache hilft primaer zwischen separaten Audit-Laeufen. Innerhalb desselben Audit-Laufs aendern Fixes die Datei-Hashes, sodass in Runde 2+ fast nie ein Cache-Hit auftritt.

**Schritt C.0 — Triage-Agent (nur Runde 1)**

**Nur in Runde 1** dispatchen. Ab Runde 2 das `TRIAGE_RESULT` aus Runde 1 wiederverwenden — Fixes aendern die Routing-Entscheidung praktisch nie, ein erneuter Triage-Call waere verschwendet.

Dispatche EINEN Triage-Agent (Haiku, schnell, billig). Er liest den Diff einmal und erstellt ein JSON mit: welcher Dimension-Agent muss laufen, welche Hotspots pro Agent, was ist irrelevant.

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

Parse das JSON. Ergebnis: `TRIAGE_RESULT` mit `relevance` pro Dimension. Speichere es fuer Folgerunden.

**Schritt C — Spezial-Subagents parallel dispatchen**

**Regel:** Nur Agents mit `relevance.{dimension}.run == true` aus dem Triage-Ergebnis dispatchen. Security sollte fast immer laufen — Triage ist angewiesen nur bei reinen Doc/Translation-Changes zu skippen.

**PFLICHT: Alle nicht-geskippten Agents in JEDER Runde dispatchen.** Ein Security-Fix kann ein Performance-Problem einfuehren — aber nur wenn Performance vom Triage als relevant markiert wurde.

Dispatche in **einem einzigen Message-Block** via Agent-Tool. Uebergib:
- `TRIAGE_SUMMARY` (die 1-2 Zeilen aus dem Triage-JSON)
- `HOTSPOTS` (die fuer diesen Agent markierten Stellen)
- `UNIFIED_DIFF` (als Fallback, wenn der Agent breiteren Kontext braucht)

Dadurch parst jeder Agent nicht mehr den ganzen Diff von 0 — er fokussiert direkt auf seine Hotspots.

**Model-Override bei Escalation:** Wenn `HEAVY_REASONING_OVERRIDE` in Phase 1 gesetzt wurde (LARGE-Diff), übergib beim Dispatch von **Agent 1 (Architektur) und Agent 2 (Security)** explizit `model: claude-opus-4-7` und ignoriere das `model:`-Feld aus deren `agents/*.md`. Alle anderen Agents (3-10) nutzen unverändert ihr Default-Modell aus `agents/*.md`.

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
| 10 | `agents/10-animation.md` | Animation & Motion Design |

Prompt-Template: `agents/prompt-template.md`, Abschnitt „Für /audit (Diff-basiert)".

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
## Audit Runde {RUNDE}/3 — X Dateien, Y Commits seit origin/{branch}

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

**0 Critical und 0 Important?** → Todo completed → Ergebnis: `SAUBER`. **Early-Exit:** Auch wenn noch Minor-Findings vorhanden sind, wird der Loop sofort beendet. Minor ist nie Push-blockierend, keine zweite Runde noetig.

**Sonst — Confidence-Gate:** Jedes Finding hat eine Confidence (`high`, `medium`, `low`). Bei vagen Formulierungen („könnte", „möglicherweise") = `low`.

- **High** → direkt fixen
- **Medium** → fixen, mit Hinweis `(medium confidence)`
- **Low** → NICHT auto-fixen, als Offener Punkt auflisten

**Fix-Strategie — parallele Fix-Agents:**

1. Gruppiere verifizierte high/medium Critical+Important Findings nach Datei.
2. **Unabhaengige Dateien parallel fixen:** Dispatche pro betroffener Datei einen `fix-agent.md`-Subagent (Haiku) in einem einzigen Message-Block. Jeder Agent bekommt nur sein Finding + Kontext. Das ist billiger und schneller als wenn der Main-Skill alle Fixes sequenziell selbst macht.
3. Bei mehreren Findings in derselben Datei: die Findings in einem einzigen Fix-Agent-Call bundeln (verhindert Merge-Konflikte).
4. Fix-Agent-Ergebnisse einsammeln: `FIX_RESULT=APPLIED` zaehlt als gefixt, alles andere wird als Offener Punkt gelistet.
5. Minor: fixen wenn einfach und high confidence, sonst ueberspringen — blockieren Push nicht.
6. Nicht fixbar (z. B. architektonische Entscheidung): als Offener Punkt mit Begruendung → `patterns-store.sh dismissed {pattern}` aufrufen. Wenn `should-suggest {pattern}` true: User fragen ob Eintrag in `suppressions.json` soll.
7. Gefixte Issues zu `BEREITS_GEFIXT` hinzufuegen und via `patterns-store.sh add` ins Learning-Store schreiben.

Todo completed → Ergebnis: `FIXES_APPLIED`.

**PFLICHT — gib am Ende jeder Runde exakt diese Zeile aus:**

```
AUDIT_STATUS: SAUBER | RUNDE {RUNDE}/3
AUDIT_STATUS: FIXES_APPLIED | RUNDE {RUNDE}/3
AUDIT_STATUS: NO_CONVERGENCE | RUNDE {RUNDE}/3
```

### Nach jeder Runde: Entscheidung

| Ergebnis | RUNDE | Aktion |
|----------|-------|--------|
| `SAUBER` | egal | Loop beendet. Weiter mit Abschnitt 3. |
| `FIXES_APPLIED` | < 3 | `RUNDE = RUNDE + 1`, Prozedur erneut. **Kein Warten auf User.** |
| `FIXES_APPLIED` | = 3 | Loop beendet. Verbleibende Issues auflisten. |
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
- Runden: N/3
- Critical gefunden/gefixt: A/B
- Important gefunden/gefixt: C/D

## Gefixte Issues
- [Typ] datei:zeile — was gefixt wurde

## Manueller Testplan
- (Testplan-Schritte, falls visuelle Dateien geaendert wurden)

## Offene Punkte
- (falls vorhanden)

## Sauber
Dimension1, Dimension2
```

Beim nächsten Audit-Lauf: wenn zwischen `{letzter-audit-HEAD}..HEAD` Commits auftauchen die **nicht** im Diff von `origin/$DEFAULT_BRANCH...HEAD` enthalten sind (weil inzwischen gepusht), `/full-audit` empfehlen — der `audit`-Skill sieht gepushte Commits nicht mehr.

**Cache aktualisieren** (nach erfolgreichem Loop-Ende):

```bash
# JSON mit allen geauditeten Dateien und finalen Findings pipen:
echo '{"files": [...], "findings": [...]}' | bash "$AUDIT_BIN/cache-write.sh"
```

Nur auditierte Dateien, die nach allen Fixes sauber sind, kommen in den Cache. Dateien mit verbleibenden Offenen Punkten werden NICHT gecached (damit sie beim naechsten Audit erneut geprueft werden).

**Hinweis:** Das Audit-Log wird erst nach Abschnitt 3 (inkl. Testplan) im Chat angezeigt, damit der Testplan bereits enthalten ist.

---

## 3. Changelog, Linter, Tests und Design-Verification (einmal, nach dem Loop)

### 3a. Changelog/Release-Notes

Prüfe selbst ob user-facing Changes einen Changelog-Eintrag brauchen. Kandidaten-Dateien: `CHANGELOG.md`, `changelog.md`, `release-notes/next.md`, `resources/changelog.md`, `CHANGES.md`.

Ignorieren: reine Test-Änderungen, interne Services ohne UI, Refactorings ohne Verhaltensänderung, Config, Migrations ohne neue Features.

Existiert kein passender Eintrag → Eintrag draften, Format orientiert sich am bestehenden Stil der Datei, chronologisch oben einfügen.

### 3b. Linter & Static Analysis · 3c. Test-Suite

Erkennungstabellen und Befehle stehen in `references/linters-and-tests.md`. Reihenfolge: Formatter → Linter → Static Analysis → Tests. Bei Failures: fixen, erneut laufen lassen. Unfixbare Test-Failures als Critical aufnehmen.

**Tests nur diff-scoped:** Nur Tests laufen lassen, die von den geänderten Dateien betroffen sind (Mapping siehe `references/linters-and-tests.md`). NIEMALS `composer test` / `npm test` in `/audit` — die volle Suite läuft in CI. Dieser Skill darf die Laufzeit nicht durch eine 2000+ Test-Suite explodieren lassen.

### 3d. Manueller Testplan erstellen

Wenn visuelle Dateien im Diff sind (FRONTEND_DATEIEN oder VISUELL_RELEVANTE_DATEIEN nicht leer), erstelle einen konkreten Testplan, den der User lokal durchgehen kann.

**Testplan generieren** — basierend auf dem Diff, Framework und geaenderten Dateien:

```markdown
## Manueller Testplan

**Branch:** {BRANCH}
**Geaenderte visuelle Dateien:** {Liste}

### Schritte

1. [ ] **{Seitenname}** — {URL oder Route}
   - Pruefe: {was sich geaendert hat, z.B. "neuer Button-Variant 'danger'"}
   - Desktop + Mobile testen
   - {Spezifischer Hinweis, z.B. "Dark Mode pruefen falls aktiv"}

2. [ ] **{Seitenname}** — {URL oder Route}
   - Pruefe: {konkrete Aenderung}
   ...

### Worauf besonders achten
- {Edge Cases aus dem Diff, z.B. "Leerer Zustand wenn keine Items vorhanden"}
- {Responsive-Verhalten, z.B. "Tabelle bricht unter 768px auf Cards um"}
- {A11y-relevant, z.B. "Neue Buttons muessen per Tastatur erreichbar sein"}
```

**Regeln fuer den Testplan:**
- Nur Schritte fuer tatsaechlich geaenderte Stellen — kein generischer "pruefe alles"-Plan.
- URLs/Routes aus dem Framework ableiten (Next.js: Dateipfad = URL, Laravel: `routes/web.php`, Nuxt: `pages/` = URL).
- Max. 10 Schritte — priorisiert nach Sichtbarkeit und Risiko.
- Rein textuell — keine externen Tools oder Server noetig.

Den Testplan ins Audit-Log unter `## Manueller Testplan` schreiben UND im Chat ausgeben.

### 3e. Audit-Log im Chat anzeigen (PFLICHT — nach Testplan)

Nach Abschluss von 3a-3d den kompletten Inhalt des Log-Files (inkl. Testplan) via Read-Tool laden und als Markdown-Codeblock im Chat ausgeben:

```
Audit-Log: {LOGFILE}

---
{Inhalt des Log-Files}
---
```

So hat der User das vollstaendige Ergebnis inkl. Testplan auf einen Blick.

### Offene Punkte (optional)

Enthaelt das Audit-Log `## Offene Punkte`, User via AskUserQuestion fragen: „Alle umsetzen / einzeln entscheiden / spaeter". Bei „alle umsetzen": implementieren, dann weiter mit Abschnitt 4.

---

## 4. Pre-Push-Verhalten

Wenn der Audit im Kontext eines blockierten `git push` läuft:

**Hard-Block (nie pushen):**
- `SECRET_SCAN_RESULT=FINDINGS` aus den Pre-Checks → Push abbrechen, User informieren dass Secrets entfernt UND History bereinigt werden müssen (BFG/`git filter-repo`).
- Noch unfixbare Critical/Important, Linter-Fehler oder Tests rot → `BLOCKED: Push abgebrochen.` + Liste der offenen Probleme.
- KEINE Marker-Datei schreiben.

**Alles gefixt, Tests gruen:**

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

**Marker-Details:** Gueltig fuer 30 Minuten (TTL), wird NICHT nach Verwendung geloescht (mehrere Hooks pruefen denselben Marker sequenziell). Hash kommt aus `.cwd` des Tool-JSON (Session-Startverzeichnis, unabhängig von `cd`). Für Multi-Repo-Pushes: `git -C /pfad push` statt `cd /pfad && git push`. Nie `cd` im selben Bash-Aufruf wie `git push`.

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

Läuft im Hintergrund, blockiert weder Push noch PR. Vorschläge werden ausschließlich in die `learning-log.md` geschrieben — der User kann sie dort später einsehen.

---

## 6. PR erstellen (nach Push)

Ablauf steht in `references/pr-creation.md`. Kurzfassung: Branch prüfen, Commits sammeln, optional Plan-Doc für Description nutzen, PR via `gh pr create` erstellen, URL ausgeben. Fehler blockieren nicht — einfach melden und weitermachen.
