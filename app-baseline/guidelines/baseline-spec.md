# App Baseline Spec

Single source of truth for what every app (web or mobile) must have before it counts
as production-grade. Consumed by two skills:

- `/app-baseline` — interactive: captures the charter for a new app, scaffolds missing pieces.
- `/baseline-check` — autonomous: checks an existing app against this spec, reports gaps.

Scope boundary: this spec owns **infra, process, and release** dimensions — the things a
code diff audit cannot see. Code-level quality (a11y in markup, security in code, UI
consistency, performance, docs drift) is owned by `/full-audit` and is delegated, never
duplicated here.

## TOC

1. [How to read this spec](#how-to-read-this-spec)
2. [D1 Positioning charter](#d1-positioning-charter)
3. [D2 Design foundation](#d2-design-foundation)
4. [D3 Accessibility process](#d3-accessibility-process)
5. [D4 Quality gates](#d4-quality-gates)
6. [D5 Security posture](#d5-security-posture)
7. [D6 Deployment and release](#d6-deployment-and-release)
8. [D7 Dependency currency](#d7-dependency-currency)
9. [D8 Backups and restore](#d8-backups-and-restore)
10. [D9 Observability](#d9-observability)
11. [D10 Legal and privacy](#d10-legal-and-privacy)
12. [D11 Documentation](#d11-documentation)
13. [D12 Environments and data](#d12-environments-and-data)
14. [Severity mapping](#severity-mapping)
15. [Delegation to /full-audit](#delegation-to-full-audit)

## How to read this spec

Each dimension lists:

- **Must** — absence is a finding (Critical or Important, see severity mapping).
- **Should** — absence is a Minor finding.
- **Web / Mobile** — platform-specific interpretation. "Mobile" means native iOS/Android
  or cross-platform (React Native, Flutter). Platform comes from `detect-framework.sh`
  (`PLATFORM=web|native|cross`).
- **Verify** — how `/baseline-check` establishes the fact. Prefer deterministic checks
  (file exists, command exits 0) over LLM judgment. A check that cannot be verified
  is reported as `UNVERIFIED`, never assumed to pass.

## D1 Positioning charter

The app can state what it is, for whom, and what feeling it transmits. This drives
design, copy, and scope decisions; without it, every later dimension drifts.

**Must**

- A `BASELINE.md` (or equivalent section in README) containing:
  - Three keywords the app should transmit (e.g. "ruhig, schnell, verlässlich").
  - One-sentence value proposition.
  - Target user in one sentence.
- The three keywords are referenced by the design foundation (D2) — they are not
  decoration.

**Should**

- Explicit out-of-scope list (what the app deliberately does not do).

**Verify**: file exists and contains the three sections. Keyword-to-design linkage is
an LLM check (one sentence of reasoning, not a deep audit).

## D2 Design foundation

**Must**

- A design system or token layer is the base for all UI. No raw, unstyled platform
  elements where a component exists.
- Dark mode supported (or a documented decision not to).
- Layout adapts: no fixed-width assumptions.

**Web**

- Design tokens as CSS custom properties (or the framework's token system).
- Responsive via container queries / fluid layout, not device-width breakpoint forks.

**Mobile**

- Dynamic Type / font scaling respected.
- Safe areas respected on every screen.
- Native platform components (or the design system's wrappers), not lookalikes.

**Should**

- Tokens documented (where they live, how to add one).
- Motion/animation follows a single defined easing/duration scale.

**Verify**: token file/system exists (deterministic). Coverage and quality are
delegated to `/full-audit` dimensions 7 (typography) and 8 (ui-design).

## D3 Accessibility process

Code-level a11y findings belong to `/full-audit` dimension 6. This dimension checks
that a11y is a **process**, not an afterthought.

**Must**

- Automated a11y check wired into CI or the audit flow (axe, Lighthouse a11y,
  or platform equivalent).
- Evidence of at least one manual pass: keyboard-only (web) or
  VoiceOver/TalkBack (mobile), noted in `BASELINE.md` or a test log.

**Web**: target WCAG 2.2 AA.
**Mobile**: contrast, touch target sizes (44pt/48dp), screen reader labels.

**Should**

- Reduced-motion preference respected.

**Verify**: CI config or audit hook references an a11y tool (deterministic grep).
Manual-pass evidence is a file check.

## D4 Quality gates

"Everything tested" is the wrong target; **critical paths gated in CI** is the right
one. Coverage numbers are not a Must.

**Must**

- A test suite exists and runs green locally (`test-command` documented).
- Critical user paths (auth, payment, the app's core loop) each have at least one test.
- CI runs lint + typecheck + tests on every push and **blocks merge on red**.
- A pre-push quality gate exists locally (e.g. the `/audit` marker flow, husky, or
  equivalent).

**Web**: unit (Vitest/Jest/PHPUnit) + at least one E2E flow (Playwright) for the
core path.
**Mobile**: unit (XCTest/JUnit) + at least one UI test for the core path.

**Should**

- Test pyramid shape: many unit, some integration, few E2E. Not inverted.
- Flaky tests quarantined, not deleted or retried into green.

**Verify**: test command exits 0 (deterministic). CI config exists and contains
test + lint steps (deterministic grep). Blocking-on-red is a repo/branch setting —
check via `gh api` where possible, else UNVERIFIED.

## D5 Security posture

Code-level vulnerabilities belong to `/full-audit` dimension 2. This dimension checks
the **posture around** the code.

**Must**

- No secrets in the repo or its history-visible files. Secrets live in a secret
  store / CI secrets / `.env` excluded by `.gitignore`.
- Dependency vulnerability scan runs regularly (`check-outdated.sh --security-only`,
  `npm audit`, Dependabot, or equivalent).
- Auth/session handling uses the platform's standard mechanism, not homegrown crypto.

**Web**: HTTPS enforced, CSP present, cookies `Secure`/`HttpOnly`/`SameSite`.
**Mobile**: ATS not globally disabled (iOS), secrets in Keychain/Keystore, no
sensitive data in plain-text storage or logs.

**Should**

- Security headers scored (Mozilla Observatory or equivalent) for web.
- Signing keys/certificates stored outside the repo with documented rotation.

**Verify**: `.gitignore` covers `.env` (deterministic). Secret scan over tracked files
(deterministic, report as `file:line` + type only, never reproduce the value).
Vuln scan: run `check-outdated.sh --security-only`.

## D6 Deployment and release

**Must**

- Deployment is fully automated: one command or one push, no manual file copying.
- Reproducible: the same commit always produces the same artifact.
- **Reversible: a rollback path exists and is documented.** An unrollbackable deploy
  is a Critical finding.
- Secrets are injected at deploy time, never committed.
- A staging/preview target exists before production (or a documented decision why not).

**Web**: CI/CD to server (SSH/rsync, container, or platform deploy). Health check
after deploy.
**Mobile**: Fastlane (or equivalent) drives build + signing + TestFlight/Play upload.
Signing is automated, not "Xcode on someone's laptop". Versioning/build numbers
bumped automatically.

**Should**

- Deploy notifications (success/failure visible without asking).
- Zero-downtime strategy for web (atomic symlink switch, rolling, or platform-managed).

**Verify**: deploy config/workflow file exists (deterministic). Rollback path is a
documentation check. Actual deploy execution is never triggered by `/baseline-check`.

## D7 Dependency currency

"Always latest" is explicitly **not** the rule — bleeding edge breaks things. The rule
is: supported, patched, reviewed.

**Must**

- Runtime (Node/PHP/Swift toolchain/Kotlin/...) is a supported, non-EOL version.
- Security patches applied promptly (see D5 scan).
- No dependency pinned to a version with a known unpatched CVE.

**Should**

- Scheduled dependency review (monthly or per-release) for outdated majors.
- Lockfile committed and honored in CI (`npm ci`, not `npm install`).

**Verify**: `check-outdated.sh` (already exists in the audit toolchain) — vulnerability
part maps to Must, outdated-majors part maps to Should.

## D8 Backups and restore

A backup without a tested restore is not a backup.

**Must**

- Backups of all persistent data run automatically (cron, platform snapshot, managed
  DB backup).
- At least one **restore has been tested** and the result noted (date + outcome in
  `BASELINE.md` or ops doc).
- Backup destination is off-host (not only on the machine that could die).

**Web**: DB dump + uploaded-files sync, offsite.
**Mobile**: usually server-side (the app's backend owns this); on-device-only data
needs an explicit statement (iCloud/Auto Backup or "ephemeral by design").

**Should**

- Retention policy defined (how many, how long).
- Backup failure alerts (silent-failure is the common death).

**Verify**: backup mechanism config exists (deterministic where reachable). Restore
test is a documentation check — no note means Must failed, regardless of whether
backups "probably work".

## D9 Observability

Without this, production errors are discovered by users, not by tooling.

**Must**

- Error tracking wired (Sentry or equivalent) for production.
- Uptime monitoring with alerting for anything with a server component.

**Web**: server + client error tracking, uptime ping on the public URL.
**Mobile**: crash reporting (Crashlytics/Sentry), release-health visibility.

**Should**

- Structured logs with levels; no `console.log` debugging left in production
  (overlaps `/full-audit` code-quality — the baseline check only verifies the
  tooling exists).
- One dashboard or endpoint that answers "is it healthy right now".

**Verify**: SDK/config presence (deterministic grep for the tracking DSN pattern —
report presence only, never the DSN value).

## D10 Legal and privacy

Not optional for apps operated from Germany.

**Must**

- Impressum and Datenschutzerklärung reachable (web) or linked in-app (mobile).
- Consent management for any non-essential tracking; none needed if there is no
  tracking (the better default).
- Personal data inventory: what is stored, where, how long (one section in
  `BASELINE.md` suffices for small apps).

**Mobile additionally**: App Store privacy labels / Play Data safety section matches
what the app actually does.

**Should**

- Data deletion path for user requests (even if manual).

**Verify**: pages/links exist (deterministic). Label-vs-reality match is an LLM check.

## D11 Documentation

**Must**

- README answers: what is this, how to run locally, how to test, how to deploy.
- Every required ENV variable documented (name + purpose, never values).
- `BASELINE.md` from D1 exists and is current.

**Should**

- ADRs (or a decisions section) for choices a future maintainer would question.
- Doc drift is `/full-audit` dimension 11 — delegated.

**Verify**: README section check (deterministic headings grep + short LLM sanity pass).

## D12 Environments and data

**Must**

- Local, staging (if D6 requires one), and production are configuration-separated —
  same code, different env.
- Database migrations are versioned and reversible (down-migrations or documented
  restore-based rollback).
- `.env`-style files are git-ignored; a committed `.env.example` documents the shape.

**Should**

- Seed data or fixtures for local development.
- Production data never copied to local without anonymization.

**Verify**: `.env.example` exists, `.gitignore` covers env files, migration directory
exists (all deterministic).

## Severity mapping

| Finding | Severity |
|---|---|
| Missing Must in D5, D6 (rollback), D8 (restore test) | Critical |
| Missing Must elsewhere | Important |
| Missing Should | Minor |
| Verify impossible (no access, no tooling) | UNVERIFIED — listed separately, never silently passed |

A dimension with a documented decision ("no dark mode because X", "no staging because
Y") is not a finding — documented tradeoffs are respected, same rule as `/audit`'s
`DECIDED_TRADEOFFS`.

## Delegation to /full-audit

`/baseline-check` never audits code for these — it reports them as
"delegated: run /full-audit" when the user wants code-level depth:

| Concern | /full-audit dimension |
|---|---|
| a11y in markup/views | 6 |
| security vulnerabilities in code | 2 |
| UI/design consistency | 8 |
| typography | 7 |
| performance | 3 |
| docs drift vs code | 11 |
| copy quality | 12 |

The baseline check owns only what a diff audit cannot see: process, infra, release,
and the charter.
