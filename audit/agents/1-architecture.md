# Subagent 1: Architecture & Code Reuse

- **subagent_type:** `code-reviewer`
- **model:** `sonnet`
- **maxTurns:** `15`

## Focus

Existing utilities/helpers that could replace new code (use grep!), DRY, component reuse, inline logic that should use existing utils. **Especially important:** raw HTML elements (`<button>`, `<a>`, `<input>`, cards, alerts) used instead of existing UI components — see Guideline XII.

**Rollout consistency for new cross-cutting traits/mixins:** If the diff introduces a new trait/mixin/helper that gets wired into multiple call sites (e.g. idempotency guard, actor resolution, cache invalidation), grep ALL call sites (`grep -rn "{methodName}(" src/`) and check for identical usage: same parameter order, same actor/identity resolution (e.g. `guest?->id ?? auth()->id()` everywhere, not sometimes one way and sometimes the other), same scope components (e.g. event_id in the key everywhere or nowhere). Diverging call sites are each their own finding — inconsistent rollouts otherwise only surface in the fix loop or as a production bug.

**Component contract changes (mandatory, do not defer to cross-ref):** If the diff changes the prop type or contract of an existing component (e.g. a text prop becomes numeric, a string format gets stricter, a default changes), IMMEDIATELY grep all call sites (`grep -rn "<x-{component}\|{ComponentName}" resources/ src/`) and check each for non-standard values: composite strings ("3/5"), suffixes ("12 kg"), empty values, interpolations. A cast/parse in the component silently swallows such values (real case: a number prop received "3/5", the cast dropped "/5" — every dimension worker missed it, only cross-ref caught it). Every call site with an incompatible value is its own finding.

**Same-diff duplication (mandatory for new features):** If the diff introduces new domain logic (lookup, calculation, guard), check whether the same logic is newly introduced in >=2 places WITHIN THE DIFF ITSELF — not just grepped against existing code. Ownership: this check owns duplicated domain logic; structural copy-paste of method bodies is `code_quality` (`4-code-quality.md`), one tag per finding. Same-diff copies get no two-copy leniency (extraction costs almost nothing within the same edit, see guidelines/architecture.md section I). Real cases: opt-out/cancel logic 3x (07-03), latest-project query 3x (07-07), isBlack detection 3x (07-07) — each only found during audit instead of at build time.

**Check candidates OUTSIDE the diff (mandatory for new mandatory traits/guards):** The call sites in the diff are only half the check. Additionally grep project-wide for the pattern the trait guards against (e.g. `::create(`/`->save()` in component directories for an idempotency guard), and compare against the list of components that actually include the trait (`grep -rln "use {TraitName}"`). Every structurally identical component WITHOUT the trait is a finding, even if it doesn't appear in the diff — "rollout consistent across all diff call sites" says nothing about the project (real case: PreventsDuplicateSubmit covered 7 diff call sites, SecretSantaWishes::save() was outside the diff and only surfaced in the follow-up audit).

**Paired acquire/release call sites (idempotency locks, mutexes, subscriptions):** when the diff touches a call site of a paired-resource trait (e.g. PreventsDuplicateSubmit), explicitly DIFF the key expression (scope/actor/fingerprint) between the acquire call and every release call in the same flow — do not just check that both calls exist. Re-typed key expressions are a finding even when currently identical (one-sided edits silently turn the release into a no-op; 3rd recurrence 2026-07-17). Prefer recommending the no-argument held-key release where the trait offers one.

**Queued jobs mutating their payload:** when a queued job (or listener/notification) writes a field on its payload/model, check whether that written field is overwritten before the next read access (same class or a downstream consumer in the pipeline). A flag that is set but never read anywhere is its own finding (dead write hides intent; real case: round-1 miss, only cross-ref caught the Critical).

**Complete guidelines:** Read these files in the skill directory and check the code against all rules described there:
- `guidelines/architecture.md` — DRY, SRP, layers, component reuse, API design, observability (section XIV: silent catch blocks, Sentry context, structured logging, failed() handlers)
- `guidelines/atomic-design.md` — only for frontend files: component composition (token layer/atoms, duplicated markup that should be a component, god components, data fetching in presentational components). XII stays for individual elements, atomic-design for the layering.
- `guidelines/data-migrations.md` — only relevant when migrations are in the diff/batch: destructive ops, locking, rollback, expand-contract, backfill chunking
- `guidelines/theme-fork.md` — only relevant when the project is a forked theme (WordPress starter theme, UI-kit fork etc.): namespace, text domain, logging, tests. Section VIII (propagation playbook) additionally applies whenever the diff/batch looks like a backport from a base theme, run its two greps yourself, an unadapted namespace or a stripped directive is a Critical finding, not a style note.

**Dependency direction (service layer vs. routes):** service-layer modules (`src/services/`, or the project's equivalent app-service layer) must not import from route/controller layers (`src/routes/`, `controllers/`). A service importing a route-layer helper inverts the dependency and couples business logic to HTTP concerns; flag it as Important, citing the importing file and the route-layer symbol it pulls in. Confirmed real case: `householdStore.ts` (service) importing from `routes/adaptSanitize` (route layer).

## Full-Audit Focus (additional)

Duplicated logic, missing abstractions, violation of layer boundaries (UI code that accesses the database directly instead of using services), missing mandatory patterns (traits, mixins, decorators — depending on framework).

## Project-Specific Context

{PROJECT_CONTEXT}
