# Security Guidelines, 2026 Continuation

Continuation of `security.md`, split on 2026-09-16 when that file passed 550 lines (the repo
convention caps a guideline at 500, see CLAUDE.md "Adding a 2026 best-practice section"). Same
precedent as `code-quality-2026.md` and `performance-2026.md`: the security specialist reads both
files in full, and section numbering continues from `security.md` so existing citations by Roman
numeral stay valid. No `applies_to` frontmatter, on purpose: like `security.md` this is always-on.

## Contents
- XII. AI / LLM Security (2026)
- XIII. Modern Browser Hardening (2026)
- XIV. Authentication 2026
- XV. Supply Chain (2026)
- XVI. Blade Escaping Context: `{{ }}` inside `<style>` / `<script>` (RAWTEXT)
- XVII. New Sensitive or Derived Field: Check EVERY Sink in One Round
- XVIII. User-Confirmation Gates over Model Behavior
- XIX. Host and Origin Allowlists: Suffix Checks Need the Dot
- XX. Every Livewire Action Is a Public Endpoint
- XXI. New Telemetry, Logging or Error-Tracking Sink: Inventory the Forwarded Fields
- XXII. Widening a Content Guard to a New Field
- XXIII. Deletion Completes Everywhere, or Reports That It Did Not

## XII. AI / LLM Security (2026)

If the application calls an LLM API or processes LLM output, treat the LLM as another untrusted input channel.

**Prompt Injection — direct.** User-supplied text concatenated into a system prompt becomes a vector: "Ignore previous instructions and..." Use structured message roles (system/user/assistant separation in the SDK), never string-concatenate user input into the system prompt. Treat user input as data, not instructions.

**Indirect Prompt Injection.** When the LLM reads documents/URLs/emails (RAG, tool-use), malicious content in those sources can override instructions. Defenses:
- Allowlist URLs the LLM can fetch
- Strip suspicious markers in fetched content (`<|im_end|>`, JSON config snippets, role tags)
- Re-prompt with stronger guardrails after each fetched-content turn
- Treat tool-call arguments derived from fetched content as low-trust

**Prompt-template files.** When prompts are assembled from template files (e.g. `src/prompts/*.md`, `resources/prompts/*`) with `{{placeholder}}` substitution, audit the templates themselves, not only the callers. Any `{{placeholder}}` whose value originates from external data (search-console queries, scraped page copy, third-party API titles/snippets, prior LLM output) MUST be wrapped in an explicit untrusted-data block inside the template (`<<<UNTRUSTED_*_START>>>` / `<<<UNTRUSTED_*_END>>>` or equivalent) so the model treats it as data, not instructions. A bare external placeholder in a template is an indirect-prompt-injection hole even when the calling code looks safe. Template files are skipped by default file globs — verify they are in audit scope. Substituted values must also have the fence-marker tokens stripped, otherwise a value containing the literal end marker breaks out of the block.

**Output handling.** LLM output is user-controlled. If you render it as HTML, escape it. If you pass it to a shell/SQL/eval, treat it as user input — same parameterization rules as Section V apply.

**Persisted identifiers from an LLM or a web search need an explicit sanitize/allowlist step before they are stored or rendered — not just at the final render call.** This applies to more than markup: URLs, free-text fields, and other identifiers a pipeline script pulls from LLM generation or a search result are attacker- or hallucination-controlled the same way page content is, and they typically flow through a data-ingestion script (`scripts/seed-*`, `scripts/enrich-*`, importers) long before any template renders them, so a render-time escape alone misses the write path. Two shapes of the same root cause have shipped:

```
// BAD — LLM/search-derived URL stored as-is, trusted at every later read
const record = { ...parsed, sourceUrl: llmResult.url };
db.insert(record);

// GOOD — validated once, at the point it enters persistent storage
function sanitizeSourceUrl(url) {
    const parsed = new URL(url);  // throws on malformed input
    if (!['http:', 'https:'].includes(parsed.protocol)) throw new Error('rejected scheme');
    if (!ALLOWED_HOSTS.has(parsed.hostname)) throw new Error('host not on allowlist');
    return parsed.toString();
}
const record = { ...parsed, sourceUrl: sanitizeSourceUrl(llmResult.url) };
db.insert(record);
```

Write one named sanitize/allowlist function per identifier class (URL, free-text marker/fence stripping, etc.) and call it at the ingestion boundary, then reuse it everywhere that class of value enters storage — do not re-derive the check per call site, and do not rely on catching it at render time. A pipeline script that trusts LLM/search output because "it's our own prompt, not a public form" is still ingesting untrusted content; the same class of bug has independently shipped twice on one project (unescaped fence markers from LLM output, an unvalidated `sourceUrl` from search results).

**Secret exposure.** Never include API keys, internal URLs, or PII in the system prompt — the model may echo them back on craft prompts. Use server-side fetch + post-processed results instead of giving the LLM direct credentials.

**Cost DoS.** A malicious user can craft prompts that maximize output tokens (long context, recursive tool-call loops). Rate-limit per user and cap `max_tokens` per call.

## XIII. Modern Browser Hardening (2026)

**Trusted Types** for DOM XSS prevention. Set `Content-Security-Policy: require-trusted-types-for 'script'` and create a policy that sanitizes all assignments to `innerHTML`, `outerHTML`, `eval`, `Function`. Browser blocks raw string sinks at the platform level. Works alongside CSP, not as a replacement.

**Permissions Policy** (replaces Feature-Policy header). Lock down APIs you do not use:
```
Permissions-Policy: camera=(), microphone=(), geolocation=(), payment=(), usb=(), interest-cohort=()
```

**CSP nonce, not 'unsafe-inline'.** Generate a per-request nonce, put it on every `<script>` tag, reference it in CSP. `'unsafe-inline'` defeats XSS protection entirely; nonce-based is the minimum acceptable today.

CSP Level 2 nuance, so this does not become a false finding: `'unsafe-inline'` **together with** a `'nonce-...'` or `'sha256-...'` source in the same `script-src` is the standard backwards-compatibility pattern. CSP2+ browsers ignore `'unsafe-inline'` as soon as a nonce or hash is present, only CSP1 browsers fall back to it. Not a finding. `'unsafe-inline'` alone (no nonce, no hash) stays Important. `'unsafe-eval'` can be a documented framework requirement (Alpine.js without the CSP build, some template engines): check whether the project documents it (CLAUDE.md, a comment at the header) before reporting; documented -> not a finding, undocumented -> Minor with the pointer to the framework's CSP build (2026-08-03).

**SameSite=Strict cookies** unless cross-site flows require otherwise. `Lax` is the default since 2020 but `Strict` is safer for session cookies.

**Subresource Integrity (SRI)** on all CDN-loaded scripts and stylesheets:
```html
<script src="https://cdn.example.com/lib.js" integrity="sha384-..." crossorigin="anonymous"></script>
```
Without SRI, a CDN compromise compromises every site using it.

## XIV. Authentication 2026

**Argon2id over bcrypt.** Argon2id is the OWASP-recommended password hash. Parameters: `memory >= 19 MiB, iterations >= 2, parallelism = 1` (or framework defaults if they meet OWASP 2024+ guidance). Migrate bcrypt-hashed passwords on next login.

**Passkeys (WebAuthn)** as primary auth, not optional. Phishing-resistant, no shared secret, supported in Safari/Chrome/Firefox/Edge. Frameworks: Spatie WebAuthn (Laravel), simplewebauthn (Node). Fallback to TOTP/email-code, never SMS.

**No SMS 2FA** for new flows. SIM-swap is a documented attack chain. TOTP, push notifications, or passkeys instead.

**Session rotation on auth events.** Issue a new session ID on login, password change, MFA enrollment. Old session cookie is invalidated.

## XV. Supply Chain (2026)

**Lockfile drift.** PR that changes `package.json` or `composer.json` but not `package-lock.json` / `composer.lock` is a red flag — either incomplete or someone is bypassing the lock. Block in CI.

**Dependency audit in CI.** `npm audit --omit=dev --audit-level=high`, `composer audit`, `pip-audit` on every PR. Fail on high/critical.

**Sigstore / npm provenance** verification for critical dependencies. `npm install --provenance` checks build provenance metadata.

**Postinstall scripts.** Block by default in CI (`npm config set ignore-scripts true` in builds), allow per-package after review. Postinstall is the most common npm-supply-chain vector.

**Typosquat detection.** Before adding a dependency, search the registry for similar names; established packages have stars/downloads, typosquats often do not.

## XVI. Blade Escaping Context: `{{ }}` inside `<style>` / `<script>` (RAWTEXT)

`<style>` and `<script>` are RAWTEXT elements: the browser does NOT decode
HTML entities inside them. Blade's `{{ }}` escapes to entities, so a quoted
value rendered into CSS/JS breaks silently:

```blade
{{-- BAD — renders font-family: &quot;Inter&quot;, sans-serif; -> invalid CSS, silently ignored --}}
<style>body { font-family: {{ config('mail.font_stack') }}; }</style>

{{-- GOOD — trusted config value, unescaped WITH justification --}}
{{-- font stack comes from config/mail.php (developer-controlled, no user input) --}}
<style>body { font-family: {!! config('mail.font_stack') !!}; }</style>
```

**Rule:** `{{ }}` inside `<style>`/`<script>` with a value that can contain
quotes/ampersands is a correctness bug (broken CSS/JS), and `{!! !!}` there is
only acceptable when the value is provably developer-controlled (config,
enum, constant) — never request/user/DB input. Each `{!! !!}` in RAWTEXT
context needs a trusted-source justification comment. User-dependent values
in `<script>` belong in `@js()` / `Js::from()`, in `<style>` in a sanitized
custom property.

**Audit signal:** grep the diff for `{{` between `<style>`/`<script>` tags →
quoted/entity-prone value: Important [Correctness]; user-influenced value with
`{!! !!}`: Critical [Security] (XSS).

## XVII. New Sensitive or Derived Field: Check EVERY Sink in One Round

When a diff adds a field that can reach a persistent or shared sink — anything CloudKit-mirrored, exported, backed up, indexed, or rendered outside the locked app — the audit checks ALL of its sinks in the SAME round. Fixing the first sink found and discovering the rest over the following rounds is the documented failure mode, not a thorough process.

Example: a filter added to the write path in round 1 while the widget render path and the legacy-entry scrub path carry the same data and surface only in later rounds. Same field, same rule, three rounds, and after round 1 the fix looked complete.

The sink list for one new field, all in one pass:

| Sink | Question |
|---|---|
| Write / persist | Does the filter sit on the write, or only on one caller of it? |
| Export | Does the JSON/Markdown/backup path carry it? |
| Import / validation | Does an untrusted payload get to set it, bypassing the write-path filter? A file from before the rule existed is the normal case. |
| Derived summaries | Does an anchor/chip/summary field quote it in prose? A filter on the structured field does nothing for a string that already contains the value. |
| Extensions | Widget, watch, share sheet, notification body, Siri response — surfaces that render without the app's lock. |
| Diagnostics | Diagnostic dumps and share-a-report features quote real values and leave the device by design. |
| Backup | Plists and files in a shared container ride along in the device backup unless explicitly excluded. |
| Prompt | Does it reach an on-device or remote model as context? |

A field that is legitimately excluded from a sink says so in a comment at the filter, naming the rule (a store policy, a platform guideline), so the next audit does not have to re-derive whether the omission was deliberate.

Confidence: a new sensitive field filtered at one sink while another sink in this list carries it -> Critical. All sinks covered but none documented -> Minor.

## XVIII. User-Confirmation Gates over Model Behavior

A user-confirmation gate lets the model bypass a safety rule (allergy guard, destructive action,
policy override) only after explicit user assent. Every such gate gets THREE checks, in one pass —
one audit found all three gaps in the same feature, spread over three rounds because each round
stopped at the first hit:

1. **Word-boundary matching, never prefix/substring.** A `startsWith`/`includes` check for "does
   the user's text mention the term" is bypassable by unrelated words that contain the term
   ("Ei" matches "eine", "Nuss" matches "Nussbaum-Furnier"). Match on token boundaries against
   the same normalization (folding, casing) the guard itself uses.
2. **Real yes/no assent, not term presence.** "The confirmed term appears in the user's reply" is
   not assent. The reply must contain an affirmative token AND no negation that scopes to the
   term ("nein, bitte ohne Milch" mentions Milch and denies it; "milchfrei" negates via suffix).
   Compound negation morphemes (-frei, -los, ohne-) count as negation, not as mention.
3. **Scope limitation.** A confirmed single term exempts THAT term, never its whole trigger
   class. Confirming "Parmesan trotzdem" must not exempt every dairy trigger; the guard re-checks
   the remaining class members after the exemption.

Confidence: any one of the three missing on a health/safety or destructive-action gate -> Critical.
On a reversible convenience gate -> Important.

## XIX. Host and Origin Allowlists: Suffix Checks Need the Dot

`host.hasSuffix("github.com")`, `endsWith(".com")`-style checks without a leading dot accept lookalike hosts: `evilgithub.com` ends with `github.com`. Same for `startsWith` on origins (`https://example.com.attacker.net`). The check is either equality or a dotted-suffix comparison:

```swift
let ok = host == allowed || host.hasSuffix("." + allowed)
```

Applies to OAuth callback hosts, deep-link handlers, CSP/CORS origin lists, webhook source checks. Confidence: a trust decision (auth, token exchange, deep-link routing) on a dotless suffix match -> Important; with a token or credential flowing on the match -> Critical (2026-06-11).

**Relative-URL allowlists (`redirect_to`, `next`, `return_url`, a CMS link field) check `//` AND `\` in one pass.** A "must start with `/`" guard that rejects `//evil.example` still passes `/\evil.example` and `\/evil.example`: per the WHATWG URL Standard, browsers treat a backslash as a slash for special schemes (http, https), so `/\evil.example` parses as a protocol-relative URL to `evil.example`. A regex that accepts a single leading `/` followed by anything but `/` is therefore an open redirect. Reject when the second character is `/` OR `\`, or parse with the platform URL parser against the app origin and compare the resulting host. When reviewing such a guard, look for both characters in the same read; a checklist item that names only `//` has shipped the `\` half of the same bug (2026-09-15).

## XX. Every Livewire Action Is a Public Endpoint

A Livewire/Filament action method is callable by any client that can render the component, whatever the Blade template shows. Every action that reads or mutates something the viewer does not own starts with the authorization check (`$this->authorize(...)`, `ensureAuthorized()`, `abort_unless(...)`) as its FIRST statement, before any query. A Blade `@if`/`@can` around the button is display logic, not a guard; and the reverse mismatch, a button shown to users the server rejects, is a UX defect worth its own finding (2026-08-27: a propose button was visible to series members whose action the server silently refused). Confidence: mutating action without a first-line authorization check -> Critical; read-only action -> Important; visible control the server rejects -> Important (ux).

## XXI. New Telemetry, Logging or Error-Tracking Sink: Inventory the Forwarded Fields

Wiring a sink (Sentry, Crashlytics, a log shipper, a metrics endpoint) is a data flow to a third party. At wiring time, list every field the call forwards: `extras`, `tags`, breadcrumbs, the raw error object and its `userInfo`/`context`, guard reasons, provider error text, request bodies. Each field is either safe by construction (an enum, a status code, an id) or gets redacted at the call site. Two occurrences across audits (2026-07, 2026-08), both introduced by an earlier fix and caught one audit later. Confidence: raw error objects or free-text detail strings forwarded to a third-party sink -> Important; user content or credentials reachable through them -> Critical. Section XVII's sink table applies to the wiring diff as well.

## XXII. Widening a Content Guard to a New Field

When a fix extends an existing content/keyword guard to an additional field, the guard's false-positive surface grows with it. Before the widening counts as done, run the guard against the EXISTING benign content of the new field (a sample of real rows, the seed data, the fixtures), not only against the example that motivated the fix; and decide per field whether a hit blocks or degrades, because a free-text preferences field is not a chat input (2026-08-03: a stage-1 guard widened to a preferences field hard-blocked "Krieg der Sterne"). Confidence: guard widened without a benign-content check in the same change -> Important.

## XXIII. Deletion Completes Everywhere, or Reports That It Did Not

A deletion path is a security surface, not a correctness detail: what stays behind is data the user is entitled to have gone, still reachable by anyone who reaches the store it stayed in.

**Name every store, not just the row.** A delete that sets a flag (`deleted_at`, `is_deleted`, `status = 'deleted'`) is not an erasure when the caller's contract is erasure. Data written by a feature lives wherever that feature put it: related rows no cascade reaches, cached copies, queued jobs carrying a snapshot of the record, search indices, the error tracker, analytics, exports, backups, and third-party systems (payment provider, CRM, mailing list, file storage). A deletion path that touches fewer stores than the write paths that filled them is incomplete, and the gap is the finding.

**A multi-store deletion needs a resume marker that survives the failure.** When the local half succeeds and a remote half can fail, something has to record that the remote half is still outstanding. Clearing that marker unconditionally, in a `defer`, a `finally`, or a cleanup at the end of the happy path, drops the only record of the outstanding work and makes the recovery code that reads it dead on exactly the path it exists for.

**A swallowed remote failure never reaches the success report.** An error that is caught, logged, and falls through to the same completion callback as the success path makes a network failure, a signed-out account and a real deletion indistinguishable, to the user and to the audit trail. Either the failure propagates, or the reported state names what is still pending.

**An irreversible external step is ordered against a marker.** Cancelling a subscription, removing a third-party account, or deleting remote files cannot be rolled back by the surrounding database transaction. A crash between that step and the local delete must leave a recoverable state, not an orphan.

Confidence: an erasure contract with data provably retained in a store the path never touches -> Critical; a resume marker cleared on the error path, or a swallowed remote failure reported as success -> Critical; a soft delete whose contract is ambiguous, or an external step with no record that it ran -> Important.
