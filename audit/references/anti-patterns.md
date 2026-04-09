# Audit: Anti-Patterns (Rote Flaggen)

Lies diese Datei wenn dir die Regeln im Haupt-Skill nicht präsent sind. Jede Zeile markiert einen Denkfehler, der den Audit-Loop kaputtmacht.

## Loop-Steuerung

- **"Ich warte auf Bestätigung vom User bevor ich die nächste Runde starte"** → FALSCH. Der Loop läuft autonom. Kein User-Input zwischen Runden.
- **"Eine Runde reicht"** → FALSCH. Erst bei `AUDIT_STATUS: SAUBER` ist der Loop beendet. `FIXES_APPLIED` + `RUNDE < 5` → sofort nächste Runde.
- **"Ich erkläre jetzt den Plan"** → FALSCH. Direkt ausführen.
- **"Findings sind gleich geblieben, ich probiere noch eine Runde"** → FALSCH. Bei `NO_CONVERGENCE` (Runde ≥ 2 und Findings sinken nicht): Loop sofort beenden.

## Subagent-Disziplin

- **"In Runde 2 reichen nur Architecture und Code Quality"** → FALSCH. In JEDER Runde werden ALLE zulässigen Subagents (1-7 plus die Frontend-Gruppe falls FRONTEND_DATEIEN vorhanden) dispatcht. Ein Security-Fix kann ein Performance-Problem einführen. Ein Architecture-Refactor kann A11y brechen.
- **"Der Validator ist übertrieben, ich trust den Subagents"** → FALSCH. LLM-Findings halluzinieren Dateipfade, Zeilennummern und API-Signaturen. Schritt D.5 ist Pflicht.
- **"Das Finding sieht komisch aus, ich fixe es einfach mal"** → FALSCH. Erst Halluzinations-Validator. Wenn Datei/Zeile nicht existiert: Finding verwerfen.

## Testplan

- **"Testplan kann ich ueberspringen weil keine visuellen Aenderungen da sind"** → Pruefe `FRONTEND_DATEIEN` / `VISUELL_RELEVANTE_DATEIEN`. Wenn leer: korrekt, kein Testplan noetig. Wenn nicht leer: Testplan ist Pflicht.
- **"Ich generiere einen generischen Testplan"** → FALSCH. Der Testplan muss konkrete Seiten, Routes und Aenderungen aus dem Diff referenzieren. Max 10 Schritte, priorisiert nach Risiko.

## Full-Audit-spezifisch

- **"Das Finding ist Minor, das überspringe ich"** → FALSCH. Full-Audit fixt ALLES — Critical, Important und Minor.
- **"Convergence-Check kann ich überspringen"** → FALSCH. Ohne Convergence-Check landet man in Fix-Schleifen.
