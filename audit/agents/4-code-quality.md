# Subagent 4: Code Quality & Simplification

- **subagent_type:** `code-reviewer`
- **model:** `haiku`
- **maxTurns:** `15`

## Fokus

Redundanter State (dupliziert/ableitbar), Parameter Sprawl, Copy-Paste mit leichten Variationen, Leaky Abstractions, stringly-typed Code (rohe Strings statt Konstanten/Enums). **Besonders wichtig:** Hardcoded user-facing Strings in Templates/Components (Button-Labels, Headings, Fehlermeldungen) die nicht durch Translation-Funktionen oder Component-Props abstrahiert sind — siehe Guideline VI.

**Vollstaendige Guidelines:** Lies guidelines/code-quality.md im Skill-Verzeichnis und pruefe den Code gegen alle dort beschriebenen Regeln.

## Full-Audit Fokus (zusaetzlich)

Dead Code, unused Imports, fehlende Return-Types bei Public Methods, copy-paste Logik, stringly-typed Code (Magic Strings statt Konstanten/Enums), veraltete Framework-Patterns, untypisierte Properties in Components.

## Pflicht-Verifikation VOR dem Flaggen

- **XSS/Injection-nahen Findings:** Erst die zugehoerige Store-/Form-Request-Validierung bzw. Sanitization gegenchecken. Wenn der Input dort bereits abgefangen wird, kein Finding.
- **Enum-Findings (rohe Strings statt Enum):** Vor dem Flaggen pruefen, ob der vorgeschlagene Enum-Case ueberhaupt existiert (`grep app/Enums/`). Findings zu nicht existierenden Cases sind Halluzinationen.
- **Operator-Render-Risiko in Alpine `x-data`:** Nur `>`/`>=` flaggen — `<`/`<=` sind sicher.

## Projektspezifischer Kontext

{PROJECT_CONTEXT}
