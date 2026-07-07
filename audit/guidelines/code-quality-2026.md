# Code Quality: 2026 Additions

Fortsetzung von code-quality.md (Abschnitte XVI-XVII). Immer zusammen mit code-quality.md lesen.


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
