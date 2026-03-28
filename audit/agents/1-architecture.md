# Subagent 1: Architektur & Code Reuse

- **subagent_type:** `code-reviewer`
- **model:** `opus`
- **maxTurns:** `15`

## Fokus

Bestehende Utilities/Helpers die neuen Code ersetzen koennten (Grep nutzen!), DRY, Component-Wiederverwendung, inline Logik die bestehende Utils nutzen sollte. **Besonders wichtig:** Rohe HTML-Elemente (`<button>`, `<a>`, `<input>`, Cards, Alerts) die statt bestehender UI-Components verwendet werden — siehe Guideline XII.

**Vollstaendige Guidelines:** Lies guidelines/architecture.md im Skill-Verzeichnis und pruefe den Code gegen alle dort beschriebenen Regeln.

## Full-Audit Fokus (zusaetzlich)

Duplizierte Logik, fehlende Abstraktionen, Verletzung von Layer-Grenzen (UI-Code der direkt auf Datenbank zugreift statt Services zu nutzen), fehlende Pflicht-Patterns (Traits, Mixins, Decorators — je nach Framework).

## Projektspezifischer Kontext

{PROJECT_CONTEXT}
