# Subagent 4: Code Quality & Simplification

- **subagent_type:** `code-reviewer`
- **model:** `opus`
- **maxTurns:** `15`

## Fokus

Redundanter State (dupliziert/ableitbar), Parameter Sprawl, Copy-Paste mit leichten Variationen, Leaky Abstractions, stringly-typed Code (rohe Strings statt Konstanten/Enums). **Besonders wichtig:** Hardcoded user-facing Strings in Templates/Components (Button-Labels, Headings, Fehlermeldungen) die nicht durch Translation-Funktionen oder Component-Props abstrahiert sind — siehe Guideline VI.

**Vollstaendige Guidelines:** Lies guidelines/code-quality.md im Skill-Verzeichnis und pruefe den Code gegen alle dort beschriebenen Regeln.

## Full-Audit Fokus (zusaetzlich)

Dead Code, unused Imports, fehlende Return-Types bei Public Methods, copy-paste Logik, stringly-typed Code (Magic Strings statt Konstanten/Enums), veraltete Framework-Patterns, untypisierte Properties in Components.

## Projektspezifischer Kontext

{PROJECT_CONTEXT}
