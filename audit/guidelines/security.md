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

**Client-exposed state:** Public properties or state exposed to the client are readable and writable from the browser. Never put sensitive data (other users' records, internal IDs used for authorization) in client-accessible state without server-side validation. Use immutable/locked properties or server-side validation hooks to prevent client-side tampering:

```
// GOOD — prevent client-side tampering with the user ID
// Mark as immutable/locked so the client cannot modify it
userId: locked(int)
```

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
