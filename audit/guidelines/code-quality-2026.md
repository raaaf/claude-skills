# Code Quality: 2026 Additions

Continuation of code-quality.md (sections XVI-XVIII). Always read together with code-quality.md.


## XVI. 2026 Type-Safety Patterns

### Branded / Nominal Types (TypeScript)

Make `UserId`, `OrderId`, `Email` distinct from `string` at the type level so `getUser(orderId)` becomes a compile error:

```typescript
type Brand<T, B> = T & { readonly __brand: B };
type UserId = Brand<string, 'UserId'>;
type OrderId = Brand<string, 'OrderId'>;

function asUserId(s: string): UserId { return s as UserId; }
function getUser(id: UserId) { /* ... */ }

const orderId = asOrderId('ord_123');
getUser(orderId); // Compile error
```

Apply to IDs (most common bug), money amounts, time durations, validated/unvalidated input.

### Result / Either over throwing for expected failures

Throwing is for bugs and unrecoverable state. For expected failures (validation, not-found, lock contention), return a result:

```typescript
type Result<T, E> = { ok: true; value: T } | { ok: false; error: E };

function parseDate(input: string): Result<Date, 'invalid' | 'out-of-range'> {
  const d = new Date(input);
  if (isNaN(d.getTime())) return { ok: false, error: 'invalid' };
  if (d.getFullYear() < 1900) return { ok: false, error: 'out-of-range' };
  return { ok: true, value: d };
}
```

Library: `neverthrow` (TS), `Result` in Rust, `Either` in fp-ts. Callers cannot forget to handle the error case — types force it.

### Pure functions by default

A function that takes only its arguments and returns a value is testable in 3 lines, reusable, and composable. A function that reads from globals or mutates external state is none of these. Default to pure. Side effects belong at the edge (controllers, command handlers) where they are obvious.

Audit signal: a "service" method that does logging, DB writes, email sending, AND business logic in one function. Split into pure-business-logic + impure-side-effects.

### Discriminated Unions over flags

```typescript
// BAD — invalid states representable
interface Order {
  status: string;
  paidAt?: Date;
  cancelledAt?: Date;
  refundReason?: string;
}

// GOOD — type system enforces valid combinations
type Order =
  | { status: 'pending'; createdAt: Date }
  | { status: 'paid'; paidAt: Date }
  | { status: 'cancelled'; cancelledAt: Date; reason: string };
```

Eliminates "what if both paidAt and cancelledAt are set" bugs at compile time.

### Exhaustive switch with never

```typescript
function label(status: Order['status']): string {
  switch (status) {
    case 'pending': return 'Pending';
    case 'paid': return 'Paid';
    case 'cancelled': return 'Cancelled';
    default:
      const _exhaustive: never = status;
      throw new Error(`unhandled: ${status}`);
  }
}
```

Add a new variant to `Order['status']` and TypeScript points to this `never` line. No forgotten case.

### PHP 8.3+ Specific

- **Readonly properties** (PHP 8.1+) for value objects. `public readonly string $email` — set in constructor, never mutated.
- **Enums with methods** (PHP 8.1+) replace stringly-typed constants. Add `label()`, `color()`, `permission()` methods to the enum, not a separate helper.
- **`@throws` PHPDoc enforcement** via PHPStan strict mode catches uncaught checked-throw paths.
- **Asymmetric visibility** (PHP 8.4+): `public protected(set) string $name` allows external read but internal-only write.
- **`#[\Override]` attribute** (PHP 8.3+) on overridden methods catches typo-based override failures at autoload time.

### Audit Signal

When reviewing typed code, ask: "If I deleted this `as any` / `mixed` / `Object` cast, would TypeScript / PHPStan find a real bug or just complain?" If real bug → fix it. If false positive → narrow the type instead of casting.

## XVII. Deprecated APIs (Web / PHP / Node)

Gleiche Verifikations-Regel wie native-mobile.md VIII: Deprecation-Findings IMMER mit Confidence-Label; bei medium/low erst via context7/Doku verifizieren, sonst nicht melden. Nie ohne Verifikation auto-"modernisieren".

Stabile Beispiele (Muster, keine erschoepfende Liste):

| Veraltet | Ersatz |
|---|---|
| PHP: `utf8_encode()` / `utf8_decode()` | `mb_convert_encoding()` (removed in PHP 9) |
| PHP: dynamische Properties ohne `#[AllowDynamicProperties]` | explizite Properties (deprecated seit 8.2) |
| PHP: `${var}` String-Interpolation | `{$var}` (deprecated seit 8.2) |
| Laravel: `$dates` Property | `$casts` mit `datetime` |
| Node: `url.parse()` | `new URL()` |
| Node: `Buffer()` Konstruktor | `Buffer.from()` / `Buffer.alloc()` |
| JS: `document.execCommand()` | Clipboard API / `contenteditable`-Alternativen |
| JS: `unload`-Event | `pagehide` / `visibilitychange` |

Schweregrad: Minor solange funktional; Important wenn Removal in der naechsten Major-Version der im Projekt genutzten Runtime ansteht (PHP-Version aus composer.json, Node aus engines lesen).

## XVIII. Tooling That Audits Other Code Needs Its Own Evidence

A script whose job is to decide, route, score or gate has a failure mode ordinary code does not: when
it is wrong, it produces a confident answer instead of an error, and nothing downstream contradicts
it. Every long-lived defect found so far in this repo's own `audit/bin/*.sh` and `audit/evals/*.sh`
sat there for months and was found by accident, never by a check.

Concretely, three that shipped and stayed:

- a routing floor that left four dimensions to a triage step that had meanwhile become opt-in, so
  those dimensions ran on no default audit at all
- a scoring rule that matched dimension names without normalizing separators, so a whole class of
  false positives could never be counted
- an invocation that appended human instructions to a slash command, which the skill then parsed as
  its argument

None of these threw. All three reported success.

**Scope, so this does not turn into a test-coverage complaint.** This applies to scripts that
*decide* something: routing, gating, scoring, dispatch, matching. It is not a general call for tests,
and "this file has no tests" is never a finding on its own in this repo. The question is narrower:
does the specific decision this script makes have any evidence behind it other than someone having
read the code.

When a diff touches a script of this class, ask for evidence rather than for review:

- **Does a deterministic check exercise the decision?** A fixture, a golden output, a `--dry-run`
  that prints what would happen. "I read it and it looks right" is not evidence for a router.
- **Does the failure mode announce itself?** A skipped dimension, a swallowed timeout, a silently
  unscored fixture all look identical to a clean run. Anything that drops work must say so on
  stdout and be counted in the summary.
- **Do the two directions agree?** If the tool maps A to B (fixture to expected file, dimension to
  worker, category to config), check both directions and report orphans on each side. One-way
  matching hides exactly the entries that never fire.
- **Is the contract asserted where it is used, not only where it is defined?** An agent file that
  says it needs a specific subagent type does not enforce it; the dispatch site does. Grep every
  dispatch site when the definition changes.

Severity: a routing, gating or scoring defect that silently drops work is `Important` even when the
code around it is clean, because the loss is invisible in the output. It is `Critical` only when it
lets something through a safety gate.
