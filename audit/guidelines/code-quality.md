# Code Quality & Clean Code Guidelines

Clean code reads like well-written prose — every name reveals intent, every function does one thing, and the structure guides you without needing a map.

## I. Naming

Names are the primary documentation of your code. A good name eliminates the need for a comment.

**Variables and functions should reveal intent:**
```
// Avoid: cryptic, abbreviated, generic
d = order.createdAt.diffInDays(now())
tmp = users.filter((u) => u.active)
function proc(data) { ... }

// Prefer: self-documenting
daysSinceOrder = order.createdAt.diffInDays(now())
activeUsers = users.filter((user) => user.active)
function processRefund(request: RefundRequest): Refund { ... }
```

**Rules:**
- No single-letter variables outside of trivial closures or loop counters
- No abbreviations unless universally understood (`id`, `url`, `html` are fine — `usr`, `mgr`, `ctx` are not)
- No Hungarian notation (`strName`, `arrItems`, `boolIsActive`)
- Booleans should be questions: `isActive`, `hasPermission`, `canEdit`, `shouldNotify`
- Classes are nouns (`InvoiceService`, `PaymentGateway`), methods are verbs (`calculateTotal`, `sendNotification`)
- Use domain language — if the business says "subscription," don't call it "plan" in code

## II. Function Size

A function should do one thing, do it completely, and do it well. If you feel the urge to add a comment explaining what the next block does — extract it into a named function instead.

**Signals a function is too long:**
- You need to scroll to see the whole thing
- It has more than one level of abstraction (HTTP parsing mixed with business logic mixed with formatting)
- It requires a comment to separate logical sections
- It has more than 2 levels of nesting

**Extract ruthlessly:**
```
// Before: one long method doing everything
function import(file: UploadedFile): ImportResult
    // validate file format
    // ... 15 lines ...

    // parse rows
    // ... 20 lines ...

    // transform and save
    // ... 25 lines ...

// After: composed from named steps
function import(file: UploadedFile): ImportResult
    validateFormat(file)
    rows = parseRows(file)

    return transformAndSave(rows)
```

Each extracted method is independently testable and its name documents its purpose.

## III. Type Safety

Type hints are executable documentation. They catch bugs at write-time, not runtime.

**Use type hints everywhere:**
- All function parameters
- All return types (including `void`)
- All class properties
- Collection generics where supported

```
// Avoid: untyped, guessing required
function getDiscount(user, amount) { ... }

// Prefer: fully typed
function getDiscount(user: User, amount: Money): Money { ... }
```

**Rules:**
- Never use `mixed`/`any` unless interfacing with an external system that truly sends anything
- Avoid union types like `string|int|null` — if a value can be multiple types, the design needs rethinking
- Enable strict type checking in your language/toolchain
- Use readonly/immutable properties where values should not change after construction

## IV. Dead Code

Dead code is noise that distracts readers and creates false search results. Remove it aggressively.

**What counts as dead code:**
- Unused imports
- Commented-out code blocks (that's what Git is for)
- Unreachable code after unconditional return/throw
- Unused private methods
- Unused function parameters that are not required by an interface
- Unused variables
- Empty method bodies with no clear reason
- `TODO` comments older than one sprint (either do it or delete it)

**Rule:** If the code is not executing, it should not exist. Version control preserves history — the codebase should only contain code that runs.

## V. Magic Values

Magic numbers and strings make code impossible to understand without context and dangerous to change.

```
// Avoid: what do these mean?
if (status === 3) { ... }
cache.put(key, value, 86400)
if (user.role === 'super-admin') { ... }

// Prefer: named values
if (status === OrderStatus.Shipped) { ... }
cache.put(key, value, CacheTTL.ONE_DAY)
if (user.role === Role.SuperAdmin) { ... }
```

**Rules:**
- Use enums for any finite set of known values
- Use class constants for domain-specific values (`const MAX_RETRY_ATTEMPTS = 3`)
- Use config for environment-dependent values
- The only acceptable "magic" numbers are `0`, `1`, and `-1` in obvious contexts (array indices, increments)

## VI. Hardcoded Strings — User-Facing Text

User-facing text hardcoded directly in templates, components, or controllers is a maintenance problem. Even if the project is not multilingual today, hardcoded strings scattered across hundreds of files make text changes painful and inconsistent.

**What counts as hardcoded strings:**
```html
<!-- Avoid: hardcoded user-facing text -->
<h1>Event erstellen</h1>
<button>Speichern</button>
<p>Keine Ergebnisse gefunden.</p>
<label>E-Mail-Adresse</label>
<span class="text-red-500">Dieses Feld ist erforderlich.</span>
```

**Preferred approaches (in order of preference):**
1. **Translation/i18n strings** via the framework's translation system — ideal for multilingual or text-heavy apps
2. **Component props with defaults** — the component defines default text, callers can override
3. **Constants/Enums** — for status labels, category names, or other structured text

```html
<!-- Prefer: translation strings -->
<h1>{{ t('events.create_title') }}</h1>
<Button>{{ t('common.save') }}</Button>
<p>{{ t('common.no_results') }}</p>

<!-- Or: component with default -->
<Button label="{{ t('common.save') }}" />
<EmptyState message="{{ t('common.no_results') }}" />
```

**Rules:**
- **Button labels, headings, form labels, error messages, success messages, empty states, tooltips** — should never be raw strings in templates
- **Technical strings** (CSS classes, HTML attributes, route names, config keys) are NOT user-facing — these are fine as raw strings
- **Validation messages** should use the framework's validation translation system, not hardcoded strings
- If the project already uses a translation function somewhere — new code MUST follow the same pattern. Mixing translated and hardcoded text is a **Critical** finding.
- If the project has NO translation usage at all — flag hardcoded strings as **Minor** and recommend establishing a pattern

**Checking for violations:**
```bash
# Find hardcoded text in template files (common patterns)
grep -rn ">[A-Z][a-z]" templates/ --include="*.html" | grep -v "{{" | head -20
# Check if project uses translations
find locales/ i18n/ lang/ -name "*.json" -o -name "*.yaml" 2>/dev/null | head -5
grep -r "t(" templates/ | head -5
```

## VII. Cyclomatic Complexity

Deeply nested conditionals are hard to read, hard to test, and prone to bugs in overlooked branches.

**Reduce nesting:**
- Use guard clauses (early returns) to eliminate `else` blocks
- Extract complex conditions into named boolean methods
- Replace `switch` statements with polymorphism or lookup maps
- Use pattern matching or match expressions instead of long `if/elseif` chains

```
// Avoid: nested maze
if user.isActive():
    if user.hasSubscription():
        if subscription.isValid():
            if not subscription.isCancelled():
                return grantAccess()
    return showUpgrade()
return showLogin()

// Prefer: flat and readable
if not user.isActive():
    return showLogin()

if not user.hasValidSubscription():
    return showUpgrade()

return grantAccess()
```

**Target:** No function should have more than 3 levels of nesting. If it does, extract or restructure.

## VIII. Immutability

Mutable state is the #1 source of hard-to-trace bugs. Prefer values that don't change after creation.

**Rules:**
- Use `readonly`/`final`/`const` properties for values set in the constructor
- Use value objects for domain concepts (Money, Email, DateRange) — they are immutable by design
- Avoid setter methods — pass all required data through the constructor
- Don't mutate collection items in place — return new collections from transformations
- If a method must modify state, make it obvious in the name: `cart.addItem()` clearly mutates, `cart.withItem()` clearly returns a new instance

## IX. Consistent Patterns

The same problem should be solved the same way everywhere. Inconsistency forces readers to re-learn patterns they already know.

**Common consistency violations:**
- Some controllers use form requests, others validate inline
- Some features use services, others put logic in controllers
- Some models use accessors, others format data in templates
- Date formatting done differently in different places
- Data access patterns mixed (helper functions vs. direct access)

**Rule:** When you find an existing pattern in the codebase, follow it — even if you think a different approach is slightly better. Consistency beats local optimization. If the pattern truly needs changing, change it everywhere in a dedicated refactoring.

**Custom browser events — name drift across emit/listen:** Custom events (`dispatch('foo')` / `$dispatch('foo')` / `new CustomEvent('foo')` and the matching `@foo`, `x-on:foo`, `wire:foo`, `addEventListener('foo')`, `.window` listeners) couple two sides by a string only — a typo or rename on one side fails silently. When a diff touches an event name, grep BOTH sides across the whole project and reconcile:

```bash
grep -rn "dispatch('eventName'\|@eventName\|addEventListener('eventName'\|CustomEvent('eventName'" resources/ app/
```

A dispatched event with no listener (or vice versa) is a finding. Watch especially for a parallel Alpine path and a plain-JS path listening for the same name — they drift independently.

## X. Comments

Comments that explain *what* the code does are a sign the code should be rewritten. Comments that explain *why* are valuable.

**Delete:**
```
// Get the user
user = User.find(id)

// Check if active
if user.isActive(): ...

// Loop through items
for item in items: ...
```

**Keep:**
```
// We round to 2 decimals here because the payment gateway
// rejects amounts with more precision (discovered in PROJ-1234)
amount = round(total, 2)

// Intentionally not using soft deletes — GDPR requires
// actual removal of personal data after the retention period
user.forceDelete()
```

**Rules:**
- If a comment explains WHAT — rename the variable/function instead
- If a comment explains WHY — keep it, it captures decision context
- Delete commented-out code — Git remembers
- Delete stale comments that no longer match the code
- `@todo` must include a ticket reference or it will never get done

## XI. Error Messages

Error messages are the interface between your system and the person debugging it at 2 AM. Be kind.

```
// Avoid: useless
throw new Exception('Error occurred')
throw new Exception('Invalid input')
log.error('Failed')

// Prefer: specific and actionable
throw new UserNotFoundException('User with ID ' + id + ' not found in tenant ' + tenantId)
throw new InvalidCurrencyException("Currency '" + code + "' is not supported. Allowed: USD, EUR, GBP")
log.error('Payment charge failed', {
    orderId: order.id,
    gateway: 'stripe',
    amount: amount,
    errorCode: e.code,
})
```

**Rules:**
- Include the specific value that caused the failure
- Include context that helps locate the problem (IDs, names, types)
- Suggest what the correct input should look like when possible
- Use structured logging with context objects, not string interpolation in the message

### Swallowed errors on user-facing persistence (FLAG)

`try?`, empty `catch`, or `.catch(() => {})` that silently discards an error is a
finding whenever the operation is UI-relevant persistence the user believes
succeeded: `modelContext.save()` / ORM writes behind a user action, photo/file
writes, exports, sync pushes. The user taps "Speichern", nothing happens, no
feedback — data loss disguised as success.

```swift
// Avoid: user action, silent failure
Button("Speichern") { try? context.save() }

// Prefer: surface the failure (banner/alert) or log + retry path
do { try context.save() } catch { saveFailed = true }
```

Background/best-effort work (cache warmup, prefetch, badge refresh) may swallow
errors deliberately — a short comment stating why is enough to pass. Fire-and-
forget without that comment on a persistence path: flag it.

## XII. Parameter Count

Functions with many parameters are hard to call correctly, hard to read, and a sign of too many responsibilities.

```
// Avoid: parameter explosion
function createUser(
    name: string,
    email: string,
    password: string,
    phone: string?,
    company: string?,
    role: string,
    sendWelcome: boolean,
    referralCode: string?
): User { ... }

// Prefer: parameter object
function createUser(data: CreateUserData): User { ... }
```

**Rules:**
- Maximum 3-4 parameters per function
- If you need more, introduce a DTO or parameter object
- Boolean parameters are almost always wrong — they create hidden branching (`createUser(data, true, false)` tells the reader nothing)
- If a parameter is always the same value at every call site, it should be a class property or config value instead

## XIII. Return Types

A function's return type is a contract. Inconsistent returns break trust and force defensive coding everywhere downstream.

**Rules:**
- Be explicit — every function gets a return type declaration
- Don't return mixed types from the same function (`User|array|false` means the caller needs three code paths)
- Avoid `null` as a return value when possible — use null objects, empty collections, or throw exceptions
- If a method can fail, either throw a typed exception or return a result object — not `null`
- Collection methods should return empty collections, not `null`

```
// Avoid: null ambiguity
function findUser(id: int): User?  // null means "not found" or "error"?

// Prefer: explicit failure
function findUser(id: int): User  // throws UserNotFoundException
function findUserOrNull(id: int): User?  // name makes null explicit
```

## XIV. Temporal Coupling

Temporal coupling means methods must be called in a specific order to work correctly. This is a hidden contract that nothing in the code enforces.

```
// Avoid: order-dependent setup
processor = new PaymentProcessor()
processor.setGateway('stripe')    // must be first
processor.setCurrency('USD')      // must be second
processor.charge(amount)          // breaks if above not called

// Prefer: constructor initialization
processor = new PaymentProcessor(
    gateway: Gateway.Stripe,
    currency: Currency.USD,
)
processor.charge(amount)          // always works
```

**Rules:**
- Required data goes in the constructor — the object is valid from the moment it exists
- If a method requires another method to be called first, combine them or enforce the order internally
- Builder patterns are an acceptable way to handle complex construction with many optional parameters

## XV. Law of Demeter

Don't reach through objects to access their internals. Each object should only talk to its immediate collaborators.

```
// Avoid: chain through internal structure
city = user.getAddress().getCity().getName()
managerEmail = employee.department.manager.email

// Prefer: direct accessors
city = user.getCityName()
managerEmail = employee.getManagerEmail()
```

**Why this matters:**
- `user.getAddress().getCity().getName()` breaks if the address model changes how it stores cities
- The caller now depends on User, Address, AND City — three classes instead of one
- Testing requires mocking an entire object chain instead of a single method

**Rule:** If you chain more than one `->` to access data (excluding fluent/builder APIs), introduce a delegate method on the immediate object.

## PHP Strictness

**`declare(strict_types=1)` is mandatory.** Every PHP file must have this declaration immediately after the opening `<?php` tag. Without it, PHP silently coerces types, masking bugs that strict mode would catch at runtime. Missing `strict_types` on even one file in a project is an inconsistency finding.

**Native return types on all public/protected methods.** Use PHP's native return type declarations instead of relying on PHPDoc alone. This includes Livewire `render()` methods (`: View`), computed properties, and service methods. The type system is only as strong as its weakest declaration.

**Native parameter types over PHPDoc.** Prefer `float|int|string|null $amount` over `@param mixed $amount`. PHPDoc types are invisible to the runtime and to static analysis tools that do not read docblocks.

**`match()` over `switch()` for type-mapping logic.** When mapping values to outcomes (e.g., enum to label, type to sanitizer), `match()` is stricter (no fallthrough, throws on unmatched), more concise, and returns a value directly.

## Blade Template Whitespace

**Whitespace inside `@if`/`@endif` bodies is rendered.** Blade strips the directives but keeps every character between them, including indentation and newlines. Whitespace inside a conditional is therefore never automatically "insignificant": inside `<pre>`, inline-flex gaps, `:empty` selectors, or space-sensitive inline contexts it changes rendering. Do not flag "redundant whitespace" in Blade conditionals as cleanup, and when adding conditionals into space-sensitive markup, keep the body flush.

---

Continued: sections XVI (2026 Type-Safety Patterns) and XVII (Deprecated APIs) live in code-quality-2026.md.
