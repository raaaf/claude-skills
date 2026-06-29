---
name: audit
disable-model-invocation: true
description: "Pre-push code audit. Triage routes the diff to relevant subagents (architecture incl. migrations and observability, security, performance, code quality, SEO, a11y, typography, UI, UX, animation, docs sync, copy), runs secret/lockfile/i18n pre-checks, auto-fixes via parallel fix-agents with peer-review verification, loops until clean, generates a manual test plan, then allows git push. Use when the user runs /audit, says 'before pushing' or 'review my changes', or has uncommitted/unpushed changes that should be checked. NOT for whole-codebase audits — use /full-audit instead."
when_to_use: "/audit, before pushing, git push, pre-push review, review my changes, audit uncommitted changes, check before pushing"
argument-hint: "[optional: scope hint]"
model: opus
effort: high
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

**SOFORT AUSFÜHREN — nicht erklären, nicht ankündigen. Direkt mit Phase 0 beginnen.**

Anti-Patterns / häufige Fehler im Loop: `references/anti-patterns.md`.

## Phase 0: Learning-Backlog-Check

Pruefe ob unverarbeitete Lerning-Vorschlaege aus frueheren Audits offen sind:

```bash
LOG="$(git rev-parse --show-toplevel)/.claude/audits/learning-log.md"
[ -f "$LOG" ] && grep -c "^- \[ \] " "$LOG" 2>/dev/null || echo 0
```

Wenn `>= 1`: User via `AskUserQuestion` fragen mit Optionen:
- **Vorschlaege jetzt umsetzen** → Vorschlaege auflisten, User waehlt welche, Orchestrator dispatcht passende Aenderungen an `audit/guidelines/*.md` oder `audit/agents/*.md`. **WICHTIG — ins Quell-Repo editieren:** `~/.claude/skills/*` kann ein Sync-Ziel sein (Symlink oder entpacktes `.skill`-Bundle), dessen Inhalt ueberschrieben wird. Vor dem ersten Edit Quelle aufloesen (`readlink` bzw. Skill-Quell-Repo finden, z.B. `~/Local Sites/claude-skills`) und DORT editieren — Edits in der entpackten Kopie gehen beim naechsten Sync verloren. Nach Umsetzung: `[ ]` zu `[x]` aendern in learning-log.md. Dann Audit weiter mit Phase 1.
- **Spaeter, Audit jetzt** → Phase 1 starten, Vorschlaege bleiben offen.
- **Nie wieder fragen fuer diese Audits** → `[skip]`-Marker an betroffene Zeilen anhaengen, sie zaehlen nicht mehr.

Wenn `0`: weiter ohne Frage.

### Phase 0.2: Offene Audit-Issues & PRs

```bash
if gh repo view >/dev/null 2>&1 && git remote get-url origin 2>/dev/null | grep -q github.com; then
  OPEN_AUDIT_ISSUES=$(gh issue list --state open --label audit-finding --json number,title --jq '.[] | "#\(.number) \(.title)"' 2>/dev/null || true)
  OPEN_PRS=$(gh pr list --state open --json number,title,headRefName --jq '.[] | "#\(.number) \(.title) [\(.headRefName)]"' 2>/dev/null || true)
fi
```

**Offene `audit-finding`-Issues vorhanden?** → AskUserQuestion (Liste kompakt zeigen):
- **Jetzt mitfixen** — ausgewaehlte Issues werden als verifizierte Findings in Runde 1 eingespeist (Fix-Agent + Fix-Verifier wie ueblich). Nach erfolgreichem Fix: `gh issue close {N} --comment "Fixed in audit {DATUM}, commit folgt im naechsten Push."`
- **Offen lassen** — Issues bleiben, Audit laeuft normal.

**`OPEN_PRS` nicht leer?** → Als Kontext merken (keine Frage):
- In Phase 3f-Dedup: kein neues Issue fuer etwas, das ein offener PR bereits adressiert.
- Wenn ein offener PR dieselben Dateien anfasst wie der aktuelle Diff: Hinweis im Audit-Log (`## Hinweise: PR-Ueberschneidung`) — Merge-Konflikt-Risiko.

**Skip dieser Phase (0 + 0.2) wenn:** ENV `AUDIT_SKIP_LEARNING_CHECK=1` gesetzt (fuer CI/Batch-Runs) — dann auch keine Issue-Frage.

## Phase 0.5: Effort Configuration

Skill skaliert Tiefe nach `${CLAUDE_EFFORT}`. Default `medium`.

```bash
CLAUDE_EFFORT="${CLAUDE_EFFORT:-medium}"
case "$CLAUDE_EFFORT" in
  low)    MAX_RUNDEN=1; FIX_MINOR=0; SKIP_LEARNING=1; CONFIDENCE_FLOOR=high ;;
  high)   MAX_RUNDEN=3; FIX_MINOR=1; SKIP_LEARNING=0; CONFIDENCE_FLOOR=low ;;
  medium|*) MAX_RUNDEN=2; FIX_MINOR=1; SKIP_LEARNING=0; CONFIDENCE_FLOOR=medium ;;
esac
echo "Effort=$CLAUDE_EFFORT | Runden=$MAX_RUNDEN | FixMinor=$FIX_MINOR | SkipLearning=$SKIP_LEARNING | ConfidenceFloor=$CONFIDENCE_FLOOR"
```

| Level | Runden | Fix Minor | Learning | Confidence-Floor |
|---|---|---|---|---|
| low | 1 | nein | skip | high (nur sichere Fixes) |
| medium (Default) | 2 | ja | ja | medium |
| high | 3 | ja | ja | low (auch unsichere fixen, mit Warnung) |

Im Folgenden bedeutet `{MAX_RUNDEN}` der hier gesetzte Wert.

## Phase 1: Pre-Flight & Scope

```bash
AUDIT_BIN="${CLAUDE_SKILL_DIR}/bin"
AUDIT_AGENTS_DIR="${CLAUDE_SKILL_DIR}/agents"

# PreCompact-Schutz: blockiert Auto-Compaction waehrend des Audit-Runs
CWD_HASH=$(pwd | md5 2>/dev/null || pwd | md5sum 2>/dev/null | cut -d' ' -f1)
touch "/tmp/claude-audit-in-progress-${CWD_HASH}"

bash "$AUDIT_BIN/verify-agents.sh" "$AUDIT_AGENTS_DIR" || { echo "Audit abgebrochen — fehlende Agent-Dateien."; exit 1; }
bash "$AUDIT_BIN/collect-scope.sh"
bash "$AUDIT_BIN/detect-framework.sh"
bash "$AUDIT_BIN/pre-checks.sh"

# Dependency-Vulnerabilities (nur wenn Manifest/Lockfile im Diff)
if echo "$ALLE_DATEIEN" | grep -qE '(package(-lock)?\.json|composer\.(json|lock)|yarn\.lock|pnpm-lock\.yaml|requirements\.txt|pyproject\.toml|Podfile(\.lock)?|Package\.(swift|resolved)|pubspec\.(yaml|lock)|build\.gradle)'; then
  bash "$AUDIT_BIN/check-outdated.sh" "$(git rev-parse --show-toplevel)" --security-only
  # DEP_SECURITY_RESULT=VULNS -> jede gemeldete Zeile wird ein Critical-Finding
  # [Security] (verwundbare Dependency blockiert Push wie jedes Critical).
  # SKIP/CLEAN -> nichts tun. Outdated-Check laeuft hier bewusst NICHT (Noise).
fi

# i18n-Vollstaendigkeit (deterministisch, kein LLM)
bash "$AUDIT_BIN/check-i18n-keys.sh"
# I18N_RESULT=MISSING → jede Zeile "MISSING {locale}: {key}" wird ein
# Important-Finding [i18n] (Schritt D), sofern die betroffenen Keys/Files
# im Diff liegen. Bei /audit ausserhalb des Diffs: als Hinweis ausgeben,
# nicht als Finding. SKIP/OK → nichts tun.

# Project-Specific Guidelines (Override global)
PROJECT_GUIDELINES_FILE="$(git rev-parse --show-toplevel)/.claude/audit-guidelines.md"
PROJECT_GUIDELINES=""
if [ -f "$PROJECT_GUIDELINES_FILE" ]; then
  PROJECT_GUIDELINES=$(cat "$PROJECT_GUIDELINES_FILE")
  echo "Project guidelines: $PROJECT_GUIDELINES_FILE ($(wc -l < "$PROJECT_GUIDELINES_FILE") lines)"
fi
bash "$AUDIT_BIN/diff-size-gate.sh"

# Verify-by-Measurement: Mess-Kommando fuer Performance-Fixes erkennen (opt-in, evtl. leer)
eval "$(bash "$AUDIT_BIN/perf-measure.sh" --detect)"   # setzt PERF_MEASURE_CMD

# Working-Tree-Exklusivitaet: Basis-Zustand festhalten (Check in Phase 4)
AUDIT_BASE_HEAD=$(git rev-parse HEAD)
AUDIT_BASE_STATUS_HASH=$(git status --porcelain | { md5 2>/dev/null || md5sum | cut -d' ' -f1; })
```

**WIP-/Stale-Snapshot-Scope-Check (vor Phase 2):** `git status --porcelain` + `git diff --stat` ansehen. Enthaelt der Working-Tree Dateien, die erkennbar NICHT zur gerade besprochenen Aufgabe gehoeren (vorbestehende WIP eines anderen Arbeitsstrangs, fremde uncommittete Edits, stale Snapshots)? Dann NICHT stillschweigend mitauditieren, sondern den User via `AskUserQuestion` nach dem Scope fragen: **nur die Session-/Aufgaben-Aenderungen** vs. **ganzer Working-Tree**. Heuristik fuer "gehoert nicht dazu": Dateien in ganz anderen Modulen als der Rest des Diffs, oder Dateien die schon vor Sessionbeginn `M` waren. Im Zweifel fragen — ein Audit auf fremdem WIP produziert Findings auf Code, den der User gerade gar nicht bearbeitet.

Detail-Auswertung der Script-Outputs in `references/scope-and-pre-checks.md`:
- Diff-Size-Gate-Tabelle (OK/LARGE/HUGE)
- Pre-Check-Auswertung (Secrets, Lockfile, Binary-Artefakte)
- Variable-Ableitung (ALLE_DATEIEN, FRONTEND_DATEIEN, UNIFIED_DIFF, SUPPRESSIONS, PROJECT_CONTEXT)
- Audit-Context-Check (PFLICHT bei fehlendem Context)

Übergib `PROJECT_CONTEXT`, `PROJECT_GUIDELINES`, `FRAMEWORK` und `SOURCE_DIRS` an alle Subagents. Den `UNIFIED_DIFF` bekommt nur der **Triage-Agent** zur Hotspot-Bestimmung — Workers bekommen statt des Diffs nur die ihnen zugeordneten Hotspots (siehe Phase 2 Schritt C).

---

## Phase 2: Audit-Loop

Maximal **{MAX_RUNDEN} Runden** (aus Phase 0.5). Convergence-Check: Wenn `Critical + Important` der aktuellen Runde NICHT sinkt UND `RUNDE >= 2`, Loop abbrechen mit `NO_CONVERGENCE`.

Initialisiere: `RUNDE = 1`, `BEREITS_GEFIXT = []`, `FINDINGS_VORHERIGE_RUNDE = null`.

### Prozedur AUDIT_RUNDE

**Schritt A — Ankündigung + Todos**

Ausgabe: `Audit-Runde {RUNDE}/{MAX_RUNDEN}`. TodoWrite: `Subagents dispatchen` (in_progress), `Findings fixen` (pending).

**Schritt B — Scope aktualisieren (ab Runde 2)**

`collect-scope.sh` erneut. `ALLE_DATEIEN` und `FRONTEND_DATEIEN` bleiben identisch. Diff geht erneut nur an Triage falls dieser nochmal laeuft (siehe C.0). Workers bekommen weiterhin nur Hotspots.

**Schritt B.5 — Incremental-Cache**

```bash
echo "$ALLE_DATEIEN" | tr '\n' '\0' | xargs -0 bash "$AUDIT_BIN/cache-check.sh"
```

`CACHED_FILES` werden aus dem Triage-Input entfernt. `CACHED_FINDINGS` werden uebernommen. Hilft primaer zwischen Audit-Laeufen.

**Schritt C.0 — Triage-Agent (nur Runde 1)**

Ab Runde 2 das `TRIAGE_RESULT` aus Runde 1 wiederverwenden — Fixes aendern die Routing-Entscheidung praktisch nie.

```
Agent(
  subagent_type: general-purpose,
  model: haiku,
  prompt: "Lies agents/0-triage.md und fuehre die Triage durch.
    UNIFIED_DIFF: {UNIFIED_DIFF}
    FRONTEND_DATEIEN: {FRONTEND_DATEIEN}
    TRANSLATION_DATEIEN: {TRANSLATION_DATEIEN}
    FRAMEWORK: {FRAMEWORK}
    PROJECT_CONTEXT: {PROJECT_CONTEXT}
    SUPPRESSIONS: {SUPPRESSIONS}
    Gib NUR das JSON zurueck."
)
```

Ergebnis: `TRIAGE_RESULT` mit `relevance` pro Dimension. Speichern fuer Folgerunden.

**Schritt C.0.5 — Sanity-Floor + Routing-Transparenz (deterministisch, JEDE Runde)**

Triage laeuft auf Haiku, dem billigsten Modell, und entscheidet was alle teuren Worker sehen. Verlasse dich nicht allein darauf:

```bash
printf '%s' '{TRIAGE_RESULT_JSON}' | bash "$AUDIT_BIN/check-skips.sh" "{FRAMEWORK}"
```

Er leitet Datei-Signale selbst aus git ab und ueberschreibt offensichtliche Fehlskips (Frontend → `a11y`/`ui_design`/`ux`; Translation → `copy`/`typography`; Migration → `architecture`; Code → `code_quality`/`security`; Regeln im Script) und gibt `ROUTING_RUN` (Triage-run plus Floor), `ROUTING_SKIPPED`, `ROUTING_OVERRIDE` und eine `Routing:`-Zeile zurueck. **PFLICHT:** Die `Routing:`-Zeile jede Runde im Chat ausgeben und am Loop-Ende unter `## Routing` ins Audit-Log (eine Zeile pro Runde); Dispatch (Schritt C) nutzt `ROUTING_RUN`. Floor laeuft auch ab Runde 2 (billig), das Haiku-Triage wird ab Runde 2 wiederverwendet.

**Schritt C — Spezial-Subagents parallel dispatchen**

Nur Agents aus `ROUTING_RUN` (Schritt C.0.5: Triage-run plus deterministischer Floor) dispatchen. Security fast immer. Alle nicht-geskippten Agents in JEDER Runde.

Dispatche in **einem Message-Block** via Agent-Tool. Uebergib NUR:
- `TRIAGE_SUMMARY` (1-2 Zeilen)
- `HOTSPOTS` (markierte Stellen, exakte Datei:Zeile)
- `DATEILISTE` (zur Orientierung)

**KEIN UNIFIED_DIFF.** Workers lesen Code via Read-Tool wenn noetig (max 5 Files pro Agent pro Runde).

**Model-Override bei Escalation:** Wenn `HEAVY_REASONING_OVERRIDE=opus` aus Phase 1 gesetzt ist (LARGE-Diff), Agent 1 (Architektur) und Agent 2 (Security) explizit auf Opus dispatchen. Andere Agents nutzen ihr `agents/*.md` Default.

| # | Agent | Kurzname |
|---|---|---|
| 1 | `agents/1-architecture.md` | Architektur & Code Reuse |
| 2 | `agents/2-security.md` | Security |
| 3 | `agents/3-performance.md` | Performance |
| 4 | `agents/4-code-quality.md` | Code Quality |
| 5 | `agents/5-seo.md` | SEO |
| 6 | `agents/6-a11y.md` | A11y (WCAG) |
| 7 | `agents/7-typography.md` | Typography |
| 8 | `agents/8-ui-design.md` | UI Design |
| 9 | `agents/9-ux.md` | UX Patterns |
| 10 | `agents/10-animation.md` | Animation |
| 11 | `agents/11-docs-sync.md` | Docs Sync & Style |
| 12 | `agents/12-copy.md` | Copy & UX-Writing |

Prompt-Template: `agents/prompt-template.md`, Abschnitt "Fuer /audit (Diff-basiert)".

**Schritt D — Konsolidieren + Deduplizieren**

Gleiche Stelle von mehreren Subagents → ein Finding, strengste Einstufung gewinnt.

Pruefe SELBST (nur Runde 1):
- Oeffentliche Seiten / Changelog (siehe Phase 3a)
- Tests: geaenderte Logik ohne Tests?
- Mobile Apps: `bash bin/detect-mobile.sh` → bei Treffer Impact aus `references/mobile-impact.md`

(Hinweis: Docs-Sync laeuft als Agent 11 — kein separater Orchestrator-Check noetig.)

Eigene Findings als Important einfuegen.

Ausgabe-Format:
```
## Audit Runde {RUNDE}/2 — X Dateien, Y Commits seit origin/{branch}

### Critical
- [Dimension] datei:zeile — Beschreibung

### Important / Minor / Sauber
[gleiche Struktur]
```

**Schritt D.5 — Halluzinations-Validator (PFLICHT vor jedem Fix)**

```bash
test -f "{datei}" || echo "HALLUCINATION: file missing"
[ "$(wc -l < "{datei}")" -ge "{zeile}" ] || echo "HALLUCINATION: line out of range"
```

Externe APIs/Libraries: `grep -r` im Projekt pruefen ob importiert. Halluzinierte Findings rausfiltern. Ausgabe: `Validator: X/Y verifiziert, Z halluziniert (verworfen)`.

**Schritt E — Auto-Fix**

Zaehle verifizierte Critical+Important. Speichere `FINDINGS_AKTUELLE_RUNDE`. Convergence-Check siehe oben.

**0 Critical und 0 Important?** → `SAUBER`. Early-Exit (Minor blockiert nie Push).

**Sonst — Confidence-Gate (skaliert mit `CONFIDENCE_FLOOR` aus Phase 0.5):**
- `floor=high` (low effort): nur `high` fixen, Rest bleibt im Log (keine Issues, kein Nachverifizieren — low effort ist der Schnell-Modus)
- `floor=medium` (medium effort): `high`+`medium` fixen. `low` → **Nachverifikation** (siehe unten)
- `floor=low` (high effort): alle fixen, `low`-Fixes mit Warn-Marker `(LOW CONFIDENCE FIX)`

**Nachverifikation fuer low-confidence (medium effort):** Orchestrator liest die betroffene Stelle gezielt (Read-Tool). Bestaetigt sich das Finding → wie `medium` behandeln (fixen). Nicht bestaetigbar → verwerfen + `patterns-store.sh dismissed` — ein unbestaetigtes Finding gehoert NICHT in den Issue-Tracker.

**Offene Punkte sind ab jetzt NUR noch:** echte Entscheidungs-Punkte (Architektur-Tradeoffs, Verhaltens-Aenderungen, Scope-Fragen), die ein Agent nicht entscheiden darf. Alles andere wird gefixt oder verworfen.

**Self-Regression vs. pre-existing (Priorisierung):** Liegt ein Finding auf einer Zeile, die im aktuellen Branch-Diff geaendert wurde (`git blame`/Diff-Abgleich), ist es eine **Self-Regression** — IMMER fixen, nie parken, auch wenn es ein Entscheidungs-Punkt zu sein scheint (der Branch hat das Problem eingefuehrt). Nur Findings auf unveraenderten, pre-existing Zeilen duerfen als Offener Punkt geparkt werden.

**HARTE REGEL: Orchestrator editiert NIEMALS Code-Dateien selbst.** Jeder Code-Fix geht via Fix-Agent (Sonnet). Edits vom Orchestrator auf Opus kosten ein Mehrfaches.

**Erlaubte Orchestrator-Edits:** `.claude/audits/*.md`, `CLAUDE.md` Audit-Context-Entwurf, `suppressions.json` (mit User-Zustimmung), Changelog-Dateien.

**Verify-by-Measurement (Perf) — Baseline:** Enthaelt die Runde ein `[Performance]`-Finding und ist `PERF_MEASURE_CMD` gesetzt, VOR dem Fix-Agent-Dispatch einmal die Baseline messen: `eval "$(bash "$AUDIT_BIN/perf-measure.sh" --run "$PERF_MEASURE_CMD")"; PERF_BASELINE="$PERF_METRIC"`. Details: `references/perf-measurement.md`.

1. Findings nach Datei gruppieren
2. Pro Datei einen `fix-agent.md`-Subagent (Sonnet) parallel dispatchen
3. Mehrere Findings in derselben Datei: in einem Fix-Agent-Call bundeln
3a. **Zentralisierungs-Findings (neue Shared-Utility):** Extrahiert ein Finding ein dupliziertes Pattern in ein neues `lib/*.js` / Helper / Trait, ZUERST alle Vorkommen greppen (`grep -rn "{altes_pattern}" src/`, Glob an Projektsprache anpassen) und ALLE Treffer-Dateien an EINEN Fix-Agent uebergeben (kein paralleler Split, sonst Datei-Kollision). Als Zentralisierungs-Fix markieren, damit der Fix-Agent jede Fundstelle migriert (siehe `fix-agent.md` Sonderfall).
4. Ergebnisse einsammeln: `FIX_RESULT=APPLIED` zaehlt als gefixt
5. Minor: bei `FIX_MINOR=1` (medium + high effort) alle high/medium-confidence Minor fixen, sonst skippen. Nicht gefixte Minor bleiben NUR im Audit-Log — nie als Issue.
6. Nicht fixbar weil Entscheidung noetig: als Offener Punkt mit Begruendung (siehe Definition oben). Nicht fixbar aus anderem Grund (z.B. externes System): verwerfen + `patterns-store.sh dismissed {pattern}`
7. Gefixte Issues zu `BEREITS_GEFIXT` adden, via `patterns-store.sh add` ins Learning-Store

**Schritt E.5 — Fix-Verification (PFLICHT bei medium/high effort, SKIP bei low)**

Fuer jeden `FIX_RESULT=APPLIED` einen Fix-Verifier-Subagent (sonnet) dispatchen:

```
Agent(
  subagent_type: code-reviewer,
  model: sonnet,
  prompt: "Lies agents/fix-verifier.md und bewerte den folgenden Fix.
    ORIGINAL_FINDING: {finding}
    FIX_DIFF: {diff_des_fix_agents}
    FIX_DATEI: {datei}
    PROJECT_GUIDELINES: {PROJECT_GUIDELINES}"
)
```

Auswertung des `FIX_VERIFIER_RESULT`:
- `RECOMMEND=keep` → Fix bleibt, weiter
- `RECOMMEND=patch` → Fix bleibt, aber Finding bleibt in `FINDINGS_NAECHSTE_RUNDE` als "Fix needs improvement"
- `RECOMMEND=revert` → `git checkout {FIX_DATEI}` (Fix rueckgaengig), Original-Finding zurueck in offene Liste

Parallelisierung: Alle Verifier in einem Message-Block, max 10 parallel. Latenz-Add: ~3-5s pro Runde.

**Token-Cost:** Verifier ist Sonnet, kostet ca. ein Drittel eines Workers. Bei N Fixes also +N*0.3 Worker-Kosten. Lohnt sich weil falsche Fixes spaeter teuer sind.

**Performance-Fixes — Verify-by-Measurement (wenn `PERF_MEASURE_CMD` gesetzt und Baseline in Schritt E erhoben):** Nach allen Fixes der Runde re-messen: `eval "$(bash "$AUDIT_BIN/perf-measure.sh" --run "$PERF_MEASURE_CMD")"; PERF_AFTER="$PERF_METRIC"`. Verdikt deterministisch: `AFTER <= BASELINE` → Perf-Fixes `keep` (Log: `Verifikation: measured {BASELINE}->{AFTER}`); `AFTER > BASELINE` → Regression, Perf-Fixes als Offenen Punkt + fix-verifier zur Eingrenzung; `NA` → Fallback fix-verifier. Korrektheit/Regression anderer Dimensionen prueft weiterhin der fix-verifier. Details: `references/perf-measurement.md`.

**PFLICHT — Status-Zeile am Ende jeder Runde:**

```
AUDIT_STATUS: SAUBER | RUNDE {RUNDE}/{MAX_RUNDEN}
AUDIT_STATUS: FIXES_APPLIED | RUNDE {RUNDE}/{MAX_RUNDEN}
AUDIT_STATUS: NO_CONVERGENCE | RUNDE {RUNDE}/{MAX_RUNDEN}
```

### Nach jeder Runde

| Ergebnis | Aktion |
|---|---|
| `SAUBER` | Loop beendet → Phase 2.5 (falls Multi-File) → Phase 3 |
| `FIXES_APPLIED` + RUNDE < {MAX_RUNDEN} | `RUNDE += 1`, Prozedur erneut. Kein User-Wait. |
| `FIXES_APPLIED` + RUNDE = {MAX_RUNDEN} | Loop beendet → Phase 2.5 (falls Multi-File) → Phase 3 |
| `NO_CONVERGENCE` | Loop beendet → Phase 3. Warnung. |

---

## Phase 2.5: Cross-Reference (Multi-File-Features)

**Trigger:** Anzahl geaenderter Dateien >= 3 UND `CONFIDENCE_FLOOR != high` (skip auf low effort).

```bash
FILES_CHANGED_COUNT=$(echo "$ALLE_DATEIEN" | wc -l)
if [ "$FILES_CHANGED_COUNT" -ge 3 ] && [ "$CONFIDENCE_FLOOR" != "high" ]; then
  RUN_CROSS_REF=1
else
  RUN_CROSS_REF=0
  echo "Cross-Ref skipped (files=$FILES_CHANGED_COUNT, floor=$CONFIDENCE_FLOOR)"
fi
```

Wenn `RUN_CROSS_REF=1`: einen Cross-Ref-Subagent (sonnet) dispatchen:

```
Agent(
  subagent_type: code-reviewer,
  model: sonnet,
  prompt: "Cross-Reference-Pruefung der geaenderten Dateien.
    DATEILISTE: {ALLE_DATEIEN}
    BEREITS_GEFIXT: {BEREITS_GEFIXT}
    PROJECT_GUIDELINES: {PROJECT_GUIDELINES}

    Pruefe NUR Cross-File-Probleme:
    - Services <-> UI: falsch aufgerufen, Signaturen passen nicht
    - Models <-> Traits/Mixins: falsch genutzt
    - Controller <-> View: Mismatches (z.B. Variable im View nicht uebergeben)
    - Konsistenz: gleiches Pattern projektweit (Auth-Checks, Cache-Keys, Error-Handling)
    - Ein Fix in Datei A koennte Datei B brechen (z.B. Method-Rename)

    Output-Format wie Worker-Findings. Max 50 Worte pro Finding."
)
```

Findings werden behandelt wie Critical/Important (gleiches Confidence-Gate). Auto-Fix nach gleichen Regeln (Fix-Agent).

---

### Audit-Log schreiben (nach Loop-Ende)

```bash
AUDIT_DIR="$(git rev-parse --show-toplevel)/.claude/audits"
mkdir -p "$AUDIT_DIR"
LOGFILE="$AUDIT_DIR/$(date +%Y-%m-%d_%H%M%S)-$(git branch --show-current | tr '/' '-').md"
```

Format-Template: `references/audit-log-template.md`. Mehrere Audits am selben Tag/Branch werden so nicht ueberschrieben.

**Cache aktualisieren** (nach Loop-Ende):
```bash
echo '{"files": [...], "findings": [...]}' | bash "$AUDIT_BIN/cache-write.sh"
```
Nur Dateien, die nach allen Fixes sauber sind. Dateien mit Offenen Punkten NICHT cachen.

---

## Phase 3: Post-Loop (Changelog, Tests, Testplan, Issues, Display)

**PFLICHT:** Lies jetzt `references/post-loop.md` und fuehre 3a-3f sequenziell aus. Keine dieser Subphasen ist optional. Wenn ein Schritt nicht anwendbar ist (z.B. keine visuellen Files fuer 3d), explizit "n/a" loggen statt skippen.

| Subphase | Was | Skip-Bedingung |
|---|---|---|
| 3a | Changelog-Eintrag draften (wenn user-facing) | nur Doku/Test/Refactor ohne Verhaltensaenderung |
| 3b | Linter + Static Analysis | nie |
| 3c | Diff-scoped Tests | nie |
| 3d | Manueller Testplan | wenn `VISUELL_RELEVANTE_DATEIEN` leer |
| 3e | Audit-Log im Chat anzeigen (Markdown-Block) | nie |
| 3f | **Offene Punkte: User-Entscheid → fixen / Issue / verwerfen** | wenn keine Offenen Punkte |

**3f:** Offene Punkte (nur Entscheidungs-Punkte, siehe Phase 2 Schritt E) werden dem User via AskUserQuestion vorgelegt — pro Punkt: **Jetzt entscheiden + fixen** / **Als Issue vertagen** / **Verwerfen**. Issues entstehen NUR fuer explizit Vertagtes (mit Dedup). Minor-Findings bekommen NIE Issues. Details in `references/post-loop.md` Section 3f.

---

## Phase 4: Pre-Push-Verhalten

**Working-Tree-Exklusivitaet pruefen (vor Marker):**

```bash
# Drift-Check gegen Basis aus Phase 1. Eigene Audit-Fixes zaehlen nicht als
# Drift (sie sind im Status-Hash erwartbar) — verglichen wird HEAD und ob
# Aenderungen auftauchen, die weder Basis noch Fix-Agents zuzuordnen sind.
[ "$(git rev-parse HEAD)" = "$AUDIT_BASE_HEAD" ] || echo "WARN: Fremd-Commit waehrend Audit, Diff-Basis instabil."
```

Bei Abweichung: warnen (`Fremd-Commit/Index-Drift waehrend Audit, Diff-Basis instabil`), Scope via `collect-scope.sh` neu erheben und entscheiden, ob die Findings noch zur Diff-Basis passen. Kein automatischer Abbruch, aber Push nur nach bewusster Bestaetigung der neuen Basis.

**Hard-Block (nie pushen):**
- `SECRET_SCAN_RESULT=FINDINGS` → Push abbrechen, Secrets entfernen + History bereinigen (BFG / `git filter-repo`).
- Unfixbare Critical/Important, Linter-Fehler, Tests rot → `BLOCKED: Push abgebrochen.` + Liste. KEINE Marker-Datei.

**Alles gefixt, Tests gruen:**

**KRITISCH — Marker und Push NIEMALS im selben Bash-Befehl.** Pre-Push-Hook prueft Command-String auf `git push` und blockiert BEVOR der Marker geschrieben wird.

```bash
# Schritt 1 — Marker (kein `git push` im Befehl):
hash=$(echo -n "$PWD" | md5 2>/dev/null || echo -n "$PWD" | md5sum 2>/dev/null | cut -d' ' -f1)
touch "/tmp/claude-audit-passed-$hash"
```

```bash
# Schritt 2 — Push (separater Bash-Aufruf):
git push
# Multi-Repo: git -C /pfad push
```

Marker: TTL 30 Min, wird nicht geloescht (mehrere Hooks pruefen sequenziell). Hash kommt aus `cwd` des Tool-JSON. Multi-Repo: `git -C /pfad push`, niemals `cd /pfad && git push`.

Danach: `Audit passed.` ausgeben, weiter mit Phase 5 + 6.

---

## Phase 5: Learning

**Skip wenn `SKIP_LEARNING=1`** (low effort). Direkt zu Phase 6.

Der Learning-Agent gibt einen **strukturierten Output** zurueck. **Subagents koennen nicht in `.claude/`-Pfade schreiben** (hardcoded Schutz, auch im Foreground und mit bypassPermissions). Der Orchestrator parst den Output und schreibt selbst — `.claude/audits/*.md` und `.claude/audits/suppressions.json` sind in den erlaubten Orchestrator-Edits.

**Schritt 1: Learning-Agent dispatchen**

```
Agent(
  subagent_type: general-purpose,
  prompt: "Lies agents/learning-agent.md und fuehre den Ablauf aus.
    PROJECT_ROOT={PROJECT_ROOT}
    AKTUELLES_LOG={Inhalt des gerade geschriebenen Audit-Logs}
    AUDIT_TYPE=audit",
  mode: bypassPermissions
)
```

Foreground (5-10s, nicht push-blockierend).

**Schritt 2: Output parsen**

Der Agent liefert zwischen `LEARNING_RESULT_START` und `LEARNING_RESULT_END` drei Bloecke: `SUPPRESSIONS_TO_ADD` (JSON-Array), `LEARNING_LOG_ENTRY` (Markdown bis `LEARNING_LOG_ENTRY_END`) und `TRENDS_BLOCK` (Markdown zwischen `TRENDS_BLOCK_START` und `TRENDS_BLOCK_END`). Die Vorschlaege fuer Guideline-/Agent-Aenderungen sind als `- [ ]`-Checkboxes im `Vorgeschlagene Verbesserungen`-Abschnitt des `LEARNING_LOG_ENTRY` enthalten.

**Schritt 3: Orchestrator schreibt**

- `LEARNING_LOG_ENTRY` an `.claude/audits/learning-log.md` anhaengen (oder neu anlegen falls erster Audit)
- `TRENDS_BLOCK` am Anfang der `learning-log.md` einfuegen oder vorhandenen Block ersetzen (nicht anhaengen — soll Top-Snapshot bleiben)
- `SUPPRESSIONS_TO_ADD` in `.claude/audits/suppressions.json` mergen. **Dedup-Regel:** Pattern jeder neuen Suppression durch `bash "$AUDIT_BIN/normalize-suppression.sh"` schicken, gleiche Normalisierung fuer bestehende Suppressions. Wenn beide den gleichen Key produzieren → existierende behalten, neue verwerfen. So werden "[Security] LIKE injection in scope" und "Like-wildcard injection (security)" als gleich erkannt.
- Im Chat anzeigen: Anzahl neuer Suppressions und Anzahl neuer offener Backlog-Punkte. User weiss, dass beim naechsten `/audit` (oder `/full-audit`) gefragt wird.

---

## Phase 6: PR erstellen (nach Push)

```bash
# PreCompact-Marker entfernen — Audit abgeschlossen
CWD_HASH=$(pwd | md5 2>/dev/null || pwd | md5sum 2>/dev/null | cut -d' ' -f1)
rm -f "/tmp/claude-audit-in-progress-${CWD_HASH}"
```

Detail: `references/pr-creation.md`. Kurzfassung: Branch pruefen, Commits sammeln, optional Plan-Doc fuer Description, PR via `gh pr create`, URL ausgeben. Fehler blockieren nicht.
