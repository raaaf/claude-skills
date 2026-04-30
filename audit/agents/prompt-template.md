# Prompt-Template fuer Subagents

Dieses Template wird an jeden Subagent uebergeben. Platzhalter werden vom Audit-Skill ersetzt.

## Fuer /audit (Diff-basiert)

Audit der folgenden Aenderungen auf {DIMENSIONEN}.

Triage-Zusammenfassung: {TRIAGE_SUMMARY}

Deine spezifischen Hotspots (vom Triage-Agent markiert — FOKUSSIERE DICH AUSSCHLIESSLICH HIER):
{HOTSPOTS}

Geaenderte Dateien (zur Orientierung): {DATEILISTE}

Pruefe NUR auf echte, konkrete {DIMENSIONEN}-Probleme an den oben genannten Hotspots.

Suppressions (bekannte akzeptierte Issues -- NICHT melden):
{SUPPRESSIONS}

Regeln:
- Nur Issues melden die tatsaechlich Schaden anrichten oder gegen Best Practices verstossen
- Keine stilistischen Vorschlaege (dafuer gibt es den Linter)
- Keine theoretischen "koennte ein Problem sein"-Findings -- nur wenn es ein Problem IST
- **Code-Lesen on-demand:** Wenn ein Hotspot allein nicht ausreicht (z.B. Konsistenzpruefung gegen bestehende Komponente), lies die betreffende Datei mit dem Read-Tool. Max 5 Files pro Audit-Lauf.
- **KEIN ungezielter Diff-Scan.** Du bekommst keinen kompletten Diff mehr — der Triage-Agent hat bereits die fuer dich relevanten Stellen markiert. Nutze die Hotspots als Startpunkt, lies via Read-Tool gezielt nach wenn noetig.
- Fuer Full-Scans gibt es /full-audit
- Melde NICHT Issues die bereits in einer vorherigen Runde gefixt wurden: {BEREITS_GEFIXT}
- Melde NICHT Issues die in den Suppressions stehen -- diese wurden bewusst akzeptiert

Format (jedes Finding MUSS ein Confidence-Label haben):
**Maximal 50 Worte pro Finding-Beschreibung. Keine Code-Snippets im Finding -- nur Datei:Zeile referenzieren.**
**Critical:** [Datei:Zeile] (confidence: high|medium|low) Problem + warum kritisch
**Important:** [Datei:Zeile] (confidence: high|medium|low) Problem + Empfehlung
**Minor:** [Datei:Zeile] (confidence: high|medium|low) Vorschlag

Confidence-Regeln:
- `high` — Problem direkt im gelesenen Code verifiziert, Fix offensichtlich
- `medium` — Problem klar, aber Fix benoetigt projektspezifisches Judgment
- `low` — externe API/Lib nicht verifiziert, oder du bist unsicher ob es wirklich ein Problem ist

Keine echten Findings? Antworte exakt: "Keine Findings."

## Fuer /full-audit (Codebase-basiert)

Full Codebase Audit auf {DIMENSIONEN}.

Architektur-Kontext:
{ARCHITEKTUR-NOTIZ}

Bereits gefixt (nicht nochmal melden): {BEREITS_GEFIXT}

Suppressions (bekannte akzeptierte Issues -- NICHT melden):
{SUPPRESSIONS}

Dateien die du pruefen MUSST (lies JEDE einzelne Datei):
{BATCH_DATEILISTE}

WICHTIG: Lies JEDE Datei in der Liste. Ueberspringe keine. Beginne mit den wahrscheinlichsten Problem-Kandidaten, aber arbeite die komplette Liste ab.
Melde nur echte, konkrete Probleme. Keine theoretischen Findings.
Melde NICHT Issues die in den Suppressions stehen -- diese wurden bewusst akzeptiert.

Format (jedes Finding MUSS ein Confidence-Label haben):
**Maximal 50 Worte pro Finding-Beschreibung. Keine Code-Snippets im Finding -- nur Datei:Zeile referenzieren.**
**Critical:** [Datei:Zeile] (confidence: high|medium|low) Problem + warum kritisch
**Important:** [Datei:Zeile] (confidence: high|medium|low) Problem + Empfehlung
**Minor:** [Datei:Zeile] (confidence: high|medium|low) Vorschlag

Confidence-Regeln:
- `high` — Problem direkt im gelesenen Code verifiziert, Fix offensichtlich
- `medium` — Problem klar, aber Fix benoetigt projektspezifisches Judgment
- `low` — externe API/Lib nicht verifiziert, oder du bist unsicher ob es wirklich ein Problem ist

Keine Findings? Antworte exakt: "Keine Findings."
