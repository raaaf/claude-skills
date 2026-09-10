---
applies_to: [Ss]tripe|[Cc]ashier|[Bb]illing|[Pp]ayment|[Cc]heckout|[Ss]ubscription|[Ii]nvoice|[Ww]ebhook|[Cc]harge
priority: mandatory
---
# Payments Guidelines

Payment code fails silently. A missing signature check does not throw, it just trusts a forged
request; a missing idempotency key does not error, it just double-charges on the second retry. The
rule for this dimension is the same rule as security, aimed at money instead of data: every guard
that should exist is checked for, not assumed, and a guard a framework already provides is not
flagged as missing.

## Contents
- I. The Go-Live Checklist, Split by Verifiability
- II. Mode Matrix: What Applies per Integration Style
- III. Code-Verifiable Checks in Detail (Laravel/PHP and Node)
- IV. The Eight Dashboard-Only Points
- V. No-False-Positive Rules

## I. The Go-Live Checklist, Split by Verifiability

The full checklist a payments go-live is measured against: verify webhook signatures, handle failed
payments, handle refunds, handle upgrades and downgrades, add idempotency keys, gate features
server-side, sync subscription status to the DB, test with Stripe test clocks, add a billing portal,
email receipts, log every payment event, handle expired cards, add tax collection, set trial rules,
prevent duplicate charges, handle multiple currencies, build a working cancel flow, retry dunning
emails, alert on failed webhooks, test the whole flow as a customer.

Roughly half of these are answerable from source. The other half live in the Stripe Dashboard and
cannot be derived from a repo — do not guess at them, do not infer them from the absence of dashboard
config in code, and do not treat their absence from the codebase as evidence either way. Section IV
lists the dashboard-only half exactly; everything else is code-verifiable.

## II. Mode Matrix: What Applies per Integration Style

`STRIPE_MODE` is a comma list emitted by `bin/detect-stripe.sh`. A repo can carry more than one
value (e.g. `sdk,client`). Apply each mode's rules independently; do not average them.

**`cashier` (Laravel Cashier).** Cashier already provides webhook signature verification (its own
middleware, `Cashier::webhookHandler` / `Http\Middleware\VerifyWebhookSignature`), subscription
status persistence (`subscriptions` / `subscription_items` tables written by Cashier's own webhook
controller), and a billing portal (`redirectToBillingPortal`). Flagging any of those three as
missing in a Cashier app is a false positive. What still applies:
- Is the Cashier webhook route actually registered and reachable (`routes/api.php` or equivalent,
  not commented out, not behind an auth middleware that blocks Stripe's servers)?
- Is `CASHIER_WEBHOOK_SECRET` / `STRIPE_WEBHOOK_SECRET` read from env, not hardcoded?
- Server-side gating of any feature/entitlement the app layers on top of Cashier's own state.
- Idempotency on any direct SDK call the app makes alongside Cashier (a manual `Charge`/
  `PaymentIntent` create outside the subscription flow).
- Every handler Cashier does not provide out of the box: app-specific reactions to
  `invoice.payment_failed`, refund-driven entitlement changes, expired-card UX.

**`sdk` (server SDK used directly, no Cashier-style wrapper).** The full code-verifiable list in
Section III applies without exception. This is the mode where a missing `Webhook::constructEvent`
(PHP) / `stripe.webhooks.constructEvent` (Node) or a missing idempotency key is a real, high-
confidence finding.

**`client` (Stripe.js / Elements only, no server SDK calls beyond confirming a PaymentIntent).** The
dominant real defect is a price, plan id, quantity, or entitlement value that originates in the
browser (a hidden form field, a query param, a value read off the Elements token) and is trusted
server-side without being re-derived from the authoritative price table. Prioritize that check over
webhook/idempotency checks, which are usually out of scope for pure client-only integrations.

**`hosted` (Payment Links or hosted Checkout, no SDK in the repo).** Almost nothing here is code-
verifiable — there is no application code processing the payment. Say so rather than manufacturing
findings. Check only two things: does a webhook receiver exist at all, and is entitlement granted
server-side (from the webhook) rather than from a client-side redirect/success-URL parameter.

**`http` (raw calls to `api.stripe.com`, no official SDK).** Idempotency (`Idempotency-Key` header)
and signature verification are almost always missing in hand-rolled HTTP integrations — check both
explicitly. Also check error handling on non-2xx responses: a raw HTTP call that does not branch on
the response status can treat a declined or errored charge as successful.

## III. Code-Verifiable Checks in Detail

**Webhook signature verification.** Laravel/PHP: `\Stripe\Webhook::constructEvent($payload,
$sigHeader, $secret)` (or Cashier's own middleware in `cashier` mode) must run before the event
payload is trusted for any state change. Node: `stripe.webhooks.constructEvent(body, sig, secret)`
against the *raw* request body — a body already parsed as JSON by a framework's default body-parser
invalidates the signature, so check that the route opts out of JSON parsing for the webhook path.

**Idempotency keys.** Laravel/PHP: `Stripe::setApiKey(...)` calls that create a charge, PaymentIntent,
or subscription pass `['idempotency_key' => ...]` in the options array. Node: `{idempotencyKey:
...}` in the request options. The key must be derived from something stable across retries (an order
id, an invoice id), not regenerated per call (`uniqid()`/`Date.now()` defeats the purpose).

**Server-side gating.** The entitlement check (does this user have access to this feature/plan) runs
against a value stored server-side (DB column, cached subscription status) at the point of use, not
against a value passed in the request or read from a client-side store/session that mirrors
Stripe state without re-verifying it.

**Subscription status sync.** A webhook handler for `customer.subscription.created/updated/deleted`
and `invoice.payment_failed` writes the resulting status to the app's own DB (not just Stripe's).
An app that queries Stripe live on every request instead is a correctness/latency concern, not a
payments-dimension finding here.

**Payment event logging.** Every payment-affecting webhook handler writes a log line or an audit
record (event type, event id, outcome) before or immediately after acting on it — silent handlers
make disputes and support tickets unresolvable.

**Failed payment / refund / expired card / upgrade-downgrade handlers.** Each of
`invoice.payment_failed`, `charge.refunded` (or `refund.created`), `customer.subscription.updated`
(price change), and a card-expiry signal (`invoice.upcoming` with an expiring card, or
`payment_method.updated`) has a corresponding handler that changes app state, not just a webhook
route that 200s and does nothing.

**Duplicate-charge prevention.** Beyond idempotency keys on the Stripe call itself: a "buy now"
or checkout submit handler is debounced/locked server-side (a unique constraint, a pending-order
lock) so a double form submission cannot create two orders even before Stripe is called.

**Currency handling.** Amounts sent to Stripe are in the smallest currency unit (cents, not a float)
and the currency code is not hardcoded when the app supports more than one — check for a stray
`* 100` cast that is skipped for a specific currency, and for a hardcoded `'usd'` in a codebase that
otherwise supports multiple currencies.

**Test coverage.** Whether any test in the repo exercises a payment path at all (webhook handler,
checkout flow, entitlement gate). Absence is a finding on its own only when nothing in the payment
surface has coverage; partial coverage is not flagged per-path here — that granularity belongs to
`code_quality`.

## IV. The Eight Dashboard-Only Points

These are answered once by the user and stored in the audited repo at `.claude/stripe-golive.md`.
Never raise these individually; see the agent file's single `payments-dashboard-unanswered` rule.

Four apply regardless of whether the integration bills recurringly:

1. Tax collection (Stripe Tax or equivalent) is configured.
2. Receipt emails are enabled and configured.
3. Alerting exists for failed/undelivered webhooks (Stripe Dashboard or an external monitor).
4. The whole flow (signup, payment, cancel, refund) has been manually tested as a customer.

Four are subscription concerns, gated by `STRIPE_RECURRING` from `bin/detect-stripe.sh`:

5. Stripe test clocks used to test subscription lifecycles before go-live.
6. A billing portal is configured and reachable by customers.
7. Trial rules (length, card-required-or-not, auto-convert behavior) are set.
8. Dunning email retries are configured for failed payments.

**Gating by `STRIPE_RECURRING`:**
- `yes`: all eight points apply, as above.
- `no`: only points 1-4 apply. The `payments-dashboard-unanswered` finding's `issue` must state
  explicitly that points 5-8 were excluded because the integration has no recurring billing, so a
  reader can tell "checked and not applicable" apart from "forgotten". Do not silently drop them
  from the finding text.
- `unknown`: all eight points apply, but points 5-8 are marked conditional in the finding's `issue`,
  with one line noting they apply only if the integration actually bills recurringly and that the
  repo does not settle it either way.

This stays ONE `Minor` finding with id `payments-dashboard-unanswered` in every case; never split it
per point.

## V. No-False-Positive Rules

- **Check whether a framework wrapper already provides the guard before flagging its absence.**
  Cashier, or an equivalent billing library, commonly provides webhook verification, subscription
  persistence, and a billing portal out of the box (Section II). Confirm the library's own code
  before concluding the app is missing something the library already does for it.
- **Check the whole file and its siblings for the guard before concluding it is missing.** A
  signature check or idempotency key placed in a shared service/trait/middleware and called from the
  handler you are reading is not absent just because it is not inline at the call site.
- **A test file that mocks Stripe is not a missing-guard finding.** Stripe SDK calls stubbed/mocked
  in a test file are expected test isolation, not evidence that production code skips the guard.
- **A webhook secret read from env is correct.** Only a hardcoded secret (a literal `whsec_...` or
  `sk_...` string in source) is a finding; `env('STRIPE_WEBHOOK_SECRET')` /
  `process.env.STRIPE_WEBHOOK_SECRET` is the expected pattern, not a finding on its own.
- **Dashboard-only points never become individual findings**, at any severity, and never above
  `Minor` even as the single combined finding (Section I, and the agent file's Output contract).
