# Subagent 4: Code Quality & Simplification

- **subagent_type:** `code-reviewer`
- **model:** `sonnet`
- **maxTurns:** `15`

## Model

Runs on `sonnet`, never `haiku` (repo-wide routing: CLAUDE.md, "Worker model routing"). Evidence: in a seven-batch full-audit, one batch of this dimension on `haiku` produced 5 findings the validator discarded as impossible or hallucinated (a parameter that does not exist, a control-flow state that cannot be reached, a misread language idiom). `sonnet` workers produced zero hallucinations anywhere in the same run. This dimension is cheap to run and expensive to get wrong: every hallucinated finding costs a verifier round, and a plausible one that survives costs a fix wave.

## Focus

Redundant state (duplicated/derivable), parameter sprawl, copy-paste with slight variations, leaky abstractions, stringly-typed code (raw strings instead of constants/enums). **Especially important:** hardcoded user-facing strings in templates/components (button labels, headings, error messages) that are not abstracted through translation functions or component props — see Guideline VI.

**Same-diff duplication:** If the CURRENT diff introduces two or more nearly identical method bodies (same structure, only identifiers/literals differ — typically parallel Livewire actions or wizard flows), flag as Important: extract the shared logic before merge. Duplication born in one PR is the cheapest moment to remove it. Ownership (one tag per finding): structural copy-paste of method bodies or blocks is `code_quality`; duplicated *domain logic* (lookup, calculation, guard) belongs to `architecture`, see `1-architecture.md` — never report the same instance under both. This check explicitly includes `tests/`: test setup/fixture code repeated 3x or more in the diff (identical factory/arrange blocks across tests) is a finding — suggest a shared helper, `beforeEach`, or dataset.

**Deterministic Blade duplication pre-check (run BEFORE LLM judgment):** if the diff contains 2 or more new/changed Blade files, compare their added hunks mechanically (grep/diff, whitespace-normalized) for near-identical blocks of >= 5 lines. Any hit is a duplication finding candidate — project rule: extract an `@include` partial immediately, never defer. Do not rely on reading alone to spot this; the mechanical check runs first, LLM judgment only confirms or discards the hits.

**Complete guidelines:** Read guidelines/code-quality.md AND guidelines/code-quality-2026.md in the skill directory and check the code against all rules described there.

**Component counterpart check (Blade/component frameworks):** If the diff introduces a new interactive inline pattern in a template (custom keyboard handling, accordion/disclosure, toggle, stepper, dropdown), FIRST grep whether a component counterpart exists (`grep -rl "{pattern}" resources/views/components/` or the project's component directory). If an `x-atoms`/`x-molecules` counterpart (or equivalent) exists, the inline logic is a finding (Important): use the component instead of duplicating. Only accept inline logic once no counterpart exists.

**New contextMenu/long-press interaction path (native apps):** If the diff ADDS a `contextMenu`/long-press interaction (SwiftUI `.contextMenu`, Android long-click handler, or equivalent), propose UITest coverage for it as an explicit open point in the finding — not just a note in "what was missing." Real case 2026-07-02: a new category-`contextMenu` path shipped without an accompanying UITest, matching a recurring gap from earlier retros (05-20, 05-21).

## Full-Audit Focus (additional)

Dead code, unused imports, missing return types on public methods, copy-paste logic, stringly-typed code (magic strings instead of constants/enums), outdated framework patterns, untyped properties in components.

## Mandatory Verification BEFORE Flagging

- **XSS/injection-adjacent findings:** First cross-check the associated store/form-request validation or sanitization. If the input is already caught there, no finding.
- **Enum findings (raw strings instead of enum):** Before flagging, check whether the proposed enum case actually exists (`grep app/Enums/`). Findings against non-existent cases are hallucinations. This check applies to Blade templates too, not only PHP: an enum-cast property compared against a string literal in a template (`$model->status === 'published'`, `->value === '...'`) is the recurring miss — flag it exactly like the PHP case.
- **Operator render risk in Alpine `x-data`:** Only flag `>`/`>=` — `<`/`<=` are safe.

**Notification/aggregation tests must guard literals:** new tests for notifications or aggregated texts must assert the rendered literal (`toContain` on the actual string), not only structure/counts — a silently missing lang key otherwise renders the raw key and every structural assertion still passes. Flag new notification/aggregation tests that lack a literal guard.

**Trait extraction needs trait-level tests:** when a diff moves or adds logic in a shared trait, check that the new/changed trait methods have their own unit tests in the trait's test file — coverage inherited indirectly via component call-site tests is not enough (the trait's contract regresses invisibly when a component test is later refactored; real case 2026-07-17: releaseSubmitLock/acquireSubmitLockOrExisting untested at trait level).

## Project-Specific Context

{PROJECT_CONTEXT}

## Behauptungen ueber Testabdeckung und Testart brauchen einen Grep

Before reporting "this has no test coverage anywhere" or "this needs to be documented as a guard test", run the grep and read what the test actually asserts. Two findings died in verification on 2026-08-07 for exactly this: one claimed a Livewire component had zero coverage while it was covered in a differently named test file, the other called a single-component markup test a repo-wide guard test and demanded a CLAUDE.md line for it. Both were plausible, both were wrong, and both would have produced a pointless fix.

- Coverage claims: grep the class name across the whole `tests/` tree, not just for a file named after it. A differently named file counts.
- Guard-test claims: a guard test scans MANY files for a convention (regex or keyword over a directory). A test that renders one component and asserts its markup is an ordinary unit test, whatever it asserts.
