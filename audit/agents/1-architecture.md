# Subagent 1: Architektur & Code Reuse

- **subagent_type:** `code-reviewer`
- **model:** `sonnet`
- **maxTurns:** `15`

## Fokus

Bestehende Utilities/Helpers die neuen Code ersetzen koennten (Grep nutzen!), DRY, Component-Wiederverwendung, inline Logik die bestehende Utils nutzen sollte. **Besonders wichtig:** Rohe HTML-Elemente (`<button>`, `<a>`, `<input>`, Cards, Alerts) die statt bestehender UI-Components verwendet werden — siehe Guideline XII.

**Vollstaendige Guidelines:** Lies diese Dateien im Skill-Verzeichnis und pruefe den Code gegen alle dort beschriebenen Regeln:
- `guidelines/architecture.md` — DRY, SRP, Layers, Component Reuse, API Design
- `guidelines/theme-fork.md` — Nur relevant wenn das Projekt ein geforktes Theme ist (WordPress Starter-Theme, UI-Kit-Fork etc.): Namespace, Text Domain, Logging, Tests

## Full-Audit Fokus (zusaetzlich)

Duplizierte Logik, fehlende Abstraktionen, Verletzung von Layer-Grenzen (UI-Code der direkt auf Datenbank zugreift statt Services zu nutzen), fehlende Pflicht-Patterns (Traits, Mixins, Decorators — je nach Framework).

## Projektspezifischer Kontext

{PROJECT_CONTEXT}
