# Dimension: Payments

## Look for

Stripe/payment-provider integration correctness: webhook trust, idempotency, entitlement gating,
subscription-state sync, and the handlers a go-live checklist expects. Read `guidelines/payments.md`
in full.

- **Mode-dependent scope.** Your briefing carries `STRIPE_MODE`, a comma list from
  `bin/detect-stripe.sh` (`cashier`, `sdk`, `client`, `hosted`, `http`). Which checks apply and
  which are false positives differs per mode — `guidelines/payments.md` section II has the exact
  matrix. Read it before forming any finding; do not apply the full code-verifiable list uniformly
  across modes.
- **Recurring-aware dashboard gating.** Your briefing also carries `STRIPE_RECURRING`
  (`yes|no|unknown`) from `bin/detect-stripe.sh`. It gates which of the eight dashboard-only points
  below apply — `guidelines/payments.md` section IV has the exact split and the finding text per
  value. Do not assume the integration has subscriptions; check `STRIPE_RECURRING` first.
- **Absences, not diffs.** Most of this dimension's real defects are something MISSING (no
  idempotency key, no webhook signature check, no failed-payment handler). You are given the whole
  payment surface, not just changed lines, because a missing guard never appears in a diff. Read
  every assigned file in full before concluding a guard is absent, and name every plausible
  location you checked in the finding's `files` — an absence finding without named checked
  locations is not evidence, it is a guess.
- **Code-verifiable checks** (may become findings): webhook signature verification, idempotency
  keys on retried/mutating calls, server-side gating of price/plan/entitlement (never trusted from
  the client), subscription status persisted to the DB, payment event logging, handlers for failed
  payment / refund / expired card / upgrade-downgrade, duplicate-charge prevention, currency
  handling, whether payment paths carry any test coverage at all.
- **Dashboard-only checks — NEVER raise these as individual findings.** Test clocks, billing portal
  existence, tax collection, trial rules, dunning retries, receipt emails, failed-webhook alerting,
  and the manual customer-flow test are not derivable from a repo. Four of the eight (tax
  configuration, receipt emails, failed-webhook alerting, the manual customer test) always apply;
  the other four (test clocks, billing portal, trial rules, dunning retries) are subscription
  concerns, gated by `STRIPE_RECURRING` — full list and per-value finding text in
  `guidelines/payments.md` section IV. Read `.claude/stripe-golive.md` in the audited repo if it
  exists. Emit exactly ONE informational `Minor` finding, id `payments-dashboard-unanswered`, whose
  `issue` names how many of the applicable points are answered and when, and lists which are
  unanswered. If the file does not exist, the same single `Minor` finding says so and lists all
  applicable points. Never split this into one finding per point, and never raise it above `Minor`.

**Defect classes calibrated against the go-live checklist:**
- **Forged entitlement:** a webhook handler that grants access/plan/credits without verifying the
  event signature first, or verifies it after the entitlement write.
- **Client-trusted price or plan:** a price id, plan id, quantity, or entitlement value read from
  the client (form field, query param, Stripe.js token payload) and used server-side without
  re-deriving it from the authoritative price/plan table.
- **Missing idempotency key:** a charge, subscription-update, or refund call that can be retried
  (client retry, webhook redelivery, queue retry) without an idempotency key, risking a duplicate
  charge.
- **Silent entitlement drift:** a refund, chargeback, cancellation, or downgrade webhook that is
  received but does not update the stored entitlement/subscription status, leaving access ahead of
  what was actually paid for.
- **Unhandled decline paths:** no handler for `invoice.payment_failed`,
  `customer.subscription.updated` (past_due), or an expired card, leaving a customer in an
  inconsistent access state.
- **Missing webhook route or missing signing secret:** a webhook endpoint absent entirely (`hosted`
  mode), or present but reading a hardcoded value instead of an env-sourced signing secret.

## Severity

`Critical` is money or access moving incorrectly and reachable in production: an unverified webhook
that grants entitlement (anyone can forge a paid status with a crafted POST), or a price/plan taken
from the client and trusted server-side. `Important` is a real gap that needs an unusual
precondition or degrades correctness without granting free access: a missing idempotency key on a
retried call (duplicate charge only on retry, not on every request), or a refund that is received
but not reflected in entitlement. `Minor` is defense-in-depth plus the dashboard-unanswered finding:
a redundant guard, or the go-live checklist's dashboard-only half being unanswered.

## Output

Reply with the specialist schema: `findings[{id, severity, confidence, files, issue, impact}]`
plus `coverage`. Every ID is prefixed `payments-`. Set `coverage` to `COVERAGE: full` or
`COVERAGE: partial | not read: {file1}, {file2}`.
