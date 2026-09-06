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
- **Enum findings:** check the referenced enum case actually exists before flagging.
- **Alpine `x-data` operator render risk:** only `>`/`>=`, never `<`/`<=`.
- **Plaintext-storage findings:** grep the whole file for `hash(`, `sha256`, `Hash::` on the same
  variable before flagging plaintext storage — a hashed-earlier write can look plaintext at the
  write line.
- **Consent questions belong to `privacy` (13), not here.** Do not dismiss a consent-gate question
  as "documented" — hand it to the privacy dimension instead of silently accepting it.

**Defect classes calibrated against real findings (2026-09-05/2026-08-27 audits):**
- **CSP directive gaps:** a `Content-Security-Policy` missing `base-uri`, `object-src`, or
  `form-action`, or a nonce-based script-src defeated by a co-present `unsafe-inline`.
- **Forwarded-header trust:** `X-Forwarded-For` read as the leftmost entry instead of the
  rightmost (client-controlled prefix spoofs the real client), or `X-Forwarded-Proto` trusted
  without a trusted-proxy gate (`TRUST_PROXY` unset/misconfigured lumps all clients into one
  rate-limit bucket).
- **DNS/SSRF:** a hostname resolved via `gethostbyname`/A-record-only lookups with the AAAA
  record unchecked, or no re-check between resolution and connection (DNS rebinding, TOCTOU).
- **Attribute injection via string concatenation:** a value (shortcode attribute, user input)
  concatenated directly into `class="..."` or another HTML attribute outside the template
  engine's own escaping (stored/reflected attribute injection, not just `{!! !!}`/`v-html`).
- **Client-supplied MIME upload gate:** an upload validated only against the client-sent
  Content-Type/MIME field instead of the file extension or actual content sniffing (SVG/script
  upload bypass).
- **Missing capability check on one handler among siblings:** an `admin-ajax`/`admin_init`/route
  handler lacking a capability/auth check while structurally identical sibling handlers have one.
- **JSON-LD/inline script without HTML-tag escaping:** `json_encode`/`wp_json_encode` building
  JSON-LD or an inline `<script>` payload without `JSON_HEX_TAG` (breakout via `</script>`).
- **Nonce-issuing endpoint registered nopriv:** a `wp_ajax_nopriv_*` (or equivalent unauthenticated
  route) that issues or refreshes a nonce/token for anonymous callers.
- **Auth-gate ordering:** rate limiting or another cheap guard placed AFTER the expensive/auth
  check instead of before it, leaving failed-auth requests unthrottled.
- **Broad capability-to-broad-capability remap:** a capability mapped to a MORE privileged
  capability with a `do_not_allow` fallback, which can silently lock out the intended role
  entirely if the more-privileged capability check fails.
- **Web-search/tool grounding without a domain allowlist:** an LLM tool call with web/browse
  access lacking `allowed_domains` (or equivalent), letting ungrounded content pass as approved.
- **Consent/attestation bypass on a fallback path:** a fire-and-forget or fallback code path
  (on-device model, cached response) that skips a check the primary path enforces.

## Severity

`Critical` requires actual exploitability: a reachable path from untrusted input to the sink/action
without an intervening guard. A theoretical or already-mitigated flaw is `Important`. Style or
defense-in-depth suggestions are `Minor`.

## Output

Reply with the specialist schema: `findings[{id, severity, confidence, files, issue, impact}]`
plus `coverage`. Every ID is prefixed `security-`. Set `coverage` to `COVERAGE: full` or
`COVERAGE: partial | not read: {file1}, {file2}`.
