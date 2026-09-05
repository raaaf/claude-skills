# Dimension: Architecture & Code Reuse

## Look for

Existing utilities/helpers that could replace new code (grep!), DRY, component reuse, inline logic
that should use existing utils. Raw HTML elements (`<button>`, `<a>`, `<input>`, cards, alerts)
used instead of existing UI components (Guideline XII).

- **Rollout consistency for new cross-cutting traits/mixins:** a new trait/mixin/helper wired into
  multiple call sites (idempotency guard, actor resolution, cache invalidation) needs identical
  usage everywhere — same parameter order, same actor/identity resolution, same scope components.
  Diverging call sites are each their own finding.
- **Component contract changes:** a changed prop type/contract on an existing component (text →
  numeric, stricter format, changed default) needs a grep of ALL call sites for incompatible
  values (composite strings, suffixes, empty values, interpolations). Every incompatible call site
  is its own finding.
- **Same-diff duplication (new domain logic):** the same lookup/calculation/guard newly introduced
  in >= 2 places within the diff. Ownership: this dimension owns duplicated domain logic;
  structural copy-paste of method bodies is `code_quality`, one tag per finding.
- **Candidates outside the diff:** for a new mandatory trait/guard, grep project-wide for the
  pattern it guards against and compare against components that include the trait. Every
  structurally identical component without the trait is a finding, even outside the diff/scope.
- **Paired acquire/release call sites** (locks, mutexes, subscriptions): diff the key expression
  between acquire and every release in the same flow, not just presence. A re-typed key is a
  finding even when currently identical.
- **Queued jobs mutating their payload:** a written field never read again downstream is a finding
  (dead write hides intent).
- **Dependency direction:** service-layer modules must not import from route/controller layers.

Guidelines to read in full: `guidelines/architecture.md` (DRY, SRP, layers, component reuse, API
design, observability), `guidelines/atomic-design.md` (frontend files only), `guidelines/data-migrations.md`
(when migrations are in scope), `guidelines/theme-fork.md` (forked-theme projects; section VIII
applies when the diff looks like a base-theme backport).

## Severity

`Critical` only when the diff introduces two contradicting sources of truth (two places that both
claim to own the same fact and can drift). Everything else — missing reuse, duplication,
inconsistent rollout, dependency-direction violations — is at most `Important`. Style-only
reuse suggestions are `Minor`.

## Output

Reply with the specialist schema (`references/finding-schema.md`): `findings[{id, severity,
confidence, files, issue, impact}]` plus `coverage`. Every ID is prefixed `architecture-`. Set
`coverage` to `COVERAGE: full` or `COVERAGE: partial | not read: {file1}, {file2}`.
