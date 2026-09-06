# Dimension: Code Quality & Simplification

## Look for

Redundant state (duplicated/derivable), parameter sprawl, copy-paste with slight variations, leaky
abstractions, stringly-typed code. Hardcoded user-facing strings in templates/components not
abstracted through translation functions or component props (Guideline VI).

Read `guidelines/code-quality.md` and `guidelines/code-quality-2026.md` in full.

- **Same-diff duplication:** two or more nearly identical method bodies newly introduced in the
  diff (parallel Livewire actions, wizard flows) → `Important`, extract before merge. Ownership:
  structural copy-paste of method bodies is this dimension; duplicated *domain logic* is
  `architecture`, never both. Includes `tests/`: repeated fixture/arrange blocks (>= 3x) in the
  diff are a finding.
- **Deterministic Blade duplication pre-check:** for 2+ new/changed Blade files, mechanically
  diff their added hunks for near-identical blocks >= 5 lines before applying judgment. Any hit is
  a duplication candidate.
- **Component counterpart check:** a new inline interactive pattern (custom keyboard handling,
  accordion, toggle, stepper, dropdown) needs a grep for an existing component counterpart first —
  if one exists, the inline version is `Important`.
- **New contextMenu/long-press path (native):** propose UITest coverage explicitly as part of the
  finding, not just a note.
- **XSS/injection-adjacent findings:** cross-check store/form-request validation first.
- **Enum findings:** verify the case exists via grep, including string-literal comparisons in
  templates against an enum-cast property.
- **Alpine `x-data` operator render risk:** only `>`/`>=`.
- **Notification/aggregation tests:** must assert the rendered literal, not only structure/counts.
- **Trait extraction needs trait-level tests**, not just coverage inherited from component tests.
- **Testabdeckung/Testart claims need a grep**, not an assumption: coverage claims are checked
  against the whole `tests/` tree by class name, not by filename; a guard-test claim needs the test
  to actually scan many files for a convention, not render one component.

**Defect classes calibrated against real findings (2026-09-05/2026-08-27 audits):**
- **Repeated boilerplate block copy-pasted 3+ times:** the same error-response shape, param
  parsing/validation block, or literal constant (secret placeholder, timeout value) duplicated
  across 3 or more route handlers/tests instead of a shared helper/constant.
- **Dead export or parameter:** a function/getter/constant exported or accepted but never called or
  read anywhere in the codebase (grep before flagging; a false negative here just means it's used
  from a spot you haven't checked).
- **Swallowed error silently coerced to success:** a `try { ... } catch { }`/`try?` that discards the
  real error and forces a success-looking state regardless of outcome.

## Severity

At most `Important` unless the defect produces demonstrably wrong output/behavior (not merely
inelegant code) — `Critical` is reserved for that case. Style, naming, and structure findings are
`Minor` unless they cause a real bug.

## Output

Reply with the specialist schema: `findings[{id, severity, confidence, files, issue, impact}]`
plus `coverage`. Every ID is prefixed `code_quality-`. Set `coverage` to `COVERAGE: full` or
`COVERAGE: partial | not read: {file1}, {file2}`.
