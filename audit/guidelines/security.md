# Security Guidelines

Security is not a feature you bolt on at the end — it is a property of every line of code you write. A single unescaped output, a missing authorization check, or a leaked secret can undo months of careful engineering. Treat every input as hostile, every output as a potential vector, and every permission boundary as load-bearing.

## I. Output Escaping & XSS Prevention

Cross-site scripting (XSS) remains one of the most common and damaging vulnerabilities in web applications. The rule is simple: never trust user-supplied data in output context.

| Context | Safe Pattern | Dangerous Pattern |
|---------|-------------|-------------------|
| Template output | Escaped/auto-escaped template expressions | Unescaped template output (e.g., raw HTML rendering) |
| HTML attribute | Escaped values inside quotes | Unquoted attributes with user data |
| JavaScript context | JSON-serialized data via framework helper | Inlining raw data in `<script>` blocks |
| URL parameter | URL-encoded values | Raw concatenation into URLs |

**Unescaped template output is a loaded weapon.** Every occurrence must have a comment explaining why raw output is safe — typically because the value was sanitized server-side with an allowlist HTML purifier (e.g., HTMLPurifier, DOMPurify). If you cannot articulate why it is safe, use the default escaped output instead.

Never construct HTML strings in backend code and pass them to templates as raw output. Build your HTML in templates where the escaping engine protects you:

```
// BAD — building HTML in backend code, forcing raw output
badge = '<span class="badge">' + user.role + '</span>';
// Then in template: raw(badge)  <-- XSS if role is tainted

// GOOD — let the template engine handle escaping
<span class="badge">{{ user.role }}</span>
```

For rich text fields that genuinely need HTML (WYSIWYG editors, markdown rendering), sanitize on write with an allowlist approach, not on read. Store the sanitized version. This prevents stored XSS even if the sanitizer has a bypass — you only need to re-sanitize stored content, not chase every read path.

## II. Authentication & Authorization

Authentication answers "who are you?" Authorization answers "are you allowed to do this?" Confusing the two — or forgetting the second — is the source of most privilege escalation bugs.

**Every action and endpoint must check authorization.** Being logged in is not the same as being authorized. A user can call any public method or endpoint by crafting a request:

```
// BAD — any authenticated user can delete any post
function deletePost(postId):
    Post.find(postId).delete()

// GOOD — explicit authorization check
function deletePost(postId):
    post = Post.findOrFail(postId)
    authorize('delete', post)
    post.delete()
```

**Use centralized permission policies, not inline role checks.** Scattering `if (user.role === 'admin')` throughout controllers creates a maze of implicit permissions that is impossible to audit. Centralized policies make the logic testable:

```
// In a policy/permission class
function canDelete(user, post):
    return user.id === post.userId
        || user.hasRole('editor')
```

**Ownership guard on every mutating action.** Any controller method that mutates a record — `update`, `destroy`, `store` (when writing to an existing parent), and any custom write action — must verify that the record belongs to the current user's tenant/owner scope **before any other logic block**, not after loading or transforming data. A logged-in user can swap the ID in the URL or payload (IDOR); route-model binding alone does not scope by owner.

```
// BAD — route binds the model, but any user can pass any id
function update(request, transaction):
    transaction.update(request.validated())  // IDOR: no ownership check

// GOOD — ownership asserted first, before everything else
function update(request, transaction):
    abortUnless(transaction.tenant_id === auth.user.tenant_id, 403)
    transaction.update(request.validated())
```

If the framework supports tenant-global query scopes (e.g. a global scope that filters every query by the current tenant), prefer that as defense in depth — but still keep the explicit `abortUnless`/`authorize` guard in the action so the protection is visible and survives a scope being disabled. New controllers are the recurring offender: audit every `update`/`destroy`/`store` for a first-line ownership check.

**A route's gating change or a new route must be checked against the whole route table, not just its own line.** Path-prefix middleware gates the exact path it is mounted on — it does not automatically extend to child/parameter routes, and a parameter route's gate does not automatically extend to its parent. Both directions have shipped as real bypasses:

```
// BAD — exact-path gate, sibling route left open
app.use('/api/items', requireEntitlement)
app.get('/api/items', listItems)        // gated
app.get('/api/items/:id', getItem)      // NOT gated — served the full record to any authenticated caller

// GOOD — gate applied per route, or with a pattern that covers the whole subtree
app.get('/api/items', requireEntitlement, listItems)
app.get('/api/items/:id', requireEntitlement, getItem)
```

When a diff adds a route or changes what gates an existing one, read the full route table for that resource (not just the diff hunk) and name every sibling/parameter route explicitly: which ones share the new/changed gate, which ones don't, and why. A framework's path-matching semantics (exact vs. prefix vs. regex) decide whether a gate mounted on the parent path reaches the child — verify this for the specific router in front of you rather than assuming it behaves like the last one you audited. This is a repeat offender: the same root cause shipped twice on the same project (`Cache-Control` header scoped to the exact list path while the underlying data leaked through a sibling; then a `GET /api/items/:id` left fully ungated while `GET /api/items` was gated).

**Client-exposed state:** Public properties or state exposed to the client are readable and writable from the browser. Never put sensitive data (other users' records, internal IDs used for authorization) in client-accessible state without server-side validation. Use immutable/locked properties or server-side validation hooks to prevent client-side tampering:

```
// GOOD — prevent client-side tampering with the user ID
// Mark as immutable/locked so the client cannot modify it
userId: locked(int)
```

**Classify every auth/lock failure as retryable or structural.** Not every failed authentication attempt has the same fix. A wrong password or a stale token is retryable — the user tries again and it works. A missing device passcode, no biometrics enrolled, or a revoked credential is structural — retrying the identical action fails identically, forever. Only the structural case needs an escape hatch (a fallback auth method, a support/reset path, another way to reach the app's data); a bare "try again" on a structural failure locks the user out permanently, and it looks identical to a working retry loop until someone actually hits it.

```
// BAD — same message and only action, regardless of why it failed
catch (error):
    showAlert('Authentication failed. Try again.')

// GOOD — structural failures get a different path than retryable ones
catch (error):
    if error.isStructural:  // no passcode set, no biometrics enrolled, credential revoked
        showAlert('Face ID is not set up on this device.', action: openSystemSettings)
    else:
        showAlert('Authentication failed. Try again.')
```

**Rule:** every error path in an auth/lock gate must branch on this classification before deciding what to show the user. Audit every `catch` block in login, biometric unlock, and re-authentication flows for a single generic message covering both cases.

## III. CSRF, Rate Limiting & Abuse Prevention

**CSRF protection** is typically automatic in modern frameworks for web routes. Do not disable it. If you have a webhook or API endpoint that needs to skip CSRF, place it in an API-specific route group — never add broad CSRF exceptions for convenience.

**Rate limiting** is essential on any endpoint that accepts input — login, registration, password reset, search, API calls, contact forms:

```
// Configure rate limits for sensitive endpoints
rateLimiter('login', maxAttempts=5, perMinutes=1, keyBy=request.ip)

// Apply to route
POST '/login' -> LoginController, middleware: 'throttle:login'
```

For interactive component actions, apply rate limiting inside the method when the framework does not handle it automatically:

```
function submitContactForm():
    rateLimiter.attempt(
        key: 'contact-form:' + request.ip,
        maxAttempts: 3,
        callback: () => processForm(),
        decaySeconds: 60,
    )
```

**Honeypot fields** on public forms catch automated bots without degrading UX for real users. Add a hidden field that humans will not fill in:

```html
<div class="hidden" aria-hidden="true">
    <input type="text" name="website" tabindex="-1" autocomplete="off">
</div>
```

Reject the submission server-side if the honeypot field has a value. This is defense in depth — it supplements rate limiting, not replaces it.

## IV. Input Validation & Sanitization

**Validate every input on the server.** Client-side validation is a UX convenience, not a security measure. An attacker will bypass it entirely.

Prefer strict allowlists over blocklists. Validate type, length, format, and range:

```
validated = request.validate({
    'email':   ['required', 'email', 'max:255'],
    'name':    ['required', 'string', 'max:100'],
    'age':     ['required', 'integer', 'min:0', 'max:150'],
    'role':    ['required', oneOf(['viewer', 'editor'])],
    'content': ['required', 'string', 'max:10000'],
})
```

In interactive components, ensure validation fires before using user-supplied properties. If you read properties directly without validating first, you are trusting client input:

```
// BAD — using property without validation
function search():
    results = Post.where('title', 'like', '%' + this.query + '%').get()

// GOOD — validate first
function search():
    validate({ query: 'required|string|max:100' })
    results = Post.where('title', 'like', '%' + this.query + '%').get()
```

## V. SQL Injection Prevention

ORM query builders use parameterized queries by default — but raw expressions bypass this protection entirely:

```
// DANGEROUS — direct interpolation in raw expression
User.whereRaw("name = '" + name + "'").get()
User.orderByRaw(request.input('sort')).get()

// SAFE — parameterized raw expressions
User.whereRaw('name = ?', [name]).get()

// SAFE — validate against allowlist for column names
allowed = ['name', 'created_at', 'email']
sort = request.input('sort') if request.input('sort') in allowed else 'created_at'
User.orderBy(sort).get()
```

**Never pass user input directly to raw query methods** without parameterization. Audit every occurrence of raw SQL expressions in your codebase — each one is a potential injection point.

## VI. File Upload Security

File uploads are among the most dangerous features in any web application. An uploaded file can contain executable code, malware, or oversized data designed to exhaust resources.

| Check | Implementation |
|-------|---------------|
| MIME type validation | Validate against allowlist, never trust `Content-Type` header alone |
| File extension | Allowlist of permitted extensions (`.jpg`, `.png`, `.pdf`) |
| File size | Set `max` in validation AND in server config |
| Filename sanitization | Generate a UUID filename, never use the original |
| Storage location | Store outside the web root, serve through a controller |
| Virus scanning | Scan with ClamAV or similar before accepting |

```
validated = request.validate({
    'avatar': [
        'required',
        'file',
        'mimes:jpg,jpeg,png,webp',
        'max:2048', // 2 MB
        'dimensions:max_width=4096,max_height=4096',
    ],
})

path = request.file('avatar').storeAs(
    'avatars',
    generateUuid() + '.' + request.file('avatar').extension(),
    'private' // non-public storage
)
```

**Never serve uploaded files directly from a public directory.** Use a route with authorization that streams the file:

```
GET '/files/{file}' -> function(file):
    abortUnless(auth.user.can('view', file), 403)
    return storage('private').download(file.path)
```

## VII. Cache Key Isolation

Cached data without proper scoping leaks information between users or tenants. Every cache key that stores user-specific or tenant-specific data must include the relevant scope:

```
// BAD — all users share the same cached dashboard
cache.remember('dashboard-stats', 3600, () => computeStats())

// GOOD — scoped to the authenticated user
cache.remember('dashboard-stats:user:' + user.id, 3600, () => computeStats())

// GOOD — scoped to tenant in multi-tenant app
cache.remember('reports:tenant:' + tenant.id + ':monthly', 3600, () => generateReport())
```

This applies to every caching layer — application cache, query cache, computed/memoized properties that depend on user context, and session-based storage. A cache key without a scope identifier is a data leak waiting to happen.

## VIII. Secret Management

**Never hardcode secrets.** No API keys, database passwords, encryption keys, or third-party tokens in source code — not even in test files, seeders, or configuration defaults.

```
// BAD — secret in source code
stripe = new StripeClient('sk_live_abc123...')

// GOOD — from environment
stripe = new StripeClient(config('services.stripe.secret'))
// config file reads from env('STRIPE_SECRET')
```

Rules for secrets:

- Store in `.env` (never committed — `.env` must be in `.gitignore`)
- Access environment values through a config layer, not directly in application code (env values may not be available when config is cached)
- Rotate secrets on any suspected exposure — immediately, not "when we get to it"
- Use separate secrets for each environment (local, staging, production)
- Audit `.env.example` to ensure it contains only placeholder values, never real credentials

## IX. Content Security Policy

A Content Security Policy (CSP) header tells the browser which sources of content are legitimate, blocking injected scripts even if XSS gets past your output escaping:

```
// In middleware or via a CSP package
response.headers.set('Content-Security-Policy', [
    "default-src 'self'",
    "script-src 'self' 'nonce-{nonce}'",
    "style-src 'self' 'unsafe-inline'", // inline styles are often needed
    "img-src 'self' data: https:",
    "font-src 'self'",
    "connect-src 'self'",
    "frame-ancestors 'none'",
    "base-uri 'self'",
    "form-action 'self'",
].join('; '))
```

Use nonce-based script allowlisting rather than `'unsafe-inline'` for scripts. When using interactive frontend frameworks, you may need to configure the nonce in the framework config to ensure its inline scripts are permitted.

Additional security headers worth setting:

| Header | Value | Purpose |
|--------|-------|---------|
| `X-Content-Type-Options` | `nosniff` | Prevents MIME type sniffing |
| `X-Frame-Options` | `DENY` | Prevents clickjacking |
| `Referrer-Policy` | `strict-origin-when-cross-origin` | Controls referrer leakage |
| `Permissions-Policy` | `camera=(), microphone=(), geolocation=()` | Restricts browser APIs |
| `Strict-Transport-Security` | `max-age=31536000; includeSubDomains` | Enforces HTTPS |

## X. OWASP Top 10 — Quick Reference

This is a condensed checklist mapped to the detailed sections above. Each item must be verifiable in code review:

1. **Broken Access Control** — Authorization on every action (Section II). No direct object references without ownership check. No reliance on hidden fields or client-side state for permissions.
2. **Cryptographic Failures** — HTTPS everywhere. Passwords hashed with bcrypt/argon2. Sensitive data encrypted at rest. No secrets in logs.
3. **Injection** — Parameterized queries only (Section V). No raw user input in shell commands (use explicit argument lists, never string concatenation).
4. **Insecure Design** — Threat modeling during architecture phase. Rate limiting on sensitive flows. Defense in depth — never rely on a single control.
5. **Security Misconfiguration** — Debug mode off in production. Default credentials changed. Directory listing disabled. Stack traces hidden from users.
6. **Vulnerable Components** — Run dependency audits regularly. Keep dependencies updated. Remove unused packages.
7. **Authentication Failures** — Strong password policies. Account lockout after failed attempts. Multi-factor authentication for admin accounts. Session invalidation on password change.
8. **Data Integrity Failures** — Verify signatures on webhooks. Validate data from external APIs. Use signed URLs for sensitive operations.
9. **Logging & Monitoring Failures** — Log authentication events, authorization failures, and input validation failures. Never log passwords, tokens, or full credit card numbers. Alert on anomalous patterns.
10. **SSRF (Server-Side Request Forgery)** — Validate and allowlist URLs before making server-side HTTP requests. Block requests to internal networks (`127.0.0.1`, `10.x.x.x`, `169.254.169.254`). Never let user input control the destination of server-side requests without validation.

## XI. GoBD / Record Immutability

For applications subject to GoBD compliance (or any domain where records become legally immutable after a certain state transition):

**Model-Level Guards are mandatory.** Do not rely solely on UI/controller checks to prevent mutations. Add an `updating()` model event that:
- Checks whether the record is in an immutable state (e.g., `finalized_at IS NOT NULL`)
- Defines an explicit allowlist of fields that may still change after immutability (e.g., `status`, `paid_amount`, `paid_at`, `cancelled_at`)
- Throws a `RuntimeException` if any non-allowed field is dirty

**$fillable Hygiene for immutable fields.** Fields that control immutability state (`finalized_at`, `cancelled_at`, `number`, `sender_snapshot`, `pdf_path`) must NOT be in `$fillable`. Set them via direct assignment in dedicated Service methods. This prevents accidental mass-assignment via `fill()`, `update()`, or `create()`.

**JS Interpolation safety.** When interpolating PHP values into JavaScript (Heredoc strings, inline `<script>` blocks), always use `json_encode()` with `JSON_HEX_TAG | JSON_UNESCAPED_UNICODE`, never `addslashes()`. The latter does not protect against template literal injection or `</script>` breakout.

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

Real case (2026-08-06): a health-card filter was added to the write path in round 1. The widget render path and the legacy-entry scrub path carried the same data and were only found in rounds 2 and 3. Same field, same rule, three rounds, and between round 1 and round 3 the fix looked complete.

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
