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

## Severity

`Critical` requires actual exploitability: a reachable path from untrusted input to the sink/action
without an intervening guard. A theoretical or already-mitigated flaw is `Important`. Style or
defense-in-depth suggestions are `Minor`.

## Output

Reply with the specialist schema: `findings[{id, severity, confidence, files, issue, impact}]`
plus `coverage`. Every ID is prefixed `security-`. Set `coverage` to `COVERAGE: full` or
`COVERAGE: partial | not read: {file1}, {file2}`.
