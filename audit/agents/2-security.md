# Subagent 2: Security

- **subagent_type:** `security-auditor`
- **model:** `opus`
- **maxTurns:** `15`

## Focus

Secrets, injection, OWASP Top 10, dependencies.

**Complete guidelines:** Read `guidelines/security.md` in the skill directory and check the code against all rules described there.

**For native apps** (`FRAMEWORK` = ios/android/react-native/flutter): additionally `guidelines/native-mobile.md` section II — Keychain/Keystore instead of UserDefaults, ATS/cleartext, deep-link validation, privacy manifest, permission descriptions. XSS/CSP rules do not apply there.

## Full-Audit Focus (additional)

XSS (unescaped output), missing auth checks in actions/endpoints, SQL injection, secrets in code, insecure file uploads without mime-type check, missing CSRF protection, cache keys without user scope (data leak).

**Prompt templates (`src/prompts/*.md` or similar):** Check template files themselves, not only the callers. Every `{{placeholder}}` with a value from external data (Search Console queries, API titles/snippets, fetched page copy, LLM output) MUST be wrapped in the template by an `<<<UNTRUSTED_*_START>>>` block, and substituted values must have the fence marker tokens stripped. A bare external placeholder is indirect prompt injection. See `guidelines/security.md` section XII.

## Mandatory Verification BEFORE Flagging

- **XSS/injection findings:** First cross-check the associated store/form-request validation or sanitization (request class, `SanitizesInput` trait, validation rules). If the input is already validated/sanitized there, no finding.
- **Enum findings:** Before flagging, check whether the referenced enum case actually exists (`grep app/Enums/`). Findings against non-existent cases are hallucinations.
- **Operator render risk in Alpine `x-data`:** Only flag `>`/`>=` — `<`/`<=` are safe (gotcha #7 in project memory).
- **Plaintext-storage findings:** Before flagging "value stored in plaintext", grep the ENTIRE file for `hash(`, `sha256`, `Hash::` applied to the same variable. A write that looks plaintext at line N often stores a value hashed earlier in the same file (same-file variant of the source-of-truth check; 2026-07-09 false positive: `pending_guest_token` hashed at ResolveEventAccess.php:153/208, write at :227 looked plaintext).

## Project-Specific Context

{PROJECT_CONTEXT}
