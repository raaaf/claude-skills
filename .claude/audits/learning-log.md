# Audit Learning Log

Dieses Log wird automatisch nach jedem Audit aktualisiert.

## Trends (Stand 2026-07-17)

| Metrik | Wert |
|---|---|
| Audits total | 3 |
| Critical-Trend (letzte 3) | 0 -> 0 -> 0 (stabil) |
| Important-Trend (letzte 3) | 1 -> 3 -> 7 (steigend) |
| Top-Kategorie (letzte 5) | Docs/Docs-Sync (8x) |
| Avg Findings/Audit | 7,7 |

**Wiederkehrer (>=3 Audits):**
- Meta-Doku-Drift (CLAUDE.md/README.md/SKILL.md faellt bei Skill-Aenderungen auseinander) — jetzt in 3/3 Audits, jedes Mal andere Dateien -- candidate for guideline update (11-docs-sync.md verallgemeinern)

---

## Retro — 2026-07-07 — main (audit)

### Statistik
- Erster Audit im Projekt — noch keine Pattern-Erkennung moeglich

### Baseline
- Critical: 0, Important: 1, Minor: 4
- Saubere Dimensionen: Architektur, Security (Critical/Important), Code Quality, A11y, UI Design, UX (nach Fix), Docs Sync, Cross-Ref (nach Fix)
- Kontext: HUGE-Diff (64 Dateien, 2100 Zeilen) per User-Override als LARGE auditiert; SAUBER nach Runde 1 (Early-Exit)
- Routing-Floor-Override griff 4x (security, a11y, ui_design, ux) wegen Eval-Fixture blade.php als Frontend-Signal — Worker bestaetigten n/a

### Vorgeschlagene Verbesserungen
- [x] check-skips.sh: Dateien unter `audit/evals/fixtures/` nicht als Frontend-/Code-Signal fuer den Routing-Floor zaehlen (4 unnötige Worker-Dispatches in diesem Audit)

---

## Retro — 2026-07-08 — main (audit)

### Statistik
- Audits insgesamt im Projekt: 2
- Haeufigste Finding-Kategorie: Docs-Sync (3x, in beiden Audits)

### Was lief gut
- Learning-Loop geschlossen: check-skips-Fixture-Filter aus Retro 07.07. umgesetzt, in diesem Audit verifiziert (Floor-Override leer statt 4 False Positives)
- Validator verwarf 1 falsche Praemisse (examples/audit-log.md) statt sie zu fixen

### Was lief schlecht
- Docs-Sync-Drift wiederholt sich (2/2 Audits): CLAUDE.md-Beschreibung stale (07.07.), plugin.json/marketplace.json ohne /delegate (08.07.)

### Was hat gefehlt
- {DECIDED_TRADEOFFS}-Platzhalter fehlte in der /full-audit-Sektion von prompt-template.md — Datei war am 07.07. im Scope und wurde als sauber gewertet (verpasster Fund)

### Erkannte Patterns
- Geteilte Templates/Sektionen mit mehreren Aufrufern: Aenderung fuer einen Aufrufer, Sibling-Sektion vergessen (2 Audits)
- Meta-Doku (plugin.json, marketplace.json, CLAUDE.md-Tabellen) driftet bei Skill-Aenderungen (2 Audits)

### Vorgeschlagene Verbesserungen
- [x] audit/agents/11-docs-sync.md: Checkliste um `.claude-plugin/plugin.json` + `marketplace.json` ergaenzen, wenn Skill-Roster oder Skill-Descriptions im Diff sind
- [x] eval-fixture: architecture/template-placeholder-missing-sibling-section — Platzhalter in geteiltem Template nur fuer einen von zwei Aufrufern ergaenzt ({DECIDED_TRADEOFFS}-Miss vom 07.07.)

---

## Retro — 2026-07-17 — main (audit)

### Statistik
- Audits insgesamt im Projekt: 3
- Haeufigste Finding-Kategorie: Docs/Docs-Sync (8x ueber 3 Audits, in allen 3 vertreten)
- Durchschnittliche Findings/Audit: 7,7

### Was lief gut
- Learning-Loop erneut geschlossen: beide offenen Vorschlaege aus dem 08.07.-Retro (11-docs-sync.md plugin.json/marketplace.json-Regel, Eval-Fixture template-placeholder-missing-sibling-section) wurden umgesetzt und im Audit-Log als [x] bestaetigt
- Hallucination-Validator 11/11 verifiziert, 0 verworfen — sauberer Durchlauf ohne False Positives
- security/code_quality/typography/animation lieferten "Keine Findings." mit nachweislich echter Pruefung (u.a. Live-Injection/Race-Check auf dem neuen test-lock.sh), kein Lazy-Skip

### Was lief schlecht
- Docs-Sync-Drift eskaliert trotz Gegenmassnahme: 1 -> 2 -> 5 Findings ueber die 3 Audits. Die nach dem 08.07.-Audit ergaenzte 11-docs-sync.md-Regel (plugin.json/marketplace.json) deckte diesmal nicht die tatsaechlich drifteten Dateien ab (CLAUDE.md-Tabellen, README.md-Zahlen, SKILL.md-Formatkonvention) — die Regel war zu eng auf den einen zuvor gefundenen Fall zugeschnitten
- Neues Bash-Script (audit/bin/test-lock.sh) brauchte 3 Runden bis zur Konvergenz: Runde 1 TTL/WAIT_MAX-Logikfehler, Runde 2 verwaister Kindprozess bei Kill, Runde 3 set-u-Race mit dem TERM-Trap — jede Runde deckte einen neuen Concurrency-Bug im selben ~30-Zeilen-File auf

### Was hat gefehlt
- Kein generischer Checklisten-Punkt fuer neue Lock/Wait/Heartbeat-Bash-Skripte (Signal-Handling, set-u-Interaktion, Orphan-Cleanup bei Kill) — waere in Runde 1 pruefbar gewesen statt erst durch 2 weitere Fix-Verifier-Runden aufgedeckt zu werden

### Erkannte Patterns
- Meta-Doku-Drift (CLAUDE.md/README.md/SKILL.md faellt bei Skill-/Feature-Aenderungen auseinander): jetzt in allen 3 Audits (repeat offender, siehe Trends)
- Iteratives Haerten neuer Concurrency-Bash-Skripte ueber mehrere Runden: jede Runde findet einen neuen Edge-Case im selben File (test-lock.sh: 07-17, einzelner Beleg bisher, noch kein Repeat-Offender)

### Vorgeschlagene Verbesserungen
- [ ] audit/agents/11-docs-sync.md: Checkliste ueber plugin.json/marketplace.json hinaus verallgemeinern — bei neuem/umbenanntem Skill, Feature oder Step: CLAUDE.md-Tabellen (Commands, Migrated-so-far, Skill-Roster), README.md-Zahlen/Listen und SKILL.md-Schrittnummerierung/Format explizit gegenchecken (3/3 Audits zeigen dieses Muster)
- [ ] audit/guidelines/architecture.md: Checklisten-Punkt fuer neue Lock/Wait/Heartbeat-Bash-Skripte ergaenzen (explizite Pruefung von Signal-Traps x set -u, Orphan-Prozess-Cleanup bei Kill) — test-lock.sh brauchte 3 Runden genau dafuer
