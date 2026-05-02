---
name: audit
description: "Pre-push code audit. Triage routes the diff to relevant subagents (architecture, security, performance, code quality, SEO, a11y, typography, UI, UX, animation), runs secret/lockfile pre-checks, auto-fixes via parallel fix-agents, loops until clean, generates a manual test plan, then allows git push. Use when the user runs /audit, says 'before pushing' or 'review my changes', or has uncommitted/unpushed changes that should be checked. NOT for whole-codebase audits — use /full-audit instead."
when_to_use: "/audit, before pushing, git push, pre-push review, review my changes, audit uncommitted changes, check before pushing"
argument-hint: "[optional: scope hint]"
model: claude-opus-4-7
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

**SOFORT AUSFÜHREN — nicht erklären, nicht ankündigen. Direkt mit Phase 1 beginnen.**

Anti-Patterns / häufige Fehler im Loop: `references/anti-patterns.md`.

## Phase 1: Pre-Flight & Scope

```bash
AUDIT_BIN="${CLAUDE_PROJECT_DIR:-$HOME/.claude/skills/audit}/bin"
AUDIT_AGENTS_DIR="${CLAUDE_PROJECT_DIR:-$HOME/.claude/skills/audit}/agents"

bash "$AUDIT_BIN/verify-agents.sh" "$AUDIT_AGENTS_DIR" || { echo "Audit abgebrochen — fehlende Agent-Dateien."; exit 1; }
bash "$AUDIT_BIN/collect-scope.sh"
bash "$AUDIT_BIN/detect-framework.sh"
bash "$AUDIT_BIN/pre-checks.sh"
bash "$AUDIT_BIN/diff-size-gate.sh"
```

Detail-Auswertung der Script-Outputs in `references/scope-and-pre-checks.md`:
- Diff-Size-Gate-Tabelle (OK/LARGE/HUGE)
- Pre-Check-Auswertung (Secrets, Lockfile, Binary-Artefakte)
- Variable-Ableitung (ALLE_DATEIEN, FRONTEND_DATEIEN, UNIFIED_DIFF, SUPPRESSIONS, PROJECT_CONTEXT)
- Audit-Context-Check (PFLICHT bei fehlendem Context)

Übergib `PROJECT_CONTEXT`, `FRAMEWORK` und `SOURCE_DIRS` an alle Subagents. Den `UNIFIED_DIFF` bekommt nur der **Triage-Agent** zur Hotspot-Bestimmung — Workers bekommen statt des Diffs nur die ihnen zugeordneten Hotspots (siehe Phase 2 Schritt C).

---

## Phase 2: Audit-Loop

Maximal **2 Runden**. Convergence-Check: Wenn `Critical + Important` der aktuellen Runde NICHT sinkt UND `RUNDE >= 2`, Loop abbrechen mit `NO_CONVERGENCE`.

Initialisiere: `RUNDE = 1`, `BEREITS_GEFIXT = []`, `FINDINGS_VORHERIGE_RUNDE = null`.

### Prozedur AUDIT_RUNDE

**Schritt A — Ankündigung + Todos**

Ausgabe: `Audit-Runde {RUNDE}/2`. TodoWrite: `Subagents dispatchen` (in_progress), `Findings fixen` (pending).

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

**Schritt C — Spezial-Subagents parallel dispatchen**

Nur Agents mit `relevance.{dimension}.run == true` aus dem Triage. Security fast immer. Alle nicht-geskippten Agents in JEDER Runde.

Dispatche in **einem Message-Block** via Agent-Tool. Uebergib NUR:
- `TRIAGE_SUMMARY` (1-2 Zeilen)
- `HOTSPOTS` (markierte Stellen, exakte Datei:Zeile)
- `DATEILISTE` (zur Orientierung)

**KEIN UNIFIED_DIFF.** Workers lesen Code via Read-Tool wenn noetig (max 5 Files pro Agent pro Runde).

**Model-Override bei Escalation:** Wenn `HEAVY_REASONING_OVERRIDE=claude-opus-4-7` aus Phase 1 gesetzt ist (LARGE-Diff), Agent 1 (Architektur) und Agent 2 (Security) explizit auf Opus dispatchen. Andere Agents nutzen ihr `agents/*.md` Default.

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

Prompt-Template: `agents/prompt-template.md`, Abschnitt "Fuer /audit (Diff-basiert)".

**Schritt D — Konsolidieren + Deduplizieren**

Gleiche Stelle von mehreren Subagents → ein Finding, strengste Einstufung gewinnt.

Pruefe SELBST (nur Runde 1):
- Documentation: README.md / CLAUDE.md Update noetig?
- Oeffentliche Seiten / Changelog
- Tests: geaenderte Logik ohne Tests?
- Mobile Apps: `bash bin/detect-mobile.sh` → bei Treffer Impact aus `references/mobile-impact.md`

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

**Sonst — Confidence-Gate:**
- High → direkt fixen
- Medium → fixen mit Hinweis `(medium confidence)`
- Low → NICHT auto-fixen, als Offener Punkt

**HARTE REGEL: Orchestrator editiert NIEMALS Code-Dateien selbst.** Jeder Code-Fix geht via Fix-Agent (Haiku). Edits vom Orchestrator kosten ~5x so viel.

**Erlaubte Orchestrator-Edits:** `.claude/audits/*.md`, `CLAUDE.md` Audit-Context-Entwurf, `suppressions.json` (mit User-Zustimmung), Changelog-Dateien.

1. Findings nach Datei gruppieren
2. Pro Datei einen `fix-agent.md`-Subagent (Haiku) parallel dispatchen
3. Mehrere Findings in derselben Datei: in einem Fix-Agent-Call bundeln
4. Ergebnisse einsammeln: `FIX_RESULT=APPLIED` zaehlt als gefixt
5. Minor: nur fixen wenn high confidence, sonst skippen
6. Nicht fixbar: als Offener Punkt mit Begruendung; `patterns-store.sh dismissed {pattern}` aufrufen
7. Gefixte Issues zu `BEREITS_GEFIXT` adden, via `patterns-store.sh add` ins Learning-Store

**PFLICHT — Status-Zeile am Ende jeder Runde:**

```
AUDIT_STATUS: SAUBER | RUNDE {RUNDE}/2
AUDIT_STATUS: FIXES_APPLIED | RUNDE {RUNDE}/2
AUDIT_STATUS: NO_CONVERGENCE | RUNDE {RUNDE}/2
```

### Nach jeder Runde

| Ergebnis | Aktion |
|---|---|
| `SAUBER` | Loop beendet → Phase 3 |
| `FIXES_APPLIED` + RUNDE < 2 | `RUNDE += 1`, Prozedur erneut. Kein User-Wait. |
| `FIXES_APPLIED` + RUNDE = 2 | Loop beendet. Verbleibende Issues auflisten. |
| `NO_CONVERGENCE` | Loop beendet. Warnung. |

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
| 3f | **Offene Punkte + Minor als GitHub-Issues anlegen** | nur wenn `gh repo view` failt oder kein github-Remote |

**3f ist HARTE PFLICHT bei GitHub-Repos.** Jeder Eintrag unter `## Offene Punkte` UND jedes verifizierte Minor-Finding bekommt ein Issue (mit Dedup). Format und Bash siehe `references/post-loop.md` Section 3f.

Wenn 3f geskippt wird (kein gh / kein github), das explizit ausgeben: `WARN: 3f uebersprungen, weil <grund>`.

---

## Phase 4: Pre-Push-Verhalten

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

Foreground (5-10s, nicht push-blockierend). Background-Subagents koennen `.claude/`-Dateien nicht schreiben (Hardcoded Schutz). Vorschlaege gehen in `learning-log.md`.

---

## Phase 6: PR erstellen (nach Push)

Detail: `references/pr-creation.md`. Kurzfassung: Branch pruefen, Commits sammeln, optional Plan-Doc fuer Description, PR via `gh pr create`, URL ausgeben. Fehler blockieren nicht.
