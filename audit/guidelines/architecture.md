# Architecture & Code Reuse Guidelines

Good architecture makes code easy to change, easy to test, and easy to understand. Every decision below serves at least one of those goals.

## Contents
- I. DRY — Don't Repeat Yourself
- II. Single Responsibility Principle
- III. Composition Over Inheritance
- IV. Service Layer Patterns
- V. Traits vs Services vs Helpers
- VI. Dependency Injection
- VII. Layer Boundaries
- VIII. Feature Cohesion
- IX. API Design
- X. Configuration
- XI. Error Handling
- XI.a Status Codes Are a Contract With Every Caller
- XII. Component Reuse — No Raw HTML
- XIII. Guard Clauses
- View / Template Duplication
- XIV. Observability & Error Reporting (2026)
- XV. Admin-Panel Action Gating (Filament 5)
- XVI. Seeder Idempotency & Stale Keys
- XVII. Shared Utilities & Constants — Grep First, Roll Out Fully
- XVIII. Lock, Wait and Heartbeat Scripts (Bash)
- XIX. Rules That Depend on State Outliving Their Screen

## I. DRY — Don't Repeat Yourself

Duplication is a signal, not a sin. When you see the same logic in two places, ask: "Is this the same concept, or just the same code right now?"

**When DRY applies:**
- Business rules that must stay in sync (e.g., discount calculation used in cart and invoice)
- Validation logic repeated across controllers
- Query scopes duplicated in multiple repositories

**When duplication is acceptable:**
- Two features happen to share similar code today but evolve independently
- Forcing a shared abstraction would create coupling between unrelated domains
- The "shared" code requires so many parameters and conditionals to handle all callers that it becomes harder to read than two simple copies

The wrong abstraction is far more expensive than duplication. If you extract a shared function and it immediately needs `if (context === 'A')` branches — revert and keep the copies.

**Same-diff duplication gets no grace period.** The acceptance cases above apply to duplication that grew organically over time. When the SAME new logic (a lookup, a calculation, a guard) is introduced at 2+ places within the current diff, extraction costs almost nothing — same edit, same review — and skipping it ships day-one drift. Flag it as Important, regardless of the two-copies leniency rule.

## II. Single Responsibility Principle

Every class and function should have exactly one reason to change. If you struggle to name what a class does without using "and," it does too much.

**Symptoms of violation:**
- A controller that validates input, queries the database, transforms data, sends an email, and returns a response
- A model with 800+ lines because it contains business logic, scopes, accessors, and helper methods
- A service class named `UserService` that handles registration, authentication, profile updates, and notification preferences

**Fix:** Extract until each piece has a clear, singular purpose. `UserRegistrationService`, `ProfileUpdateService`, `NotificationPreferenceService` — each is independently testable and independently changeable.

## III. Composition Over Inheritance

Deep inheritance chains create fragile hierarchies where changing a parent breaks unpredictable children. Prefer composing behaviors from small, focused pieces.

```
// Avoid: deep inheritance
class AdminUser extends PremiumUser extends User extends BaseModel

// Prefer: composition via mixins/traits or injected services
class User extends BaseModel
    uses HasPermissions, HasSubscription, SendsNotifications
```

Inheritance is appropriate for genuine "is-a" relationships with shared structure (e.g., ORM models extending a base model class). For shared behavior, use mixins/traits or injected collaborators.

## IV. Service Layer Patterns

Extract logic from controllers and components into services when:
- The same business logic is needed from multiple entry points (web, API, CLI, queue job)
- The operation involves multiple models or external systems
- The logic requires complex orchestration or transaction management
- You need to test business rules independently of HTTP or UI framework

**A service should:**
- Accept explicit parameters (not request objects)
- Return typed results (DTOs, models, or value objects — not arrays)
- Throw specific exceptions on failure
- Be stateless — no properties that persist between calls

```
// Controller stays thin
function store(request: CreateProjectRequest): RedirectResponse
    project = projectService.create(request.validated())

    return redirect('projects.show', project)
```

## V. Traits vs Services vs Helpers

Each has a specific purpose. Using the wrong one creates confusion.

| Construct | Purpose | State | Example |
|-----------|---------|-------|---------|
| **Trait/Mixin** | Shared model behavior, reusable capabilities | Operates on `this` | `SanitizesInput`, `HasUlids`, `Searchable` |
| **Service** | Business logic, orchestration | Stateless, injected | `InvoiceGenerationService`, `SubscriptionService` |
| **Helper** | Pure utility functions, no side effects | No state at all | `formatCurrency()`, `slugify()`, `arrayToTree()` |

**Rules:**
- Traits/mixins should never depend on services or perform I/O directly — they add capabilities to the host class
- Services are the primary home for business logic — inject dependencies via constructor
- Helpers are pure functions: same input always produces same output, no database calls, no external state

## VI. Dependency Injection

Constructor injection makes dependencies explicit, visible, and testable. Facades and static calls hide dependencies and make unit testing painful.

```
// Avoid: hidden dependency
class OrderService
    function place(order: Order):
        PaymentGateway.charge(order.total)  // hidden, untestable
        Mailer.send(new OrderConfirmation(order))  // hidden, untestable

// Prefer: explicit injection
class OrderService
    constructor(
        private payment: PaymentGateway,
        private mailer: Mailer,
    )

    function place(order: Order):
        this.payment.charge(order.total)
        this.mailer.send(new OrderConfirmation(order))
```

In tests, you can now inject fakes or mocks without touching global state. Every dependency is visible in the constructor signature.

## VII. Layer Boundaries

Each layer has one job. Don't let layers bleed into each other.

| Layer | Responsibility | Must NOT do |
|-------|---------------|-------------|
| **Controllers/Handlers** | Accept HTTP input, delegate, return response | Contain business logic, query database directly |
| **UI Components** | Handle UI interaction, delegate to services | Contain business logic beyond simple UI state |
| **Services** | Execute business logic, orchestrate operations | Access request context, return responses, know about HTTP |
| **Models** | Data access, relationships, scopes, accessors | Contain business logic, send notifications, call services |
| **Views/Templates** | Present data, render HTML | Contain logic beyond simple conditionals and loops |
| **Request Validators** | Validate and authorize input | Contain business logic |

A controller that queries the database, applies business rules, and formats output has collapsed three layers into one. When requirements change, you touch everything.

**No database queries in templates or layouts.** A view or layout that runs a query (`Model::where(...)`, `DB::table(...)`, an Eloquent relation triggered for the sole purpose of rendering chrome like a nav badge or account list) couples presentation to data access and re-runs on every render, including partial re-renders. Pass the data in from the controller, or for layout-wide data that every page needs (sidebar counts, account balances, the authenticated user's menu), use a **View Composer** (Laravel) / context provider / equivalent so the query lives in one testable place and the template only consumes the result. A query inside a Blade/template file is a finding regardless of how small it looks.

**No direct model mutations in UI components (Livewire/component classes) or their traits.** When a project has a service layer, a Livewire component (or equivalent UI-component class) that calls `Model::create(...)`, `Model::where(...)->update(...)`, `$model->update(...)` or `$model->delete()` directly for a domain mutation bypasses it — validation, events, cache invalidation and side effects that live in the service silently don't run, and the next caller duplicates the logic. This is a **confirmed recurring pattern** (3+ independent occurrences), so treat it as a firm finding, not a judgement call. It applies equally to traits mixed into UI components: a shared form-trait whose `save*()` method writes models directly is the same bypass, just harder to spot because the write lives outside the component file — grep trait methods used by components, not only the components themselves. Audit signal: any write call on a model inside a UI-component class or a trait consumed by one is a finding when a service with matching responsibility exists (or when sibling methods in the same class already delegate to one). Read-only queries for display are fine. Fix: route through the existing service; if no method fits semantically, add a dedicated one instead of force-fitting a mismatched method (recurring real case: gift "wishes" needed `createWish()`, not `createItem()` with different column semantics). **Bypass fixes roll out project-wide, not per diff instance:** once a bypass is confirmed, grep the whole project for the same method name / domain action in sibling classes (e.g. `grep -rn "deleteGroup(\|archiveEvent(" app/`) and fix every call site in the same pass — the rollout check that already applies to new traits applies to bypass fixes too (real case: `deleteGroup` existed in two classes, only the diffed one was fixed, the sibling crashed production).

**Parent soft-deletes must cascade to dependent children.** A `delete()`/`archive()` service method on a parent model must explicitly cascade to every child model holding a nullable FK on the parent — or the consuming side must be provably null-safe. Soft deletes don't fire DB-level `ON DELETE` behavior, so children keep pointing at a parent that no longer resolves: `$child->parent` returns null while flags derived from the FK (`isGroupSession()` checking `group_id`) still return true, which crashes views at render time (real case: Group soft-delete left its event sessions with a dangling `group_id` → production `ViewException`). Audit signal: when reviewing a parent `delete()`/`archive()` method, list the parent's `children()`-style relations and check each is either cascaded (detached, soft-deleted, or re-parented) or read null-safely everywhere.

## VIII. Feature Cohesion

Related code should live together. Organizing strictly by type (all controllers in one folder, all models in another) scatters related features across the codebase.

**Prefer feature-based grouping when the codebase grows:**
```
src/
  Billing/
    InvoiceService.ts
    InvoiceController.ts
    Invoice.ts
    CreateInvoiceRequest.ts
  Projects/
    ProjectService.ts
    ProjectController.ts
    Project.ts
```

**Over pure type-based grouping:**
```
src/
  Controllers/
    InvoiceController.ts
    ProjectController.ts
  Models/
    Invoice.ts
    Project.ts
  Services/
    InvoiceService.ts
    ProjectService.ts
```

When you work on "billing," you want all billing code in one place — not scattered across five directories.

## IX. API Design

Every public method is an API — whether it faces the internet or just another class.

- **Consistent naming:** If one endpoint returns `created_at`, don't return `createdAt` elsewhere. Pick a convention and enforce it.
- **Predictable return types:** A method should always return the same type. Don't return `User|null|false|array` depending on conditions.
- **Fail explicitly:** Throw an exception or return a typed error — never return `null` to signal failure when `null` could also be a legitimate value.
- **No boolean parameters:** `createUser(data, true, false)` is unreadable. Use named parameters, enums, or separate methods.
- **Idempotent where possible:** Calling the same operation twice should produce the same result, especially for write operations exposed via API.

## X. Configuration

Magic values scattered across the codebase are maintenance nightmares. Centralize them.

```
// Avoid: magic values buried in logic
if (attempts > 5) { ... }
if (role === 'super-admin') { ... }
timeout = 30

// Prefer: named constants or config
if (attempts > MAX_LOGIN_ATTEMPTS) { ... }
if (role === Role.SuperAdmin) { ... }
timeout = config('services.payment.timeout')
```

**Rules:**
- Use enums for finite sets of known values (status, role, type)
- Use class constants for values that belong to a specific domain
- Use config files for values that vary per environment
- Never hardcode URLs, credentials, timeouts, limits, or feature flags

## XI. Error Handling

Silent failures are the most expensive bugs — they go undetected until they cause cascading damage.

- **Fail fast:** Validate inputs at the boundary. Don't let bad data travel deep into the system.
- **Use typed exceptions:** `InsufficientBalanceException` is infinitely more useful than `Exception('error')`.
- **Don't swallow errors:** An empty `catch` block is almost always a bug. If you genuinely need to ignore an exception, add a comment explaining exactly why.
- **Log with context:** `log.error('Payment failed', { orderId: id, amount: amount })` — not just `log.error('Payment failed')`.
- **Distinguish recoverable from fatal:** A missing optional config value is recoverable. A missing database connection is fatal. Handle them differently.

## XI.a Status Codes Are a Contract With Every Caller

A service that answers "why did this fail" with a string code owns that code set, but it does not own the messages. Each caller maps codes to user-facing text, so adding or renaming one silently degrades every caller that has not been updated: the new code falls through to a generic "something went wrong" while the service is being precise.

**When a shared method gains or renames a status/blocker/result code:**

1. Grep for the method name across the project to find every caller.
2. In each, find the map from code to message (a `match`, an array literal, a ternary chain) and add the new code.
3. Codes that stay unmapped on purpose need a comment saying so, otherwise the next reader cannot tell an omission from a decision.

A ternary on one code (`$result === 'ok' ? … : …`) is the shape that hides this best: it looks total but silently lumps every failure together. Prefer an explicit map so a missing arm is visible.

**Smell:** the service defines four codes, the caller's map has three keys, and nothing fails.

## XII. Component Reuse — No Raw HTML

Before writing a raw HTML element (`<button>`, `<a>`, `<input>`, `<div class="card">`, `<div class="alert">`, etc.), check whether a matching component already exists in the project.

**Mandatory check order:**
1. Search for existing UI components in the project's component directories
2. Search for existing interactive/stateful components
3. Search for component usage patterns in the codebase to find naming conventions

**Common violations:**
```html
<!-- Avoid: raw HTML when components exist -->
<button class="px-4 py-2 bg-blue-600 text-white rounded">Save</button>
<a href="/dashboard" class="text-blue-600 underline">Dashboard</a>
<div class="p-4 border rounded-lg shadow">Card content</div>

<!-- Prefer: project components -->
<Button>Save</Button>
<Link href="/dashboard">Dashboard</Link>
<Card>Card content</Card>
```

**Rules:**
- NEVER use a raw `<button>`, `<a>`, `<input>`, `<select>`, `<textarea>`, `<table>`, card-like `<div>`, or alert-like `<div>` if a component exists for it
- If the same raw HTML pattern appears 3+ times across the codebase without a component — flag it as a finding and recommend creating a component
- When a component exists but is not used in new code — that's a **Critical** finding (inconsistency + maintenance burden)
- Components ensure consistent styling, accessibility attributes (aria, role), and behavior across the entire application

**Only allowed exception:** a raw element is acceptable when the component genuinely cannot express a required custom behavior (e.g. an Alpine/`x-`-directive `@change` handler, a `wire:model` binding, or a framework directive the component does not forward). Even then, prefer extending the component to accept the directive over dropping to raw HTML. Document the reason inline; an undocumented raw element next to an existing component is still a finding.

**Checking for components:**
```bash
# Find all existing UI components
find src/components -name "*.tsx" -o -name "*.vue" -o -name "*.svelte" | sort
# Find how specific elements are used across the codebase
grep -r "<Button" src/ | head -20
grep -r "<button " src/ | head -20  # raw usage = potential violation
```

## XIII. Guard Clauses

Early returns eliminate nesting and make the "happy path" obvious.

```
// Avoid: deeply nested
function process(order: Order):
    if order.isPaid():
        if order.hasItems():
            if not order.isShipped():
                // actual logic buried 3 levels deep

// Prefer: guard clauses
function process(order: Order):
    if not order.isPaid():
        return

    if not order.hasItems():
        throw new EmptyOrderException(order.id)

    if order.isShipped():
        return

    // actual logic at top level
```

Guard clauses read like a checklist of preconditions. The reader immediately sees what must be true before the real work begins.

## View / Template Duplication

Create and Edit views often share 80-95% of their markup. This is a DRY violation that causes bugs when one view is updated but the other is not.

**PHP logic duplication:** When two Livewire components (e.g., InvoiceCreate and InvoiceEdit) share identical methods — item management, computed totals, validation, customer selection — extract these into a shared trait (e.g., `HasInvoiceForm`). Each component then only contains `mount()`, the save action, and `render()`.

**Blade template duplication:** When two Blade views share >50% identical markup, extract the shared sections into partials (`@include('invoices.partials._items-section')`) or slot-based components. Only the unique parts (page title, action buttons) remain in the parent views.

**Indicator:** If a change to form validation, item handling, or computed totals requires editing two files, the duplication has not been sufficiently resolved.

## XIV. Observability & Error Reporting (2026)

Code that fails silently in production is worse than code that fails loudly in review. Check:

**Silent catch blocks.** `catch (Exception $e) {}` or `catch { return null; }` without logging or rethrow is a finding, always. Minimum: log with context. Better: report to the error tracker.

**Every `catch` around an external API call must log.** A `try/catch` wrapping a call to a third-party service (payment gateway, LLM API, mail provider, webhook dispatch) must call `Log::warning`/`Log::error` with context (endpoint, relevant ID, error message) in the `catch` block — a bare `catch` that only returns a fallback value or swallows the exception hides the failure from anyone who isn't actively watching that code path. This applies even when the caller degrades gracefully; graceful degradation and silent failure are different things, and only one of them is loggable after the fact.

**Error-tracker context.** When Sentry (or similar) is integrated: exceptions in business-critical paths should carry context — `user_id`, `request_id`, the affected entity ID. A bare exception without context costs an hour of debugging that one `setContext()` line would have saved.

**Structured logging over string interpolation.**

```php
// BAD — unparseable, unsearchable
Log::info("User $userId booked slot $slotId");

// GOOD — filterable in any log aggregator
Log::info('slot.booked', ['user_id' => $userId, 'slot_id' => $slotId]);
```

**Log levels mean something.** `error` = needs human attention, `warning` = degraded but handled, `info` = business event, `debug` = development only. An app that logs routine events as `error` trains everyone to ignore errors.

**Alert-worthy failures must be alertable.** Payment failed, queue job dead-lettered, external API circuit-broken — these need to reach the error tracker, not just a log file nobody reads. Audit signal: a `try/catch` around a payment or notification call that only logs.

**No PII in logs.** Email addresses, names, tokens in log lines are a privacy and security finding (see security.md). Log IDs, not identities.

**Queue jobs:** `failed()` method (or equivalent dead-letter handling) on jobs with side effects. A job that silently exhausts retries loses data invisibly.

## XV. Admin-Panel Action Gating (Filament 5)

Filament 5 gates `DeleteAction` via Policy + `Action->visible()`, NOT via `Resource::canDelete()`. A `canDelete()` override on the Resource has no effect on the Edit-page header action: the DeleteAction stays clickable. Audit signal: a delete guard that only exists as `Resource::canDelete()` is a finding. Anchor delete guards at `Action->visible()` AND at the Policy (defense in depth, the Policy also covers bulk actions and direct Livewire calls).

## XVI. Seeder Idempotency & Stale Keys

`firstOrCreate` / `updateOrCreate(..., $attributes)` and `Model::create()` seeders set the data **only on first insert**. When a seeded `data`/JSON/settings structure is later **extended with new keys**, existing production rows never receive them — they keep the old shape. The Admin form then renders an empty field while a frontend fallback masks it, so nothing looks broken until the admin saves and overwrites the fallback with an empty string.

**Audit signal:** a seeder that builds a `data`/`settings`/`config` array via `firstOrCreate`/`create` for a structure that has grown since first deploy, with no merge step for missing keys.

**Fix — merge missing keys without clobbering admin edits:**

```php
// BAD — new keys never reach existing rows
Page::firstOrCreate(['slug' => 'home'], ['data' => $defaults]);

// GOOD — create with defaults, then backfill only missing keys
$page = Page::firstOrCreate(['slug' => 'home'], ['data' => $defaults]);
$page->data = array_replace_recursive($defaults, $page->data ?? []);
$page->save();
```

`array_replace_recursive($defaults, $existing)` keeps every admin-edited value and only fills keys the row lacks. Re-runnable, deploy-safe. Pairs with the CMS-fallback rule in ui-ux-patterns.md (a stale key plus a `??` fallback is the exact combo that ships an empty heading).

## XVII. Shared Utilities & Constants — Grep First, Roll Out Fully

- Before writing a new handler for audio/share/navigation glue in a view: grep for an existing shared utility first (e.g. `WordAudioShare.swift`); duplication across sibling views of the same feature pair is a recurring failure mode.
- When a change introduces a new shared constant/utility or centralizes a pattern: immediately `grep -rn` the OLD pattern across the ENTIRE repo — including `scripts/`, `tests/`, seeders, and tooling, not just the main source directory — and migrate every occurrence in the same change. Partial rollouts resurface as duplicate findings in later audit rounds.

## XVIII. Lock, Wait and Heartbeat Scripts (Bash)

Coordination scripts are the one place where a missing line does not fail loudly, it hangs. `test-lock.sh` needed three audit rounds for exactly the two points below, so check them explicitly whenever a diff adds or changes a lock, spinlock, wait loop, heartbeat, watchdog or retry wrapper.

**Signal traps under `set -u`.** A trap handler runs in the same shell, so every variable it touches must already be assigned at the moment the trap is installed. Under `set -euo pipefail` a handler that references a variable set later in the script aborts with an unbound-variable error, inside the cleanup path, which is where nothing is left to clean up afterwards. Assign the variables the handler needs before `trap`, and keep the handler to operations that work in a half-initialized state.

**Orphan cleanup on kill.** `trap ... EXIT` does not fire on `SIGKILL`, and a lock directory or PID file that outlives its owner blocks every later run until someone deletes it by hand. Any lock needs a second, independent release path: a TTL that a later run can detect and break, a liveness check against the recorded PID (`kill -0`), or both. A lock whose only release is the happy path is a finding, not a style preference.

Check as well: does the wait loop have a bounded number of attempts and a distinct exit code on timeout (a caller cannot distinguish "acquired" from "gave up" otherwise), and does the script clean up background children it started rather than leaving them to reparent to init.

## XIX. Rules That Depend on State Outliving Their Screen

A layout, routing or visibility rule that reads state which lives LONGER than the screen rendering it is a different animal from one that reads props. The screen can be rebuilt, or not; the state does not care. When it is not rebuilt, the rule keeps answering with an input that has since expired.

Trigger: the rule's inputs include anything held outside the view's own lifetime — a step in a flow, a phase enum, a cached "already done" marker, a deadline, a persisted selection.

Then walk these three explicitly, in writing, before accepting the rule:

1. **Day boundary.** The process is alive at 00:01 with the screen untouched. What does the rule return?
2. **Background and return.** The app was backgrounded for hours and comes back to the same view instance. Which inputs went stale while nothing ran?
3. **External change.** A sync, another device, or a background task rewrote the underlying data. Does the rule see it, or is it reading a value captured at first render?

Head-arithmetic is not enough here and the failure is documented: on 2026-07-27 an orchestrator checked exactly such a rule by reasoning and declared it safe, missing that the state survived the day change because the view is never rebuilt. A worker found it afterwards. If the rule is worth having, it is worth a test on the state sequence rather than on the rendered output.

Platform specifics and the five precedent cases: `guidelines/native-mobile.md`, section XIV.

Confidence: layout/routing rule reading view-outliving state with none of the three cases handled -> Important. The same rule with no test pinning it -> name it as an open point even when the logic is right.

## XX. Declarative Config Runtimes Have No Abstraction Primitives

Home Assistant automations, Ansible playbooks, k8s manifests and CI workflows are executing logic written in a language that mostly cannot factor itself. YAML anchors are unavailable or ignored in most of these runtimes (Home Assistant strips them inside `automation:` blocks), there are no functions, no loops over heterogeneous shapes, and no imports.

The consequence workers keep re-discovering: repeated blocks in such a file are frequently the ONLY expressible form, not carelessness. Reporting them as DRY violations produces a finding the user cannot act on, every single audit.

Before flagging repetition in a declarative config runtime, establish that an extraction target actually exists:

1. Does the runtime offer a callable unit (Home Assistant `script:`, Ansible `roles`/`include_tasks`, k8s kustomize bases, GitHub Actions reusable workflows)?
2. Does the repeated block have identical semantics, or does it merely look similar while differing in the entity/host/namespace it acts on?
3. Would the extraction survive the runtime's parameter model — Home Assistant script fields take scalars and objects but a service call still accepts only one target per invocation, so a "loop over rooms" may need a `repeat` inside the script rather than a flat call.

All three yes -> a real finding, and name the callable unit in the fix. Any no -> not a finding. Say so once in the audit log under accepted trade-offs rather than raising it again.

Confidence: repetition WITH an available callable unit and identical semantics -> Minor (Important only when the copies have already drifted apart). Repetition with no extraction target -> not reported.

## XXI. Drifted Copies Outrank Duplication

When the same block appears more than twice, stop counting copies and start diffing them against each other. Duplication costs maintenance; a copy that has silently diverged is a live defect that the duplication merely hid.

Two outcomes, and they are graded very differently:

- The copies are identical -> ordinary duplication, graded per XX.
- The copies differ -> Important, and the finding is the difference, not the repetition. Name which copy is wrong and why, because one of them is.

The trap to avoid: divergence is not automatically a bug. Copies attached to different branches of the same state machine often SHOULD differ, each omitting what its own branch already handled. On 2026-08-19 three copies of a volume-priority template were reported as drifted; each branch deliberately left out the scene that had just ended, and all three were correct. Establish which branch each copy belongs to before calling a difference a defect.

## XXII. A Fact With a New Source Has Old Consumers

When an "is X active / available / allowed" fact gains a second source (a flag OR the existence of data, a setting OR a role, a config value OR an env override), every consumer of the old, narrower check is now wrong in the same way. In the same change, grep for all of them: settings-section `isAvailableFor()`-style predicates, Blade/JSX gates, navigation and tour services, notification triggers, exports. One missed consumer produces the split state that recurred 15 times in one project: the drawer hides a section while the host CTA links to it (2026-08-27). Confidence: widened fact with a consumer still on the narrow check in the diff scope -> Important; the consumer is a security gate -> Critical.

## XXIII. Touching an Existing Helper Means Touching Its Call Sites

A fix that changes the signature, return shape, or semantics of an EXISTING shared helper (`sentryEnabled()`, `capturingClient`, a formatter, a scope) is incomplete until every call site was read and adjusted; grep them before the edit, list them in the fix report. The same rule as XVII for new utilities, applied to changed ones. Two audits in a row (2026-08-27, 2026-08-28) had a helper fix leave a call site on the old contract.

## XXIV. A New Model or DTO Field Has Serialized Copies

Adding a field to a model, DTO or catalog record is not done when the model compiles: every place that copies the record into another representation must carry it too, or the copy is silently stale. Grep for the serialization sites explicitly: widget/extension shared stores (`SharedStore`, App Group plists), intents (`WidgetIntents`), caches, exports, API resources, search indexes, seeders. Second occurrence of this gap class on 2026-09-03. Confidence: new field missing from a copy that renders it (widget, export) -> Important.

## XXV. Configuration Access and Failure Isolation

- **No `env()` outside `config/*.php`** (Laravel) and no direct environment reads outside the config layer in other stacks: config caching makes `env()` return null at runtime, and scattered reads make the value set unauditable. Read from `config()`.
- **External API clients are centralized:** one client class per provider with base URL, headers, timeout, retry policy and endpoint/model names from config; call sites never build HTTP requests or headers themselves.
- **Notifications and other best-effort side effects are isolated from the user action:** wrap `Notification::send`/mail/push calls inside a service in `try/catch` + `report($e)` so a provider outage cannot abort a save, a checkout or a signup. A user action that fails because a notification failed is a finding (2026-06-11).
