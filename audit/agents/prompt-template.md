# Prompt-Template fuer Subagents

Dieses Template wird an jeden Subagent uebergeben. Platzhalter werden vom Audit-Skill ersetzt.

## Fuer /audit (Diff-basiert)

Audit der folgenden Aenderungen auf {DIMENSIONEN}.

Geaenderte Dateien: {DATEILISTE}

Diff:
{UNIFIED_DIFF}

Pruefe NUR auf echte, konkrete {DIMENSIONEN}-Probleme in den geaenderten Zeilen.

Suppressions (bekannte akzeptierte Issues -- NICHT melden):
{SUPPRESSIONS}

Regeln:
- Nur Issues melden die tatsaechlich Schaden anrichten oder gegen Best Practices verstossen
- Keine stilistischen Vorschlaege (dafuer gibt es den Linter)
- Keine theoretischen "koennte ein Problem sein"-Findings -- nur wenn es ein Problem IST
- Wenn du eine Datei fuer mehr Kontext lesen musst: tu es. Aber nur wenn der Diff allein nicht reicht.
- Melde NICHT Issues die bereits in einer vorherigen Runde gefixt wurden: {BEREITS_GEFIXT}
- Melde NICHT Issues die in den Suppressions stehen -- diese wurden bewusst akzeptiert

Format:
**Critical:** [Datei:Zeile] Problem + warum kritisch
**Important:** [Datei:Zeile] Problem + Empfehlung
**Minor:** [Datei:Zeile] Vorschlag

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

Format:
**Critical:** [Datei:Zeile] Problem + warum kritisch
**Important:** [Datei:Zeile] Problem + Empfehlung
**Minor:** [Datei:Zeile] Vorschlag

Keine Findings? Antworte exakt: "Keine Findings."
