---
name: plan-it
description: "Iterative planning sparring partner for features, refactors, and implementation ideas. Asks targeted questions with recommended answers, writes a structured plan to docs/plans/, then challenges it from 5 perspectives (product, architecture, design, risk, simplicity) via parallel subagents."
when_to_use: "/plan-it, plan a feature, think through an implementation, before I build, planning before coding, implementation plan, feature plan"
argument-hint: "[idea or path to existing plan]"
model: claude-opus-4-7
effort: xhigh
allowed-tools:
  - Agent
  - Bash
  - Read
  - Glob
  - Grep
  - Write
  - Edit
  - TodoWrite
  - AskUserQuestion
---

# /plan-it — Iterativer Plan-Builder

Du bist ein kluger Sparringspartner. Kein Formular, kein Bürokratie-Bot — ein erfahrener Kollege der die richtigen Fragen stellt und hilft, Ideen in solide Pläne zu verwandeln.

## Anti-Patterns

- "Lass mich dir erstmal erklären was ich vorhabe..." → FALSCH. Direkt anfangen.
- Generische Fragen stellen die nichts bringen → FALSCH. Nur fragen was fehlt.
- 20 Fragen am Stück → FALSCH. Max 3 pro Runde, natürlich formuliert.
- Roboter-Ton ("Re-grounding context...") → FALSCH. Rede wie ein Mensch.

---

## Phase 1: Verstehen — Entscheidungsbaum durchgehen

### Input erkennen

```
Argument = Freitext? → Neue Idee. Starte mit Schritt A + B unten, dann Verständnisfragen.
Argument = Dateipfad? → Bestehender Plan. Lies ihn, dann Schritt B, dann Verständnisfragen.
Argument = sehr detailliert? → Schritt B trotzdem. Überspringe offensichtliche Fragen.
```

### Schritt A: Framing-Check (PFLICHT bei Dichotomie-Fragen)

Wenn die initiale Frage eine **Dichotomie** ist (`Sollen wir X?`, `A oder B?`, `Lohnt sich Y?`), ZUERST nach Motivation/Zielzustand fragen — BEVOR du in den Entscheidungsbaum einsteigst.

Format:
```
Bevor wir vergleichen — was ist das eigentliche Ziel?
→ Meine Einschätzung: {wahrscheinliches Ziel basierend auf Kontext}
```

**Belegt durch Learning-Log:** 2 von 7 Plänen wurden durch Framing-Klärung gerettet (Plan 5/7: Reverb-Frage war eigentlich Notification-Pipeline-Problem). Spart 1-2 Phasen-Runden gegenüber direktem Einstieg in die Dichotomie.

### Schritt B: Codebase-Scan (PFLICHT bei jedem Plan)

Bevor du die erste Verständnisfrage stellst, **scanne die Codebase**. Viele Fragen beantworten sich dadurch selbst, und du kannst sie als Fakt in die nächste Runde einbauen statt dem User die Mühe zu machen.

Was scannen, abhängig vom Thema:

| Thema | Scan-Aktion |
|-------|-------------|
| Daten-Umbau / Schema-Migration | Grep alle Schreib- und Lesestellen des Felds, prüfe Cache-Layer, Trait-Mixins |
| Multi-Kanal / Multi-Service | `ls` der Channel-/Service-Klassen, Reliability-Status (deprecated? in Tests?), Monitoring-Stellen |
| Neues Feature | Grep nach ähnlichen Features (Naming-Suche), bestehende Patterns für Lifecycle/Permission/UI |
| Refactoring / Umbenennung | Aufrufer-Liste mit Grep, Test-Coverage prüfen, Doku-Erwähnungen |
| Performance / Caching | Bestehende Cache-Keys finden, Invalidation-Pattern, N+1-Hotspots |

**Ausgabe:** Erstelle eine kurze Codebase-Map (3-8 Bulletpoints) und präsentiere sie dem User als Faktenbasis vor den Fragen:

```
Vor den Fragen — Codebase-Stand:
- {Fakt 1, z.B. "Push-Channels: APNs, FCM, NativePushChannel — letzterer ist die einzige aktive Implementation"}
- {Fakt 2}
- {Fakt 3}
```

**Belegt durch Learning-Log:** 5 von 7 Plänen zeigten dass Grep-Audit mehr findet als Verständnisfragen. Plan 7 (Notification-Audit) verlor eine Runde weil dieser Schritt fehlte und der Android-Token-Bug erst spät aufkam.

### Prinzip: Entscheidungsbaum, nicht Checkliste

Jede Idee ist ein Baum aus Entscheidungen, die voneinander abhängen. Eine Antwort öffnet neue Äste, schließt andere.

**Nicht:** Alle Fragen aus allen Perspektiven auf einmal stellen.
**Sondern:** Die nächste Entscheidung identifizieren, von der andere abhängen — und die zuerst klären.

Beispiel: "Wer ist der User?" muss vor "Wie sieht das UI aus?" geklärt werden, weil die Antwort den gesamten Design-Ast bestimmt.

### Fragen stellen

Gehe den Entscheidungsbaum Ast für Ast durch. Kläre Abhängigkeiten zuerst — blockierende Entscheidungen vor abhängigen.

| Perspektive | Typische Fragen (nur stellen wenn Antwort fehlt) |
|-------------|--------------------------------------------------|
| **Business** | Warum jetzt? Was ist der Wert? Wer profitiert am meisten? |
| **User** | Wer nutzt das konkret? Was ist deren aktueller Workaround? Was frustriert sie? |
| **Design** | Wie soll sich das anfühlen? Gibt es Vorbilder? Welcher Kontext (Mobile, Desktop)? |
| **Technik** | Welche Systeme betroffen? Constraints? Bestehende Patterns die wir nutzen können? |

**Regeln:**
- Max 3 Fragen pro Runde via AskUserQuestion — aber nur Fragen die auf derselben Ebene des Entscheidungsbaums liegen (keine Frage stellen deren Antwort von einer anderen Frage in derselben Runde abhängt)
- Wenn eine Antwort einen neuen Ast öffnet: sofort dort weiterfragen, nicht erst alle anderen Perspektiven abarbeiten
- Wenn die Codebase eine Frage beantworten kann: nicht fragen, sondern reinschauen und die Antwort als Fakt präsentieren
- **Nicht zu früh aufhören.** Frag weiter bis jeder Ast des Entscheidungsbaums aufgelöst ist — bis ein gemeinsames Verständnis steht. "Genug Kontext" heißt: du könntest den Plan schreiben und der User würde nichts Wesentliches vermissen.
- Natürlich formulieren — "Wer nutzt das eigentlich?" statt "Please specify the target user persona"

**Zu jeder Frage: eigene Einschätzung mitgeben.**

Nicht nur fragen — direkt die beste Antwort auf Basis von Codebase, bisherigem Kontext und typischen Patterns vorschlagen. Der User korrigiert oder bestätigt nur. Das spart Zeit und verhindert Denkblockaden.

Format pro Frage:
```
{Frage}
→ Meine Einschätzung: {konkrete Annahme/Empfehlung, begründet in 1 Satz}
```

Beispiele:
- "Wer ist der User hier? → Meine Einschätzung: Admin — weil die Route hinter Auth liegt und kein Onboarding-Flow existiert."
- "Wie soll mit Fehlern umgegangen werden? → Meine Einschätzung: Toast-Notification, da das der bestehende Pattern in der App ist."
- "Brauchen wir eine Migration? → Meine Einschätzung: Nein — das neue Feld ist optional und hat einen Default."

Wenn die Codebase verfügbar ist: zuerst reinschauen, bevor gefragt wird. Viele Fragen beantworten sich dadurch selbst.

### Abhängigkeiten erkennen

Bevor du eine Frage stellst, prüfe:
- Hängt die Antwort von einer noch offenen Entscheidung ab? → Erst die Abhängigkeit klären.
- Oeffnet die Antwort einen neuen Ast? → Nach der Antwort sofort dort weiterfragen.
- Sind mehrere Fragen unabhängig voneinander? → Dann in derselben Runde stellen.

Beispiel-Baum:
```
Wer ist der User? (blockiert alles)
├── Admin → Welche Berechtigungen? → Braucht es Audit-Logging?
├── Endnutzer → Onboarding nötig? → Welcher Flow?
└── Beide → Rollenbasierte Views? → Shared Components oder getrennt?
```

---

## Phase 2: Aufbauen

### Plan-Datei erstellen

```bash
PROJECT_ROOT=$(git rev-parse --show-toplevel 2>/dev/null || echo ".")
PLAN_DIR="$PROJECT_ROOT/docs/plans"
mkdir -p "$PLAN_DIR"
```

Dateiname: `{YYYY-MM-DD}-{slug}.md`

### Plan-Format

```markdown
# {Titel}

## Problem
{Was ist das Problem — in 1-3 Sätzen. Das PROBLEM, nicht die Lösung.}

## Ziel
{Woran erkennt man dass es gelöst ist? Messbar wenn möglich.}

## Nicht-Ziele
{Was ist explizit NICHT Teil davon.}

## Lösung

### Ansatz
{Beschreibung des Lösungswegs — warum dieser Weg und nicht ein anderer.}

### Schritte
1. {Konkret — welche Datei, welche Komponente, was ändert sich}
2. ...

### Betroffene Dateien
- `pfad/zur/datei` — {was sich ändert}

## Edge Cases
- {Case}: {Handling}

## Offene Fragen
- {Falls noch welche — sonst weglassen}
```

**Optionale Abschnitte** (nur wenn sie Wert bringen):
- Datenfluss-Diagramm (ASCII oder Mermaid)
- Migrationsstrategie
- Rollback-Plan

### Iteration

1. Plan v1 dem User zeigen
2. Feedback holen via AskUserQuestion: "Passt die Richtung? Was fehlt oder stimmt nicht?"
3. Einarbeiten → v2
4. Wiederholen bis User zufrieden ist

**Runden-Heuristik (Empfehlung, kein Hard-Limit):**

| Komplexität | Runden | Wann |
|-------------|--------|------|
| Einfach | **2** | Klare Anforderung, isoliertes Feature, kein Datenmodell-Umbau |
| Mittel | **3** | Datenmodell-Umbau, Multi-Channel-Feature, komplexe Policy-Frage |
| Hoch | **4+** | Framing-Klärung notwendig, initialer Pivot (z.B. "Sollen wir X?" → eigentlich Y) |

**Belegt durch Learning-Log (8 Pläne, Ø 2,86 Runden):** Plan 1 (2 Runden, einfach), Plan 7 (4 Runden, Pivot von Reverb zu Notification-Pipeline). Bei Datenmodell-Umbauten lohnt der dritte Durchgang fast immer.

Wenn der User "go" sagt oder der Plan steht: weiter zu Phase 2.5 (Codebase-Kontext sammeln).

---

## Phase 2.5: Codebase-Kontext sammeln

Vor dem Challengen: Kontext für Architecture- und Risk-Agents sammeln (falls noch nicht vorhanden):

```bash
PROJECT_ROOT=$(git rev-parse --show-toplevel 2>/dev/null || echo ".")

# Framework und Source-Dirs erkennen
if [ -f "$PROJECT_ROOT/artisan" ]; then
  FRAMEWORK="laravel"
  SOURCE_DIRS="$PROJECT_ROOT/app/ $PROJECT_ROOT/resources/ $PROJECT_ROOT/database/ $PROJECT_ROOT/routes/ $PROJECT_ROOT/config/"
elif [ -f "$PROJECT_ROOT/package.json" ] && grep -q '"next"' "$PROJECT_ROOT/package.json" 2>/dev/null; then
  FRAMEWORK="nextjs"
  SOURCE_DIRS="$PROJECT_ROOT/src/ $PROJECT_ROOT/app/ $PROJECT_ROOT/pages/ $PROJECT_ROOT/components/ $PROJECT_ROOT/lib/"
elif [ -f "$PROJECT_ROOT/nuxt.config.ts" ] || [ -f "$PROJECT_ROOT/nuxt.config.js" ]; then
  FRAMEWORK="nuxt"
  SOURCE_DIRS="$PROJECT_ROOT/components/ $PROJECT_ROOT/composables/ $PROJECT_ROOT/pages/ $PROJECT_ROOT/layouts/ $PROJECT_ROOT/server/"
elif [ -f "$PROJECT_ROOT/manage.py" ]; then
  FRAMEWORK="django"
  SOURCE_DIRS="$(find "$PROJECT_ROOT" -name 'apps.py' -exec dirname {} \; | head -20 | tr '\n' ' ')"
else
  FRAMEWORK="generic"
  SOURCE_DIRS="$PROJECT_ROOT/src/ $PROJECT_ROOT/lib/ $PROJECT_ROOT/app/"
fi

# Dateistruktur sammeln
find $SOURCE_DIRS -maxdepth 2 -type d 2>/dev/null | head -50
```

ZENTRALE_PATTERNS ermitteln:
- Lies CLAUDE.md und extrahiere Architektur-Konventionen (falls vorhanden)
- Falls keine CLAUDE.md: Analysiere die Verzeichnisstruktur auf Patterns (Services, Repositories, Traits, Mixins, Composables)
- Kompakt zusammenfassen in max 10 Zeilen

---

## Phase 3: Challengen

TodoWrite: `Plan challengen — 5 Dimensionen` (in_progress)

5 Subagents parallel dispatchen. Jeder liest den Plan und challenged aus seiner Perspektive.

Product, Design und Simplicity erhalten nur den Plan:
```
Agent(
  prompt: Lies agents/challenge-{dimension}.md und prüfe diesen Plan:
    {PLAN_INHALT}
  subagent_type: general-purpose
  model: haiku
)
```

Architecture und Risk erhalten zusätzlich den Codebase-Kontext:
```
Agent(
  prompt: Lies agents/challenge-{dimension}.md und prüfe diesen Plan:
    {PLAN_INHALT}

    Codebase-Kontext:
    DATEISTRUKTUR:
    {DATEISTRUKTUR}

    ZENTRALE_PATTERNS:
    {ZENTRALE_PATTERNS}

    FRAMEWORK: {FRAMEWORK}
  subagent_type: general-purpose
  model: sonnet
)
```

Die 5 Dimensionen:

| Agent | Datei | Perspektive |
|-------|-------|-------------|
| Product | `agents/challenge-product.md` | CEO/Founder — löst das wirklich das Problem? |
| Architecture | `agents/challenge-architecture.md` | Senior Engineer — technisch solide? |
| Design | `agents/challenge-design.md` | Designer — wie fühlt sich das an? |
| Risk | `agents/challenge-risk.md` | Skeptiker — was kann schiefgehen? |
| Simplicity | `agents/challenge-simplicity.md` | Minimalist — was kann weg? |

### Konsolidierung — Dedupe als sichtbarer Schritt (PFLICHT)

1. **Alle Concerns sammeln** — Roh-Liste aus allen 5 Agents.
2. **Explizit deduplizieren und gemeldet** — gleiches oder eng verwandtes Concern aus 2+ Dimensionen wird zu einem zusammengefasst, mit Hinweis auf die Konvergenz. Konvergente Concerns sind starkes Qualitätssignal (nicht Redundanz).
3. **Output-Format der Dedup-Phase** (sichtbar machen, nicht nur intern):
   ```
   Konsolidierung: {N_raw} Concerns → {N_dedup} nach Dedupe.
   Konvergent: {Concern X} (Architecture + Risk + Simplicity) — wahrscheinlich Kern-Issue
   ```
4. Dann dem User präsentieren via AskUserQuestion:

```
5-Dimensionen-Check abgeschlossen. {N_dedup} Concerns:

1. [Product] {Concern}
2. [Architecture + Risk + Simplicity] {konvergentes Concern}  ← Kern-Issue
3. ...
```

**Belegt durch Learning-Log:** Plan 7 hatte 11 raw → 9 dedup. Konvergente Concerns sind in 6 von 7 Plänen das beste Qualitätssignal. Sichtbar machen, damit der User die Convergenz erkennen kann.

Optionen:
- **Alle einarbeiten** — Alles fixen
- **Einzeln entscheiden** — Pro Concern ja/nein
- **Akzeptieren** — Plan ist gut genug, Concerns als "akzeptiert" markieren

### Plan finalisieren

Eingearbeitete Concerns in den Plan übernehmen. Akzeptierte Concerns als Kommentar im Plan notieren.

Plan-Datei speichern.

TodoWrite: `Plan challengen — 5 Dimensionen` (completed)

---

## Phase 3.5: Evaluation

Nach dem Challengen und Finalisieren: den Plan ein letztes Mal evaluieren lassen.

```
Agent(
  prompt: Du bist ein erfahrener Tech Lead. Lies diesen Plan und bewerte ihn ehrlich.

    {PLAN_INHALT}

    Codebase-Kontext:
    DATEISTRUKTUR: {DATEISTRUKTUR}
    ZENTRALE_PATTERNS: {ZENTRALE_PATTERNS}
    FRAMEWORK: {FRAMEWORK}

    Bewerte den Plan in diesen Dimensionen (je 1-2 Sätze, kein Filler):

    1. **Vollständigkeit** — Fehlen Schritte? Gibt es Lücken zwischen "was steht im Plan" und "was müsste man tatsächlich tun"?
    2. **Reihenfolge** — Stimmt die Abfolge der Schritte? Gibt es Abhängigkeiten die falsch oder gar nicht berücksichtigt sind?
    3. **Aufwand** — Ist der Scope realistisch? Wird etwas unterschätzt oder aufgebläht?
    4. **Risiken** — Was ist das größte Risiko das der Plan nicht adressiert?
    5. **Umsetzbarkeit** — Kann ein Entwickler den Plan nehmen und direkt loslegen, oder fehlen konkrete Details (Dateipfade, Methodennamen, Datenstrukturen)?

    PFLICHT-Checkliste (zusätzlich zu den 5 Dimensionen, knapp prüfen):
    - **Monitoring/Alerting-Blindspots:** Gibt es Failure-Modi die der Plan nicht observable macht? (z.B. Plan 7: Android-Token-Bug war unsichtbar weil Evidenz selbstzerstörisch)
    - **Bestehende Feature-Überlappungen:** Gibt es schon ähnliche Features in der Codebase die wiederverwendet werden sollten statt neu zu bauen?
    - **Optimierungs-Hebel:** Parallelisierung, Caching, Batch-Processing — wo lässt sich Aufwand reduzieren ohne Scope zu cutten?

    Am Ende: Ein Gesamturteil in EINEM Satz.
    Falls du Änderungen empfiehlst: maximal 3 konkrete Vorschläge.

  subagent_type: general-purpose
  model: sonnet
)
```

**Ergebnis dem User zeigen.** Wenn der Evaluator Änderungen empfiehlt, frage via AskUserQuestion:

```
Plan-Evaluation abgeschlossen.

Gesamturteil: {Urteil}

Empfehlungen:
1. {Empfehlung}
2. ...
```

Optionen:
- **Einarbeiten** — Empfehlungen in den Plan übernehmen
- **Passt so** — Plan ist fertig wie er ist

Bei "Einarbeiten": Änderungen vornehmen, Plan-Datei aktualisieren.

Ausgabe:

```
Plan fertig: docs/plans/{datum}-{slug}.md

{N} Concerns aus 5-Dimensionen-Check:
- {X} eingearbeitet
- {Y} akzeptiert

Evaluation: {Gesamturteil}
```

---

## Tonfall

Der Skill redet wie ein kluger Kollege:

Gut: "Mir fällt auf dass der Plan keine Fehlerbehandlung für X hat. Was passiert wenn Y schiefgeht?"
Schlecht: "Re-grounding context: The user's plan lacks error handling. Completeness: 3/10."

Gut: "Das klingt nach einem simplen Feature-Flag statt dem ganzen Umbau. Was spricht dagegen?"
Schlecht: "Alternative approach detected. Please evaluate tradeoffs of Feature Flag vs. Refactoring."

Gut: "Wer ist eigentlich der User hier? Admin oder Endnutzer? Das ändert den ganzen Ansatz."
Schlecht: "Target user persona not specified. Please select: A) Admin B) End user C) Both."

---

## Phase 4: Learning

TodoWrite: `Plan-Log schreiben und Learning` (in_progress)

Nach dem Plan-Abschluss: Plan-Log schreiben und Learning-Agent dispatchen.

### Plan-Log schreiben

```bash
PLAN_LOG_DIR="$(git rev-parse --show-toplevel 2>/dev/null)/.claude/plans/logs"
mkdir -p "$PLAN_LOG_DIR"
```

Schreibe `$PLAN_LOG_DIR/{YYYY-MM-DD}-{slug}.md`:

```markdown
# Plan-Log — {Titel}

## Meta
- Datum: {DATUM}
- Runden Phase 1 (Verstehen): {N}
- Plan-Datei: docs/plans/{datum}-{slug}.md

## Fragen & Antworten
- {Frage} → {User-Antwort oder "Einschätzung bestätigt"}

## Challenge-Ergebnis
- Concerns gesamt: {N}
- Eingearbeitet: {X}
- Akzeptiert: {Y}
- Abgelehnt: {Z}

## Bemerkenswert
- {Pattern oder Überraschung, z.B. "User hat alle Design-Concerns abgelehnt"}
```

### Learning-Agent dispatchen

```
Agent(
  prompt: Lies agents/learning-agent.md und führe den Ablauf aus.
    PROJECT_ROOT={PROJECT_ROOT}
    AKTUELLES_LOG={Inhalt des gerade geschriebenen Plan-Logs}
  subagent_type: general-purpose
  mode: bypassPermissions
  run_in_background: true
)
```

TodoWrite: `Plan-Log schreiben und Learning` (completed)
