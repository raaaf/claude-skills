# Subagent 2: Security

- **subagent_type:** `security-auditor`
- **model:** `opus`
- **maxTurns:** `15`

## Focus

Secrets, injection, OWASP Top 10, dependencies.

**Complete guidelines:** Read `guidelines/security.md` in the skill directory and check the code against all rules described there.

**Sibling-field guard check:** when a field gains a sanitization/security guard in the diff (accessor guard, leak protection, validation), check whether structurally identical sibling fields (`first_name`/`last_name`/`name`, `email`/`phone`, address parts) need the same guard. A guard added to one of several parallel fields while the siblings stay exposed is an Important finding (2026-07-14: `last_name` lacked the email-leak guard `first_name`/`name` had received months earlier).

**For native apps** (`FRAMEWORK` = ios/android/react-native/flutter): additionally `guidelines/native-mobile.md` section II — Keychain/Keystore instead of UserDefaults, ATS/cleartext, deep-link validation, privacy manifest, permission descriptions. XSS/CSP rules do not apply there.

## Diff mode (/audit): whole-file output-sink sweep

Hotspots point at changed lines. Output sinks do not have to be on a changed line to be exploitable — they only have to be in a file someone is actively editing.

**For every template file in the diff, read the ENTIRE file and check every output sink, not just the changed lines.** Sinks to enumerate: `{!! !!}` (Blade), `v-html`, `dangerouslySetInnerHTML`, `echo`/`print` without an `esc_*`/escaping call, `.innerHTML =`, any raw-HTML directive the framework offers. A sink fed by user input, a CMS/ACF field, or an API response without an allowlist filter (`wp_kses_post`, sanitizer, DOMPurify) is a finding regardless of whether the diff touched that line.

This costs one extra Read per touched template and is not optional: 25 unprotected `{!! !!}` sinks in flexible templates survived four consecutive diff audits (2026-03-16 through 03-31) that each had those exact files in scope and reported security clean. Only the full audit caught them, as Critical.

Same rule for the whole-file scan when a diff-mode finding claims a sink is safe: verify the escaping call sits on the same variable, not merely somewhere in the file.

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
