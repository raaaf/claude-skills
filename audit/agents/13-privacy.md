# Dimension: Privacy

## Look for

Consent gates for third-party content, tracking scripts, cookies, IP storage/logging, data
sharing, imprint/privacy-policy links, form data.

- **Consent before third-party content:** any embed, widget, or script from a third-party domain
  (maps, video, fonts loaded from a third-party CDN, analytics, chat widgets) that loads before
  explicit user consent.
- **Tracking and analytics:** any tracking pixel, analytics SDK, or fingerprinting call that fires
  before consent, or that fires unconditionally regardless of a stated opt-out.
- **Cookies and storage:** cookies or `localStorage`/`sessionStorage` entries used for tracking
  or cross-session identification set without a consent gate.
- **IP addresses in logs and rate limiters:** IP addresses persisted in application logs,
  analytics events, or rate-limiter state beyond what is operationally necessary, without a stated
  retention/legal basis.
- **Forms and data sharing:** form submissions that send personal data to a third-party endpoint
  (webhook, CRM, marketing tool) without a visible legal basis or consent step at submission time.
- **Required links:** missing or broken imprint (`Impressum`) / privacy-policy links on pages that
  collect data or embed third-party content.

**Defect classes calibrated against real findings (2026-09-05/2026-08-27 audits):**
- **Third-party plugin bypassing the first-party access gate:** a third-party SEO/marketing
  plugin's own meta/OG/Twitter/schema filter not wired to the same access-check the first-party
  code uses, leaking protected-page content through the plugin's output instead.
- **Sensitive identifier logged even truncated:** an API key id, certificate fingerprint, or other
  identifying material written to logs (even partially/truncated) without a stated retention or
  redaction policy — flag regardless of whether the log target is stdout-only or a debug flag.

**Do not wave a consent question through as "documented".** A prior audit treated a consent gate
as accepted because it was mentioned in a doc; the gate itself was still missing at runtime. Verify
the actual code path, not the doc's claim about it (Prompt-Regel 5 applies to the tradeoff, not to
whether the gate exists).

## Severity

`Critical` = personal data leaves the system to a third party without a legal basis, or a
third-party script/tracker loads without consent. `Important` = a consent flow exists but is weak
(pre-ticked, buried, easy to misconstrue as consent when it isn't) or a required link is missing.
`Minor` = cosmetic consent-UI issues with no data-flow impact.

## Output

Reply with the specialist schema: `findings[{id, severity, confidence, files, issue, impact}]`
plus `coverage`. Every ID is prefixed `privacy-`. Set `coverage` to `COVERAGE: full` or
`COVERAGE: partial | not read: {file1}, {file2}`.
