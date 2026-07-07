# Subagent 4: Code Quality & Simplification

- **subagent_type:** `code-reviewer`
- **model:** `haiku`
- **maxTurns:** `15`

## Fokus

Redundanter State (dupliziert/ableitbar), Parameter Sprawl, Copy-Paste mit leichten Variationen, Leaky Abstractions, stringly-typed Code (rohe Strings statt Konstanten/Enums). **Besonders wichtig:** Hardcoded user-facing Strings in Templates/Components (Button-Labels, Headings, Fehlermeldungen) die nicht durch Translation-Funktionen oder Component-Props abstrahiert sind — siehe Guideline VI.

**Vollstaendige Guidelines:** Lies guidelines/code-quality.md UND guidelines/code-quality-2026.md im Skill-Verzeichnis und pruefe den Code gegen alle dort beschriebenen Regeln.

**Komponenten-Pendant-Check (Blade/Component-Frameworks):** Fuehrt der Diff ein neues interaktives Inline-Pattern in einem Template ein (eigenes Keyboard-Handling, Accordion/Disclosure, Toggle, Stepper, Dropdown), ZUERST greppen ob ein Komponenten-Pendant existiert (`grep -rl "{pattern}" resources/views/components/` bzw. das komponentenverzeichnis des Projekts). Existiert ein `x-atoms`/`x-molecules`-Pendant (oder Aequivalent), ist die Inline-Logik ein Finding (Important): Komponente verwenden statt duplizieren. Erst wenn kein Pendant existiert, Inline-Logik akzeptieren.

## Full-Audit Fokus (zusaetzlich)

Dead Code, unused Imports, fehlende Return-Types bei Public Methods, copy-paste Logik, stringly-typed Code (Magic Strings statt Konstanten/Enums), veraltete Framework-Patterns, untypisierte Properties in Components.

## Pflicht-Verifikation VOR dem Flaggen

- **XSS/Injection-nahen Findings:** Erst die zugehoerige Store-/Form-Request-Validierung bzw. Sanitization gegenchecken. Wenn der Input dort bereits abgefangen wird, kein Finding.
- **Enum-Findings (rohe Strings statt Enum):** Vor dem Flaggen pruefen, ob der vorgeschlagene Enum-Case ueberhaupt existiert (`grep app/Enums/`). Findings zu nicht existierenden Cases sind Halluzinationen.
- **Operator-Render-Risiko in Alpine `x-data`:** Nur `>`/`>=` flaggen — `<`/`<=` sind sicher.

## Projektspezifischer Kontext

{PROJECT_CONTEXT}
