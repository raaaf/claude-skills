# Architecture & Code Reuse Guidelines

Good architecture makes code easy to change, easy to test, and easy to understand. Every decision below serves at least one of those goals.

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
