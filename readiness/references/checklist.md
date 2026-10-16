# Production-readiness checklist

The areas every app is checked against. Each area letter (A to K) is the `Bereich` column in the
app file and the unit an Explore agent gets in its brief.

## Contents

- Rating scale
- Relevance rules
- A. Auth and access
- B. Data and database
- C. Security
- D. Operations
- E. Tests
- F. Billing
- G. Integrations and API
- H. AI features
- I. UX
- J. Code and organisation
- K. Legal: privacy policy and imprint
- Native and device-backend additions

## Rating scale

The status values are contract identifiers shared with earlier collections; keep them verbatim even
when the report is written in another language.

| Status | Meaning |
|---|---|
| `OK` | Implemented, evidence in the code (file:line) |
| `Teilweise` | Present, but with a concrete gap (name it) |
| `Fehlt` | Not present and relevant for this app |
| `N.a.` | Not relevant for this app (one-line reason) |

A `Fehlt` or `Teilweise` without a location is not a finding. Name the file where the fix would go,
or the file that proves the absence (for example the deploy script without a test step).

## Relevance rules

Relevance follows the product, not the checklist. Decide N.a. before dispatching agents, so no
agent spends turns on it.

- Consumer apps without enterprise customers: no SSO, SAML, SCIM, SOC 2, HIPAA, second region,
  public versioned API, API keys, sandbox.
- Solo operation: no on-call rota or postmortem process, but every alert must reach the one person.
- Payment through a hosted checkout (Stripe Checkout, StoreKit, Play Billing): PCI scope is N.a.;
  receipt verification and webhook handling stay relevant.
- No LLM calls in the code: section H is N.a.
- Device-authenticated apps (App Attest, device tokens, no accounts): passwords, MFA, sessions,
  impersonation are N.a.; device binding, token rotation and per-device deletion become relevant.
- Local tools without a server or users (menu bar utilities, CLIs, static sites): skip the app
  entirely and list it under "Nicht geprüft" in the index.
- A light check (one agent, sections A, C, D, H, K only) is enough for small apps with few users and
  no payments.

## A. Auth and access

- E-mail normalisation: plus addresses, case-insensitive uniqueness
- Password reset links expire and are single-use
- MFA with recovery codes; mandatory for admins
- Session timeout; "sign out all sessions"; password change or reset ends other sessions
- SSO, SAML, SCIM (enterprise only)
- Roles beyond admin and everyone else
- IDOR: changing an ID in a URL or request body exposes nothing
- Tenant isolation (every query scoped)
- Impersonation with an audit trail
- Rate limits on login, reset, MFA, PIN
- Lockouts without permanent locks
- Admin panel and support tools exist and are protected

## B. Data and database

- Designed schema, foreign keys, constraints
- Migrations forward and backward; versioned (also for SQLite stores)
- Migrations without long table locks
- Indexes on hot queries
- Connection pooling
- Nightly backups, off-site
- Restore tested (drill log with date), point-in-time recovery where it matters
- Soft deletes or a trash where users can lose work
- Server-side validation
- Time zones stored and displayed correctly
- Apostrophes, emoji, accents, RTL in names and text
- Money as integer minor units; currency, rounding and tax rules pinned by tests
- Idempotency keys on payments and job creation; double-submit guard
- Pagination on every list
- Export (user data, accounting data)
- Import of old or foreign CSVs (encodings, delimiters)
- Retention with deletion code per data type
- GDPR deletion across all tables, files, third parties, backups, logs; per device for apps without
  accounts
- Audit trail, including read access to sensitive data
- Cache invalidation

## C. Security

- Secrets not in code, repo history or chat; `.env` ignored
- Key rotation possible without downtime
- Packages exist and are the intended ones (no typosquats); lockfile committed
- Dependency scan (`composer audit`, `npm audit`, `bun audit`, Dependabot) and a deploy gate on it
- Input sanitising; SQL injection, XSS, CSRF, the OWASP top ten
- Uploads: size limit, MIME plus magic bytes, not executable, stored outside the web root
- CORS only where a cross-origin API exists
- Security headers (CSP, HSTS, X-Frame-Options or frame-ancestors, Referrer-Policy)
- Encryption in transit and at rest where the data warrants it
- Least privilege for services, deploy users and agents
- Logs free of passwords, tokens, card data, PII
- Pentest (or a documented decision not to)
- Disclosure process: `/.well-known/security.txt`
- Plan for a stolen laptop (keys, sessions, repo access)
- PCI scope
- Data residency (EU)
- Access reviews for accounts with production access

## D. Operations

- Dev, staging and prod built the same way
- Infrastructure as code or at least scripted
- Deploy runs tests first (or the ship gate does, see `lessons.md`)
- Rollback path that has been used
- Zero-downtime deploy, or a documented maintenance window
- Feature flags
- Autoscaling (usually N.a. for single-server apps)
- CDN for static assets
- DNS, TLS and renewal monitored
- Queues; retries with backoff; dead-letter handling; failed jobs reported
- Cron runs exactly once (no double scheduling across servers or processes)
- Caching
- SPF, DKIM, DMARC; bounces and complaints handled (suppression list)
- Storage lifecycle rules
- Cost alerts, especially for AI and cloud usage
- DR plan tested
- Structured logs
- Error tracking with grouping (Sentry or equivalent)
- External uptime checks; heartbeats for scheduler, jobs and backups
- Alerts reach a human
- Dashboards; tracing where requests cross services
- Runbooks; postmortems; status page (usually N.a. for small apps)

## E. Tests

- Unit tests that encode domain knowledge, not getters
- Integration tests for third-party APIs (fixtures of real payloads)
- End-to-end tests for signup, checkout and the core flows
- Load test (usually N.a. below a few hundred concurrent users)
- Realistic test data without production data
- Regression tests for past bugs
- Old devices and OS versions (native)
- Accessibility (axe, VoiceOver, Dynamic Type)

## F. Billing

- Subscriptions, upgrade, downgrade, proration
- Payment failure and dunning (customer is told)
- Invoices with PO number where B2B customers need it
- VAT handling
- Refunds, including partial refunds
- Usage metering
- Special contracts
- Revenue reconciliation against the payment provider

## G. Integrations and API

- Incoming webhooks verify signatures
- Webhooks are idempotent, retried, and failures are logged and visible
- Versioned API, API keys, API rate limits (only with a public API)
- Third-party API changes its format: parsing fails loudly, not silently
- OAuth token refresh
- Sandbox for integrators

## H. AI features

- Prompt injection: untrusted content fenced, tools limited
- Customer data not sent to providers beyond what is needed; PII redacted
- Spend cap per user and a global daily cap, plus a cost alert
- Evals for the prompts that matter
- Fallback when the provider is down
- Plan for model deprecation (model id from config, not hardcoded)
- Prompt and output logs free of forbidden data
- Output check before content reaches a vulnerable user (children, health)
- Human approval for irreversible actions

## I. UX

- Slow network behaviour
- Empty, loading and error states
- Error messages that say what to do
- Forms keep input after a validation error
- Mails render in all major clients
- Notifications can be switched off per channel; one-click unsubscribe
- Undo for destructive actions
- Keyboard and screen reader support
- Translations with locale-aware date and number formats
- Back button works

## J. Code and organisation

- Readable code; code review or an equivalent gate
- Branching model
- Monthly dependency updates; framework upgrades on time
- Dead code; very large files (name them with line counts)
- Architecture decisions documented
- README gets a new developer running in under an hour, and its claims are true
- Handover documentation
- Admin panel; support tools
- Changelog for customers
- Terms of service match what the code does (privacy policy: section K)
- Accounts, domains, repos owned by the company, not a person
- Bus factor above one

## K. Legal: privacy policy and imprint

Relevant for every app with users in the EU, including free and private ones that are publicly
reachable. Check the source of the pages (route, view, static file, CMS export) and every place
that should link to them.

- Imprint (Impressum, § 5 DDG) exists with name, postal address, e-mail, and for businesses the
  register and VAT id; reachable in one click from every page, including login, error and mail
  footers
- Native apps link imprint and privacy policy in the app (settings or about screen) and in the
  store listing
- Privacy policy (Datenschutzerklärung) exists and is reachable in one click from every page, from
  the signup form and from the app
- Every processor the code actually calls is named (hosting, mail, payment, error tracking,
  analytics, AI providers, push, CDN, fonts); grep the code and the dependency manifests for
  third-party hosts and SDKs and compare against the policy text
- Purpose and legal basis per processing; third-country transfers (US providers) with their basis
- Retention periods in the policy match the deletion code (section B), and the deletion and export
  rights described are actually implemented
- Data processing agreements (AV-Vertrag) with each processor, at least listed
- Consent banner only where non-essential cookies, tracking or external embeds load; nothing
  non-essential loads before consent; no banner needed when nothing non-essential exists
- Fonts, maps, videos and scripts from third-party hosts either self-hosted or behind consent
- App Store privacy labels, Play data-safety form and privacy manifest match the policy
- Date of the policy is current after the last change to data flows
- Client projects: the client is named as controller, not the developer

## Native and device-backend additions

For iOS/macOS apps with their own backend (Bun/Hono, Workers):

- Device authentication (App Attest, DeviceCheck) with nonce and counter checks
- Receipt or JWS verification on the server, not only on the device
- Store server notifications handled, including refunds and revocations
- Per-device data deletion script or endpoint
- Backend migrations versioned
- App works offline or degrades clearly
- Minimum OS version and old-device behaviour
- Privacy manifest and App Store privacy labels match the data flows
