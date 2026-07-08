# Audit Learning Log

Dieses Log wird automatisch nach jedem Audit aktualisiert.

## Trends (Stand 2026-07-08)

| Metrik | Wert |
|---|---|
| Audits total | 2 |
| Critical-Trend (letzte 3) | 0 -> 0 (stabil) |
| Important-Trend (letzte 3) | 1 -> 3 (steigend, kleine Stichprobe) |
| Top-Kategorie (letzte 5) | Docs-Sync (3x), Architektur und Security knapp dahinter |
| Avg Findings/Audit | 5.5 |

**Wiederkehrer (>=3 Audits):**
- Noch keine (erst 2 Audits). Beobachten: Docs-Sync-Drift bei Meta-Doku (2/2 Audits)

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
- [ ] audit/agents/11-docs-sync.md: Checkliste um `.claude-plugin/plugin.json` + `marketplace.json` ergaenzen, wenn Skill-Roster oder Skill-Descriptions im Diff sind
- [ ] eval-fixture: architecture/template-placeholder-missing-sibling-section — Platzhalter in geteiltem Template nur fuer einen von zwei Aufrufern ergaenzt ({DECIDED_TRADEOFFS}-Miss vom 07.07.)
