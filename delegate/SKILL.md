---
name: delegate
description: "Default-Arbeitsmodus fuer Implementierungs-Aufgaben: das teure Session-Modell (Fable/Opus) analysiert den Auftrag, stellt bei echten Mehrdeutigkeiten Rueckfragen, schreibt eine executor-taugliche Mini-Spec und uebergibt die Umsetzung an einen Sonnet-Executor. Danach reviewt das teure Modell das Ergebnis wie ein Tech-Lead (Diff lesen, Kriterien selbst re-runnen) und faellt ein Verdict. Use when the user asks to implement, build, fix, change, or refactor code (auch ohne /delegate zu tippen). NOT for: questions/explanations (direkt antworten), planning discussions or large features needing a written plan (use /plan-it), audits (/audit), pure test writing (test-writer agent)."
when_to_use: "/delegate, implementiere, baue, aendere, fixe, setz das um, refactor this, build this feature"
argument-hint: "[Aufgabe in eigenen Worten; optional --worktree]"
effort: high
allowed-tools:
  - Agent
  - Bash
  - Read
  - Grep
  - Glob
  - TodoWrite
  - AskUserQuestion
  - SendMessage
---

# Delegate: Analyse (teuer) → Umsetzung (Sonnet) → Review (teuer)

**SOFORT AUSFÜHREN — direkt mit Phase 0 beginnen.**

> Frontmatter hat bewusst KEIN `model:`-Feld und KEIN `disable-model-invocation` (beides dokumentierte Ausnahmen der Repo-Konvention): Der Skill erbt das Session-Modell (Fable/Opus), damit Analyse und Review auf dem staerksten verfuegbaren Modell laufen — `model: opus` wuerde eine Fable-Session downgraden. Auto-Trigger auf Implementierungs-Auftraege ist gewollt, das ist der Default-Arbeitsmodus.

Ökonomie dieses Skills: Das teure Modell macht die Arbeit, bei der Intelligenz zählt (verstehen, entscheiden, spezifizieren, reviewen). Sonnet generiert die Code-Masse. **HARTE REGEL: Der Orchestrator editiert NIE selbst Code** — Edit/Write sind bewusst nicht in allowed-tools. Jeder Code-Fix, auch im Review, geht durch den Executor.

## Phase 0: Scope-Gate

Auftrag einordnen, bevor Arbeit passiert:

| Einordnung | Signal | Aktion |
|---|---|---|
| Kein Implementierungs-Auftrag | Frage, Erklaerung, Meinung, Debugging-Diskussion | Skill verlassen, normal antworten |
| Trivial | 1 Datei, < ~10 Zeilen, mechanisch (Typo, Rename, Config-Wert) | Phasen 1-2 skippen, Mini-Spec in 3 Zeilen, direkt Phase 3 |
| Normal | klarer Auftrag, 1-5 Dateien, keine Architektur-Entscheidung | voller Ablauf |
| Gross / architektonisch | neues Datenmodell, > ~5 Dateien, Framing unklar, mehrere valide Ansaetze, Breaking Change | **AskUserQuestion:** "Erst /plan-it (Recommended — Plan + Challenges, dann /plan-it execute)" vs. "Direkt umsetzen via /delegate". Bei plan-it: Skill beenden, /plan-it uebernimmt. |

## Phase 1: Analyse (Orchestrator, teuer)

- Auftrag in ein pruefbares Ziel uebersetzen ("add validation" → "Tests fuer invalide Inputs, dann gruen").
- Gezielter Codebase-Scan: betroffene Dateien lesen, **jeden zu aendernden Identifier repo-weit greppen** (parallele Implementierungen, Wizard-Duplikate — nie annehmen, es gibt nur eine Stelle).
- Konventionen + Exemplar-Datei identifizieren (Komponenten statt Roh-HTML, Error-Pattern, Teststil).
- Verifikations-Kommandos des Repos ermitteln (Test-Runner, Linter, Typecheck) — NICHT raten, aus package.json/composer.json/CI lesen. Nur diff-scoped Tests, nie die volle Suite.
- Annahmen explizit auflisten.

## Phase 2: Rückfragen (nur echte Mehrdeutigkeiten)

Wenn mehrere Interpretationen existieren oder eine Annahme das Ergebnis kippen wuerde: **AskUserQuestion**, jede Frage mit empfohlener Antwort zuerst (Recommended-Muster aus /plan-it). Max 2 Runden. Keine Fragen, deren Antwort im Code steht.

## Phase 3: Mini-Spec schreiben

Inline (keine Datei), executor-tauglich — der Executor kennt diese Session nicht:

```markdown
## Auftrag: {Titel}
**Ziel:** {woran erkennt man Erfolg — messbar}
**Kontext:** {Ist-Zustand mit datei:zeile; Konventionen mit Exemplar: "Error-Handling wie src/lib/result.ts, genau so"}
**Betroffene Dateien:** {abschliessende Liste}
**Out of Scope:** {verwandt aussehende Dateien, die NICHT angefasst werden — mit Grund}
**Schritte:**
1. {konkret, Datei + was} → verify: {Kommando → erwartetes Ergebnis}
2. ...
**Bugfix?** Schritt 1 ist IMMER: Repro-Test schreiben, der rot ist. Fix danach, Test gruen.
**Done-Kriterien (alle):** {Test-Kommando → exit 0 inkl. N neuer Tests; Lint/Typecheck → exit 0; git status: nur Betroffene Dateien}
**STOP-Bedingungen:** {Ist-Zustand weicht ab; verify schlaegt 2x fehl; Fix braeuchte Out-of-Scope-Datei; Kernannahme falsch}
```

## Phase 4: Executor dispatchen (Sonnet)

Standard: direkt im Working Tree (Review passiert vor jedem Commit). Isolierter Worktree (`isolation: worktree`) nur wenn: User `--worktree` sagt, der Working Tree fremde uncommittete Aenderungen enthaelt, oder der Auftrag riskant ist (Migrations, > 5 Dateien).

```
Agent(
  subagent_type: general-purpose,
  model: sonnet,
  prompt: "{Executor-Praeambel + Report-Format aus plan-it/references/execute-review.md, Abschnitt Dispatch}
    {MINI_SPEC inline}"
)
```

Praeambel-Kern (Langform in der Referenz): Schritt fuer Schritt, jedes verify bestaetigen, nur Betroffene Dateien, STOP-Bedingungen respektieren statt improvisieren, jede Report-Behauptung gegen ein echtes Tool-Ergebnis pruefen, Report-Format exakt (`STATUS / STEPS / STOPPED BECAUSE / FILES CHANGED / NOTES`).

Referenz aufloesen (gleiche Kandidaten-Logik wie full-audit → audit):

```bash
for c in "$(dirname "${CLAUDE_SKILL_DIR:-/nonexistent}")/plan-it" "$HOME/.claude/skills/plan-it"; do
  [ -f "$c/references/execute-review.md" ] && { EXEC_REF="$c/references/execute-review.md"; break; }
done
```

## Phase 5: Review (Orchestrator, teuer)

Dem Executor-Report NICHT trauen — selbst pruefen (Checkliste = execute-review.md, Abschnitt Review):

1. `git diff` komplett lesen; gegen Ziel + Konventionen judgen (liest es sich wie der Rest des Repos?).
2. Jedes Done-Kriterium selbst re-runnen (Bash).
3. Scope: `git diff --stat` gegen Betroffene-Dateien-Liste. Datei ausserhalb = Fail.
4. Neue Tests LESEN: asserted der Test etwas Sinnvolles oder gamed er das Kriterium?
5. Dokumentierte Abweichung in NOTES nach Merit beurteilen; undokumentierte Abweichung = Fail.

**Verdict:**

| Verdict | Aktion |
|---|---|
| APPROVE | Ergebnis-Report an User (unten). Kein Commit — Committen bleibt beim User (oder /ship). |
| REVISE | SendMessage an DENSELBEN Executor mit konkretem Befund ("Kriterium 3 rot: X; api.ts:90 schluckt den Fehler — Result-Pattern laut Spec"). Max 2 Runden, dann BLOCK. |
| BLOCK | Aenderungen im Working Tree: `git checkout` der betroffenen Dateien nach User-Rueckfrage, oder stehen lassen + Befund. Befund + korrigierte Spec an User. |

## Phase 6: Ergebnis-Report

```
Delegate abgeschlossen: {Titel}
Verdict: APPROVE ({N} Revisions-Runden)
Geaendert: {Dateien mit 1-Zeilen-Was}
Verifiziert: {Kommando → Ergebnis, pro Done-Kriterium}
NOTES des Executors: {falls relevant}
Offen: {nichts | bewusst Vertagtes mit Grund}
```

Tests rot oder Kriterium nicht erfuellbar: ehrlich sagen, nie schoenreden. Danach normale Regeln: Commit nur auf expliziten Auftrag, /audit vor Push.
