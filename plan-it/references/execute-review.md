# Execute & Reconcile (Phase 5 Detail)

Follow-through fuer geschriebene Plaene. Grundregel bleibt: Der Orchestrator editiert nie selbst Produktiv-Code — der Executor arbeitet in seinem Arbeitsbereich, der Orchestrator reviewt und faellt ein Verdict, wie ein Tech-Lead, der nicht selbst auf den Branch pusht. Konzept nach shadcn/improve (closing-the-loop), an unsere Skill-Konventionen angepasst.

**Zwei Aufrufer, zwei Arbeitsbereiche:** `/plan-it execute` dispatcht IMMER in einen isolierten Worktree (`{WORKDIR}` = Worktree-Pfad, Executor committet dort). `/delegate` dispatcht per Default in den Working Tree (`{WORKDIR}` = Repo-Root, Executor committet NICHT — Review passiert vor jedem Commit; Worktree nur bei `--worktree`/Risiko, dann wie plan-it). Die mit `{WORKDIR}`/`{COMMIT_REGEL}` markierten Stellen unten entsprechend einsetzen.

## `/plan-it execute <plan-datei>` — Executor dispatchen + reviewen

### Vorbedingungen (alle pruefen, sonst stoppen und sagen warum)

1. Repo ist ein git-Repository (Worktree-Isolation braucht das).
2. Die Plan-Datei existiert unter `docs/plans/`.
3. Drift-Check selbst laufen lassen: `git diff --stat {PLANNED_AT_SHA}..HEAD -- {betroffene Dateien}`. Bei Drift: erst den Plan aktualisieren (Ist-Zustand + SHA refreshen), keinen stalen Plan an einen Executor geben.

### Dispatch

EINEN Executor-Subagent starten: `subagent_type: general-purpose`, `isolation: worktree`, Modell `sonnet` (oder was der User nennt: `/plan-it execute {plan} haiku`).

Der Prompt MUSS enthalten:

1. **Den kompletten Plan-Text/Spec inline.** Ein Worktree enthaelt nur committete Dateien — ein uncommitteter Plan ist dort nicht lesbar. Nie annehmen, immer inlinen (gilt fuer beide Aufrufer).
2. Die Executor-Praeambel:

> Du bist der Executor fuer den folgenden Plan. Folge ihm Schritt fuer Schritt.
> Fuehre jedes verify-Kriterium aus und bestaetige das erwartete Ergebnis,
> bevor du weitermachst. Fasse nur die Betroffene-Dateien-Liste an. Tritt eine
> STOP-Bedingung ein: sofort stoppen und berichten, nicht improvisieren.
> {COMMIT_REGEL: Worktree -> "Committe deine Arbeit im Worktree (Conventional
> Commits)." | Working Tree (/delegate-Default) -> "Committe NICHT — die
> Aenderungen bleiben uncommitted, das Review kommt vor jedem Commit."}
> Pruefe vor dem Report jede Behauptung gegen ein echtes Tool-Ergebnis dieser
> Session — fehlgeschlagene oder uebersprungene Verifikationen klar benennen.
> Antworte exakt im Report-Format.

3. Das Report-Format:

```
STATUS: COMPLETE | STOPPED
STEPS: pro Schritt — done/skipped + verify-Ergebnis
STOPPED BECAUSE: (nur bei STOPPED) welche STOP-Bedingung, was beobachtet
FILES CHANGED: Liste
NOTES: Abweichungen, Ueberraschungen, Judgment-Calls
```

Hinweis frische Worktrees (entfaellt im Working-Tree-Fall): git-History ja, `node_modules`/Build-Artefakte nein — der Executor muss zuerst Dependencies installieren. Das ist erwartbar, keine Abweichung.

### Review (die eigentliche Orchestrator-Arbeit)

Dem Executor-Report NICHT trauen — selbst pruefen (alle Kommandos in `{WORKDIR}`; im Working-Tree-Fall ist das das Repo-Root ohne `-C`):

1. **Jedes Done-Kriterium in `{WORKDIR}` re-runnen.**
2. **Scope-Compliance:** `git -C {WORKDIR} diff --stat` gegen die Betroffene-Dateien-Liste. Jede Datei ausserhalb = Review-Fail.
3. **Kompletten Diff lesen** und gegen "Problem"/"Ziel" des Plans und die Konventionen-Sektion judgen.
4. **Neue Tests lesen:** Ein Test, der nichts Sinnvolles asserted, besteht `npm test` und beweist nichts — Executors gamen Kriterien.

**Dokumentierte Abweichungen nach Merit beurteilen, nicht reflexhaft blocken.** "Nicht improvisieren" verhindert stilles Driften; ein Executor, der ein echtes Hindernis minimal umschifft und es in NOTES erklaert, hat richtig gehandelt — approven, wenn es dem Plan-Ziel dient und im Scope bleibt. UNDOKUMENTIERTE Abweichungen sind Review-Fails.

### Verdict

| Verdict | Wann | Aktion |
|---|---|---|
| APPROVE | Kriterien gruen, Scope sauber, Qualitaet passt | User praesentieren: Diff-Zusammenfassung, Arbeitsbereich (Worktree-Pfad + Branch bzw. Working-Tree-Status), NOTES. **Mergen/Committen ist User-Entscheidung — nie selbst mergen/pushen/committen.** |
| REVISE | Behebbare Luecken | SendMessage an denselben Executor mit konkretem, umsetzbarem Feedback. Max 2 Revisions-Runden, dann BLOCK. |
| BLOCK | STOP-Bedingung, Scope-Verletzung, Revisionen erschoepft | Plan mit dem Gelernten ueberarbeiten; User berichten, was passiert ist und was sich am Plan geaendert hat. |

Verifikations-Kommandos in `{WORKDIR}` sind erlaubt — im Worktree sowieso (isoliert, wegwerfbar); im Working-Tree-Fall nur lesende/fluechtige Kommandos (Tests, Lint), nichts was Artefakte ausserhalb ignorierter Verzeichnisse schreibt.

## `/plan-it reconcile` — Plan-Bestand pflegen

Verarbeitet, was seit der letzten Session passiert ist. `docs/plans/*.md` lesen (plus `.claude/plans/logs/` fuer Kontext), pro Plan:

- **Umgesetzt** (Done-Kriterien halten auf aktuellem HEAD, stichprobenartig die billigen): im Plan als umgesetzt markieren. Plan-Dateien nie loeschen — sie sind das Protokoll.
- **Gedriftet** (Drift-Check schlaegt an): pruefen, ob das Problem ueberhaupt noch existiert (evtl. nebenbei gefixt). Existiert es: Ist-Zustand-Abschnitte + Planned-at-SHA refreshen. Existiert es nicht: als erledigt/hinfaellig markieren mit 1-Zeilen-Begruendung.
- **Blockiert/liegengeblieben:** Hindernis im Code untersuchen; Plan drumherum umschreiben oder mit Begruendung verwerfen.

Abschlussreport: was verifiziert umgesetzt ist, was refresht wurde, was verworfen, was JETZT ausfuehrbar ist.
