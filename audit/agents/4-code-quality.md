# Subagent 4: Code Quality & Simplification

- **subagent_type:** `code-reviewer`
- **model:** `haiku`
- **maxTurns:** `15`

## Focus

Redundant state (duplicated/derivable), parameter sprawl, copy-paste with slight variations, leaky abstractions, stringly-typed code (raw strings instead of constants/enums). **Especially important:** hardcoded user-facing strings in templates/components (button labels, headings, error messages) that are not abstracted through translation functions or component props — see Guideline VI.

**Same-diff duplication:** If the CURRENT diff introduces two or more nearly identical method bodies (same structure, only identifiers/literals differ — typically parallel Livewire actions or wizard flows), flag as Important: extract the shared logic before merge. Duplication born in one PR is the cheapest moment to remove it. This check explicitly includes `tests/`: test setup/fixture code repeated 3x or more in the diff (identical factory/arrange blocks across tests) is a finding — suggest a shared helper, `beforeEach`, or dataset.

**Complete guidelines:** Read guidelines/code-quality.md AND guidelines/code-quality-2026.md in the skill directory and check the code against all rules described there.

**Component counterpart check (Blade/component frameworks):** If the diff introduces a new interactive inline pattern in a template (custom keyboard handling, accordion/disclosure, toggle, stepper, dropdown), FIRST grep whether a component counterpart exists (`grep -rl "{pattern}" resources/views/components/` or the project's component directory). If an `x-atoms`/`x-molecules` counterpart (or equivalent) exists, the inline logic is a finding (Important): use the component instead of duplicating. Only accept inline logic once no counterpart exists.

## Full-Audit Focus (additional)

Dead code, unused imports, missing return types on public methods, copy-paste logic, stringly-typed code (magic strings instead of constants/enums), outdated framework patterns, untyped properties in components.

## Mandatory Verification BEFORE Flagging

- **XSS/injection-adjacent findings:** First cross-check the associated store/form-request validation or sanitization. If the input is already caught there, no finding.
- **Enum findings (raw strings instead of enum):** Before flagging, check whether the proposed enum case actually exists (`grep app/Enums/`). Findings against non-existent cases are hallucinations.
- **Operator render risk in Alpine `x-data`:** Only flag `>`/`>=` — `<`/`<=` are safe.

**Trait extraction needs trait-level tests:** when a diff moves or adds logic in a shared trait, check that the new/changed trait methods have their own unit tests in the trait's test file — coverage inherited indirectly via component call-site tests is not enough (the trait's contract regresses invisibly when a component test is later refactored; real case 2026-07-17: releaseSubmitLock/acquireSubmitLockOrExisting untested at trait level).

## Project-Specific Context

{PROJECT_CONTEXT}
