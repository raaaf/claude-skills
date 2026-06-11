# Plan + Log Templates

Templates fuer Phase 2 (Plan-Datei) und Phase 4 (Plan-Log).

## Plan-Format (Phase 2)

Datei: `docs/plans/{YYYY-MM-DD}-{slug}.md`

```markdown
# {Titel}

## Problem
{Was ist das Problem — in 1-3 Saetzen. Das PROBLEM, nicht die Loesung.}

## Ziel
{Woran erkennt man dass es geloest ist? Messbar wenn moeglich.}

## Nicht-Ziele
{Was ist explizit NICHT Teil davon.}

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

## Edge Cases
- {Case}: {Handling}

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
