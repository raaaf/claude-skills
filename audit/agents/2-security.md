# Dimension: Security

## Look for

Secrets, injection, OWASP Top 10, dependencies. Read `guidelines/security.md` in full.

- **Sibling-field guard check:** a field that gains a sanitization/security guard needs the same
  guard on structurally identical siblings (`first_name`/`last_name`/`name`, `email`/`phone`,
  address parts). A guard on one of several parallel fields while siblings stay exposed is
  `Important`.
- **Native apps** (`FRAMEWORK` = ios/android/react-native/flutter): additionally
  `guidelines/native-mobile.md` section II — Keychain/Keystore vs UserDefaults, ATS/cleartext,
  deep-link validation, privacy manifest, permission descriptions. XSS/CSP rules do not apply.
- **Whole-file output-sink sweep for every touched template:** read the ENTIRE file, not just
  changed lines, and check every output sink (`{!! !!}`, `v-html`, `dangerouslySetInnerHTML`,
  `echo`/`print` without escaping, `.innerHTML =`, any raw-HTML directive). A sink fed by user
  input, a CMS field, or an API response without an allowlist filter is a finding regardless of
  whether the diff touched that exact line.
- **Prompt templates** (`src/prompts/*.md` or similar): every `{{placeholder}}` with a value from
  external data must be wrapped by an `<<<UNTRUSTED_*_START>>>` block with fence tokens stripped
  from the substituted value — a bare external placeholder is indirect prompt injection
  (`guidelines/security.md` section XII).
- **XSS/injection findings:** cross-check the associated store/form-request validation or
  sanitization first. Already validated/sanitized → no finding.
- **Enum findings:** check the enum case exists before flagging. Alpine `x-data`: only `>`/`>=` risk.
- **Plaintext-storage findings:** grep the whole file for `hash(`, `sha256`, `Hash::` on the same
  variable before flagging plaintext storage — a hashed-earlier write can look plaintext at the
  write line.
- **Consent questions belong to `privacy` (13), not here.** Do not dismiss a consent-gate question
  as "documented" — hand it to the privacy dimension instead of silently accepting it.

**Defect classes calibrated against real findings (2026-09-05/2026-08-27 audits):**
- **CSP directive gaps:** a `Content-Security-Policy` missing `base-uri`, `object-src`, or
  `form-action`, or a nonce-based script-src defeated by a co-present `unsafe-inline`.
- **Forwarded-header trust:** `X-Forwarded-For` read as the leftmost entry instead of the rightmost
  (client-controlled prefix spoofs the real client), or `X-Forwarded-Proto` trusted without a
  trusted-proxy gate (`TRUST_PROXY` unset/misconfigured lumps all clients into one rate-limit bucket).
- **DNS/SSRF:** a hostname resolved via `gethostbyname`/A-record-only lookups with the AAAA
  record unchecked, or no re-check between resolution and connection (DNS rebinding, TOCTOU).
- **Attribute injection via string concatenation:** a value (shortcode attribute, user input)
  concatenated directly into `class="..."` or another HTML attribute outside the template
  engine's own escaping (stored/reflected attribute injection, not just `{!! !!}`/`v-html`).
- **Client-supplied MIME upload gate:** a `wp_handle_upload_prefilter`/`wp_handle_sideload_prefilter`
  (or other upload-validation callback) branching on `$file['type']` or another client-supplied
  Content-Type value instead of the filename extension or content sniffing — at that hook WordPress
  has not yet computed the real type (SVG/script upload bypass).
- **Missing capability check on one handler among siblings:** an `admin-ajax`/`admin_init`/route
  handler lacking a capability/auth check while structurally identical sibling handlers have one.
- **JSON-LD/inline script without HTML-tag escaping:** `json_encode`/`wp_json_encode` building
  JSON-LD or an inline `<script>` payload without `JSON_HEX_TAG` (breakout via `</script>`).
- **Nonce-issuing endpoint registered nopriv:** a `wp_ajax_nopriv_*` (or equivalent unauthenticated
  route) that issues/refreshes a nonce/token for anonymous callers, or rate limiting placed AFTER
  the expensive/auth check instead of before it, leaving failed-auth requests unthrottled.
- **Broad capability remap:** a capability mapped to a MORE privileged one with a `do_not_allow`
  fallback, which can silently lock out the intended role if the more-privileged check fails.
- **Web-search/tool grounding without a domain allowlist:** an LLM tool call with web/browse access
  lacking `allowed_domains` (or equivalent), letting ungrounded content pass as approved.
- **Consent/attestation bypass on a fallback path:** a fallback code path (on-device model, cached
  response) that skips a check the primary path enforces.

## Severity

`Critical` requires actual exploitability: a reachable path from untrusted input to the sink/action
without an intervening guard. An authenticated low-privilege role (subscriber, contributor, author,
editor) counts as untrusted input — a stored XSS or privilege exposure reachable by such a role is
`Critical`, not `Important`, solely on account of needing an account. `Important` needs an unusual
precondition beyond that: a specific misconfiguration, a non-default filter, or an already-compromised
admin session. `Minor` stays defense-in-depth: removing the guard would not change what is exploitable.

Examples (2026-09-05 audit): `Critical` — Contributor-or-above could inject an unescaped class
attribute via `[icon]`, stored XSS at the lowest content-editing role. `Important` — a REST callback
returning bare `read` was reachable only if a field's `show_in_rest` were enabled, which none are.
`Minor` — a second `assertSafeHost` check, redundant with another guard, was kept for its 403 message.

## Output

Reply with the specialist schema: `findings[{id, severity, confidence, files, issue, impact}]`
plus `coverage`. Every ID is prefixed `security-`. Set `coverage` to `COVERAGE: full` or
`COVERAGE: partial | not read: {file1}, {file2}`.
