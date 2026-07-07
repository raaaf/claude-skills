# Plan + Log Templates

Templates fuer Phase 2 (Plan-Datei) und Phase 4 (Plan-Log).

Inhalt: Plan-Format (executor-grade, mit Drift-Check/STOP/Done-Kriterien) · Plan-Log-Format · Runden-Heuristik

## Plan-Format (Phase 2)

Datei: `docs/plans/{YYYY-MM-DD}-{slug}.md`

**Executor-Regel:** Der Plan wird fuer einen Executor OHNE Session-Kontext geschrieben (anderes Modell, andere Session, oder ein Mensch). Alles Noetige steht in der Datei: exakte Pfade, Ist-Zustand, Konventionen mit Exemplar-Datei, Befehle. "Wie besprochen" ist ein Bruch.

```markdown
# {Titel}

> **Executor-Anweisung:** Schritt fuer Schritt folgen, jedes verify-Kriterium
> pruefen bevor es weitergeht. Tritt eine STOP-Bedingung ein: stoppen und
> berichten, nicht improvisieren.
>
> **Drift-Check (zuerst):** `git diff --stat {PLANNED_AT_SHA}..HEAD -- {in-scope Pfade}`
> Hat sich eine In-Scope-Datei seit Plan-Erstellung geaendert: Ist-Zustand
> gegen den Live-Code abgleichen; bei Abweichung ist das eine STOP-Bedingung.

## Meta
- Planned at: commit `{git rev-parse --short HEAD}`, {DATUM}

## Problem
{Was ist das Problem — in 1-3 Saetzen. Das PROBLEM, nicht die Loesung.}

## Ziel
{Woran erkennt man dass es geloest ist? Messbar wenn moeglich.}

## Nicht-Ziele
{Was ist explizit NICHT Teil davon.}

## Out of Scope (Dateien)
{Dateien/Bereiche, die verwandt aussehen, aber NICHT angefasst werden duerfen — mit 1-Satz-Grund (z.B. "legacy-api.ts: deprecated, v1-Clients haengen dran").}

## Loesung

### Ansatz
{Beschreibung des Loesungswegs — warum dieser Weg und nicht ein anderer.}

### Schritte
1. {Konkret — welche Datei, welche Komponente, was aendert sich} → verify: {pruefbares Kriterium, z.B. "Test X gruen", "Route Y liefert 200", "Grep nach Z leer"}
2. ... → verify: ...

Jeder Schritt bekommt ein verify-Kriterium. Ein Schritt ohne pruefbares Ergebnis ist kein Schritt, sondern eine Absicht.

### Aufwand
{Grobe Einschaetzung: S (<0,5 Tag) / M (0,5-2 Tage) / L (3-5 Tage) / XL (>1 Woche) — plus der groesste Einzelposten in 1 Satz.}

### Betroffene Dateien
- `pfad/zur/datei` — {was sich aendert}

### Konventionen
{Welche Repo-Patterns gelten, mit einer Exemplar-Datei: "Error-Handling folgt dem Result-Pattern — siehe src/lib/result.ts und dessen Nutzung in src/users/api.ts:40-60. Genau so."}

## Edge Cases
- {Case}: {Handling}

## Done-Kriterien
Maschinell pruefbar, ALLE muessen gelten — Befehle mit erwartetem Ergebnis, keine Prosa wie "funktioniert korrekt":
- [ ] `{test-befehl}` → exit 0, inkl. {N} neuer Tests
- [ ] `{lint/typecheck-befehl}` → exit 0
- [ ] `grep -rn "{altes_pattern}" src/` → keine Treffer
- [ ] Keine Dateien ausserhalb der Betroffene-Dateien-Liste geaendert (`git status`)

## STOP-Bedingungen
Stoppen und berichten (nicht improvisieren) wenn:
- Der Ist-Zustand an den genannten Stellen nicht den Beschreibungen entspricht (Codebase ist gedriftet).
- Ein verify-Kriterium nach einem ernsthaften Fix-Versuch zweimal fehlschlaegt.
- Der Fix eine Out-of-Scope-Datei anfassen muesste.
- {plan-spezifische Kernannahme} sich als falsch herausstellt.

## Maintenance-Notizen
{Was kuenftige Aenderungen mit diesem Code zu tun haben werden; was ein Reviewer im PR pruefen sollte; explizit Vertagtes mit Grund.}

## Offene Fragen
- {Falls noch welche — sonst weglassen}
```

**Optionale Abschnitte** (nur wenn sie Wert bringen):
- Datenfluss-Diagramm (ASCII oder Mermaid)
- Migrationsstrategie
- Rollback-Plan

## Plan-Log-Format (Phase 4)

Datei: `.claude/plans/logs/{YYYY-MM-DD}-{slug}.md`

```markdown
# Plan-Log — {Titel}

## Meta
- Datum: {DATUM}
- Runden Phase 1 (Verstehen): {N}
- Plan-Datei: docs/plans/{datum}-{slug}.md

## Fragen & Antworten
- {Frage} → {User-Antwort oder "Einschaetzung bestaetigt"}

## Challenge-Ergebnis
- Concerns gesamt: {N}
- Eingearbeitet: {X}
- Akzeptiert: {Y}
- Abgelehnt: {Z}

## Bemerkenswert
- {Pattern oder Ueberraschung, z.B. "User hat alle Design-Concerns abgelehnt"}
```

## Runden-Heuristik (Empfehlung, kein Hard-Limit)

| Komplexitaet | Runden | Wann |
|---|---|---|
| Einfach | 2 | Klare Anforderung, isoliertes Feature, kein Datenmodell-Umbau |
| Mittel | 3 | Datenmodell-Umbau, Multi-Channel-Feature, komplexe Policy-Frage |
| Hoch | 4+ | Framing-Klaerung notwendig, initialer Pivot (z.B. "Sollen wir X?" → eigentlich Y) |

Belegt durch Learning-Log (8 Plaene, Ø 2,86 Runden): Plan 1 (2 Runden, einfach), Plan 7 (4 Runden, Pivot). Bei Datenmodell-Umbauten lohnt der dritte Durchgang fast immer.
