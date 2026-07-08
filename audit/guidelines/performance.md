# Performance Guidelines

Performance is not optimization work you do after the product ships — it is a quality that users perceive on every interaction. A 200ms database query that fires on every page load, an N+1 loop that scales linearly with data size, or an unbounded dataset loaded into memory will eventually become an outage. Build for the dataset size you will have in a year, not the one you have today.

## I. Database: N+1 Queries

The N+1 problem is the single most common performance issue in ORM-based applications. It occurs when you load a collection and then access a relationship on each item, triggering one query per item instead of one query for all items.

```
// BAD — 1 query for posts + N queries for authors (one per post)
posts = Post.all()
for post in posts:
    print(post.author.name)  // triggers a query each time

// GOOD — 2 queries total: one for posts, one for all related authors
posts = Post.withRelated('author').all()
for post in posts:
    print(post.author.name)  // no additional query
```

**Enable strict mode in development** to catch N+1 queries automatically. Most ORMs offer a lazy-loading prevention mode that throws an exception whenever a relationship is lazy-loaded, forcing you to add eager loading before it reaches production.

**Use aggregate subqueries instead of loading entire relationships** when you only need counts or sums:

```
// BAD — loads all comments into memory just to count them
posts = Post.withRelated('comments').all()
for post in posts:
    post.comments.count()

// GOOD — single query with subselect, no comment models loaded
posts = Post.withCount('comments').all()
for post in posts:
    post.commentsCount

// GOOD — sum without loading the relationship
users = User.withAggregate('orders', 'sum', 'total').all()
for user in users:
    user.ordersTotal
```

## II. Query Optimization

**Select only the columns you need.** `SELECT *` fetches every column, including large text fields and blobs you may never use. This wastes memory, network bandwidth, and makes it harder for the database to use covering indexes:

```
// BAD — loads all columns including potentially large 'body' and 'metadata'
posts = Post.all()

// GOOD — only what the view needs
posts = Post.select('id', 'title', 'slug', 'published_at').all()

// GOOD — fetch a single column or key-value pair when that is all you need
titles = Post.pluckColumn('title', 'id')
```

**Use scalar queries for single values** instead of loading a full model:

```
// BAD — loads entire model to read one field
email = User.find(id).email

// GOOD — single scalar query
email = User.where('id', id).value('email')
```

**Proper indexing** is the highest-leverage performance tool. Every `WHERE`, `ORDER BY`, and `JOIN` column should have an index unless the table is trivially small. Composite indexes must match query column order:

```
// Migration for a common query: WHERE tenant_id = ? AND status = ? ORDER BY created_at DESC
table.index(['tenant_id', 'status', 'created_at'])
```

**Avoid queries inside loops.** Any database call inside a `foreach`, `map`, or `each` is a red flag. Batch the operation:

```
// BAD — one update per item
for id in orderIds:
    Order.where('id', id).update({ status: 'shipped' })

// GOOD — single query
Order.whereIn('id', orderIds).update({ status: 'shipped' })
```

## III. Framework-Specific Optimizations

**Memoized/computed properties:** Many frameworks offer computed or memoized properties that prevent recalculation within a single render cycle. Use them for derived data that is expensive to calculate:

```
// GOOD — computed property prevents recalculation within a single render cycle
computed filteredItems():
    return Item.where('category', this.selectedCategory)
        .orderBy('name')
        .get()
```

For data that should persist across requests, use caching explicitly:

```
computed stats():
    return cache.remember(
        'user-stats:' + this.userId,
        minutes(5),
        () => computeExpensiveStats()
    )
```

**Lazy/deferred component loading** defers rendering until the component is visible in the viewport. Use it for below-the-fold content:

```html
<!-- Defer rendering of heavy components until visible -->
<heavy-chart-component lazy />
```

**Debounced input updates** reduce the number of server roundtrips. For search inputs, use debouncing (e.g., 300ms) instead of updating on every keystroke.

**Avoid unnecessary re-renders.** Every state change in reactive frameworks triggers a re-render. If a property is only used for internal state and does not affect the view, consider whether it needs to be reactive at all.

## IV. Caching Strategies

Caching is trading memory for time. The trade is only worth making when the data is expensive to compute, read frequently, and changes infrequently relative to its read rate.

**Cache key design matters.** Keys must be deterministic, scoped, and invalidatable:

```
// GOOD — deterministic, scoped, includes meaningful parameters
key = 'products:category:' + categoryId + ':page:' + page + ':sort:' + sort
cache.remember(key, minutes(15), () => fetchProducts())

// BAD — vague key, no scope, impossible to invalidate selectively
cache.remember('products', 3600, () => Product.all())
```

**Set appropriate TTL (time-to-live).** Infinite caching leads to stale data; too-short TTL negates the benefit. Consider:

| Data Type | Suggested TTL | Invalidation Strategy |
|-----------|--------------|----------------------|
| User-specific dashboard | 1-5 minutes | Invalidate on relevant write |
| Product listing | 5-15 minutes | Invalidate on product update |
| Configuration/settings | 1-24 hours | Invalidate on settings change |
| Static reference data | 24 hours+ | Cache-aside on deploy |

**Cache invalidation patterns:**

```
// Tag-based invalidation (Redis/Memcached with tags)
cache.tags(['products', 'category:' + categoryId]).flush()

// Event-driven invalidation
onProductUpdated(product):
    cache.forget('product:' + product.id)
    cache.tags(['products']).flush()
```

## V. Memory Management

Server processes have finite memory. Loading unbounded datasets into memory is the most common cause of out-of-memory errors.

**Use cursor pagination for large result sets** displayed to users — it is faster than offset pagination and does not degrade on deep pages:

```
// BAD — offset pagination on large tables is slow at high page numbers
posts = Post.paginate(25)  // page 10000 requires scanning 250,000 rows

// GOOD — cursor pagination is O(1) regardless of page depth
posts = Post.cursorPaginate(25)
```

**Chunk large datasets** when processing records in batch jobs or commands:

```
// BAD — loads all records into memory at once
User.all().each((user) => processUser(user))

// GOOD — processes 500 at a time, keeping memory flat
User.chunk(500, (users) =>
    for user in users:
        processUser(user)
)

// EVEN BETTER for read-only — use generators/lazy iteration
User.lazy().each((user) => processUser(user))
```

**Watch for unbounded data structures.** Arrays and collections that grow with input size without limits are memory bombs:

```
// BAD — unbounded collection growth
allResults = []
for source in sources:
    allResults = allResults.concat(source.fetchAll())

// GOOD — process and discard, or use generators
for source in sources:
    for chunk in source.fetchChunked(100):
        processChunk(chunk)
```

## VI. Frontend Performance

**Bundle size** directly impacts load time. Every kilobyte of JavaScript must be downloaded, parsed, compiled, and executed before the page is interactive.

- Audit bundle size regularly with build-time analysis tools
- Code-split routes so users only download the JavaScript for the page they visit
- Lazy load heavy libraries (chart libraries, rich text editors) on demand
- Tree-shake unused exports — avoid barrel files (`index.js` that re-exports everything) when only a fraction is used

**Image optimization** is typically the largest single win for page weight:

```html
<!-- Lazy load below-the-fold images -->
<img src="photo.webp" alt="..." loading="lazy" decoding="async" width="800" height="600">

<!-- Preload above-the-fold hero images -->
<link rel="preload" as="image" href="hero.webp" type="image/webp">

<!-- Responsive images with srcset -->
<img
    srcset="photo-400.webp 400w, photo-800.webp 800w, photo-1200.webp 1200w"
    sizes="(max-width: 600px) 100vw, 800px"
    src="photo-800.webp"
    alt="..."
    loading="lazy"
    width="800"
    height="600"
>
```

Always set explicit `width` and `height` on images to prevent layout shift (CLS). Use modern formats (WebP, AVIF) with fallbacks.

**Preload critical resources** that the browser cannot discover early:

```html
<!-- Fonts the browser needs but discovers late -->
<link rel="preload" href="/fonts/brand.woff2" as="font" type="font/woff2" crossorigin>

<!-- CSS for above-the-fold content -->
<link rel="preload" href="/css/critical.css" as="style">
```

## VII. Concurrency & Parallel Operations

Sequential operations that could run in parallel waste wall-clock time. This applies to both server-side and client-side code.

```
// BAD — sequential API calls, total time = sum of all call times
users = http.get('https://api.example.com/users').json()
orders = http.get('https://api.example.com/orders').json()
stats = http.get('https://api.example.com/stats').json()

// GOOD — parallel, total time = longest single call
[users, orders, stats] = http.parallel([
    http.get('https://api.example.com/users'),
    http.get('https://api.example.com/orders'),
    http.get('https://api.example.com/stats'),
])
```

On the frontend, use `Promise.all` for independent async operations:

```javascript
// BAD — sequential awaits
const users = await fetchUsers();
const config = await fetchConfig();

// GOOD — parallel
const [users, config] = await Promise.all([
    fetchUsers(),
    fetchConfig(),
]);
```

**Dispatch heavy work to background jobs/queues** instead of blocking the request. Email sending, PDF generation, image processing, and webhook delivery should never happen synchronously in a web request:

```
// BAD — user waits for email to send
mailer.send(user, new WelcomeEmail(user))

// GOOD — dispatched to queue, response returns immediately
mailer.queue(user, new WelcomeEmail(user))
```

## VIII. Hot Path Optimization

The hot path is code that executes on every request, every loop iteration, or every event. Small inefficiencies here multiply across millions of executions.

- **Avoid heavy computation in middleware** that runs on every request. If a middleware does database queries or API calls, ensure it only runs on routes that need it.
- **Move invariant computation out of loops:**
  ```
  // BAD — config lookup on every iteration
  for item in items:
      if config('features.premium') and item.isPremium():
          // ...

  // GOOD — look up once
  premiumEnabled = config('features.premium')
  for item in items:
      if premiumEnabled and item.isPremium():
          // ...
  ```
- **Cache routes and config in production:** Use your framework's CLI commands to cache routes and configuration, eliminating filesystem reads on every request.

## IX. TOCTOU Anti-Patterns

Time-of-check-time-of-use (TOCTOU) occurs when you check a condition, then act on it later — but the condition may have changed between check and action. This causes both correctness and performance issues (retries, wasted work, race conditions).

```
// BAD — TOCTOU: stock could change between check and decrement
if product.stock > 0:
    product.decrement('stock')
    createOrder(product)

// GOOD — atomic operation, check and update in one query
affected = Product.where('id', product.id)
    .where('stock', '>', 0)
    .decrement('stock')

if affected:
    createOrder(product)
```

Use database-level atomicity (atomic updates, transactions with proper isolation levels, advisory locks) for operations where concurrent access is possible. Optimistic locking with version columns is another effective pattern for update conflicts.

## X. Scaling — From 1 to 1000+ Concurrent Users

Performance requirements change fundamentally with the number of concurrent users. Always check code in the context of the expected load.

### 1-10 users (prototype, internal tool)

Solid code without special optimization is enough here:
- Avoid N+1 queries (always)
- No unbounded data structures (always)
- Synchronous processing is acceptable for short tasks
- SQLite or simple DB setups work fine

### 10-100 users (small SaaS, customer app)

- **Connection pooling:** reuse DB connections instead of establishing a new one per request
- **Queue/background jobs:** email, PDF, webhooks MUST run asynchronously
- **Session handling:** replace file-based sessions with DB or Redis sessions
- **Rate limiting:** limit API endpoints and login attempts
- **Caching:** cache frequently read, rarely written data (config, permissions, feature flags)

### 100-500 users (growing app)

- **Read replicas:** distribute read queries across read replicas once the DB becomes the bottleneck
- **Query analysis:** enable the slow-query log, investigate every query >50ms
- **Asset CDN:** serve static assets (CSS, JS, images, fonts) via a CDN
- **HTTP caching:** set `Cache-Control`, `ETag`, `Last-Modified` correctly
- **Pagination:** paginate ALL lists — no unbounded result sets
- **Eager loading audit:** check every page for N+1 — at 100 users, 10 extra queries become 1000
- **Locks and concurrency:** optimistic locking for concurrent writes (order processes, bookings, inventory)

### 500-1000+ users (scale)

- **Horizontal scaling:** the app must be stateless — no local sessions, no local file uploads, no in-memory caches that live per instance
- **Redis/Memcached:** for sessions, cache, queues, rate limiting, locks
- **Database indexes:** every WHERE/ORDER BY/JOIN column must have an index. Composite indexes for common query combinations
- **Forbid lazy loading:** enable strict mode in production — every lazy load is an N+1 candidate that kills the DB at 1000 users
- **Scale queue workers:** not one worker for everything — separate queues for critical (payment) and non-critical (email) jobs
- **Health checks and circuit breakers:** protect external services (payment, mail, API) with timeouts and fallbacks
- **Database connection limits:** at 1000 concurrent requests, the DB needs 1000 connections — connection pooling is mandatory, not optional
- **Bulk operations:** use batch operations instead of 1000 individual INSERT/UPDATE statements
- **WebSocket/SSE for realtime:** polling at 1000 users is a self-inflicted DDoS — replace polling intervals with push-based updates

### Anti-Patterns at Scale

| Anti-Pattern | Why it's deadly at scale | Fix |
|-------------|----------------------|-----|
| `User.all()` without pagination | 100k users = OOM | Cursor pagination |
| Synchronous email in the request | 1000 requests = 1000 SMTP connections = timeout | Queue |
| File upload to local disk | Horizontal scaling impossible | Object storage (S3, MinIO) |
| Session in the file system | Load balancer routes to another instance → session gone | Redis/DB sessions |
| `sleep()` or `usleep()` in code | Blocks the worker thread, at 1000 requests = deadlock | Queue or event-based |
| Global variables/singletons with state | Not thread-safe, not multi-instance-safe | Dependency injection, Redis |
| Uncached config reads per request | 1000 requests = 1000 filesystem reads | Cache the config |
| Unbounded `SELECT` without LIMIT | A bot crawl with `?page=99999` kills the DB | Always LIMIT, cursor pagination |

### Code Review Checklist

Ask these questions on every performance audit:
1. **What happens if 100 users hit this page at once?** — Queries linear? Cache in place?
2. **What happens if the table has 1 million rows?** — Index in place? Pagination?
3. **What happens if the external service takes 5 seconds?** — Timeout? Queue? Fallback?
4. **What happens if two users change the same object at once?** — Locking? Atomic updates?
5. **How many DB queries does this page fire?** — Count them. >10 per page load = suspicious. >50 = critical.

## XI. Monitoring & Measurement

You cannot optimize what you do not measure. Performance work without profiling is guesswork.

- **Use development profiling tools** (query debuggers, request profilers) to catch N+1 queries, slow queries, and excessive query counts before they reach production.
- **Log slow queries** in production: configure query listeners to log queries exceeding a threshold (e.g., 100ms).
- **Track Core Web Vitals** (LCP, INP, CLS) with real user monitoring — synthetic tests do not capture the diversity of real-world conditions.
- **Set performance budgets** and alert when they are breached: maximum query count per page load, maximum response time, maximum bundle size.
- **Profile before optimizing.** A profiler shows you where time is actually spent. Optimizing code that accounts for 1% of response time yields a 1% improvement at most — find the 80% first.

## XII. 2026 Web Performance — INP, Streaming, New APIs

### INP replaces FID

Interaction to Next Paint (INP) is the Core Web Vital for responsiveness since March 2024. Targets:
- Good: < 200ms
- Needs improvement: 200-500ms
- Poor: > 500ms

INP measures the worst input delay across the page lifetime, not just first interaction. Fix patterns:
- **Break long tasks** with `scheduler.postTask()` or `setTimeout(0)` for tasks > 50ms
- **Yield to main thread** in loops: `await scheduler.yield()` (or `new Promise(r => setTimeout(r, 0))`)
- **Use `requestIdleCallback`** for non-critical work
- **CSS containment** (`contain: layout style paint`) on independent components to limit reflow scope

### Speculation Rules API

Pre-render or pre-fetch next-page navigation. Chromium-only today, but high-leverage on link-heavy pages:

```html
<script type="speculationrules">
{
  "prerender": [{
    "source": "list",
    "urls": ["/likely-next-page"]
  }],
  "prefetch": [{
    "source": "document",
    "where": { "href_matches": "/*" },
    "eagerness": "moderate"
  }]
}
</script>
```

Measured impact: 0ms navigation on prerender hits.

### View Transitions API

Smooth crossfades and shared-element transitions between page states without React Spring etc. Native, GPU-accelerated:

```js
document.startViewTransition(() => updateDOM());
```

```css
::view-transition-old(card), ::view-transition-new(card) {
  animation-duration: 250ms;
}
```

Works across SPAs and (with `@view-transition` rule) across MPA navigations on Chrome.

### Native Lazy-Loading Defaults

- `<img loading="lazy">` for all below-fold images. **Never** for hero/LCP images — set `fetchpriority="high"` instead.
- `<iframe loading="lazy">` for embeds (YouTube, maps, social).
- `<script defer>` and `<script type="module">` for non-critical JS. `async` only when execution order does not matter.

### HTTP/3 + Brotli

- HTTP/3 (QUIC): reduces latency on lossy mobile networks. Enable at the edge (Cloudflare, Fastly support it by default).
- Brotli compression at level 5-6 for static, level 11 for pre-compressed assets. ~15-25% smaller than gzip.

### Server-Component / Streaming SSR

For React/Next.js apps in 2026:
- **Server Components** for non-interactive UI — zero client JS for those components
- **Streaming SSR** with `<Suspense>` boundaries — first byte before all data loaded
- **Partial Pre-rendering (PPR)** in Next.js 15+ — static shell + streamed dynamic content

Audit signal: a page that ships 200KB+ of JS for largely static content is a Server Component conversion candidate.

### Modern Image Formats

- **AVIF** first, **WebP** fallback, **JPEG/PNG** last. AVIF is ~30% smaller than WebP at same quality.
- `<picture>` with `<source type="image/avif">` for native browser negotiation.
- Responsive images via `srcset` + `sizes` — never serve a 2000px image to a 400px viewport.
- `<img>` MUST have explicit `width` and `height` attributes (or `aspect-ratio` CSS) to prevent CLS.

### Resource Hints

```html
<link rel="preconnect" href="https://api.example.com">       <!-- TCP+TLS warmup -->
<link rel="dns-prefetch" href="https://cdn.example.com">     <!-- DNS warmup -->
<link rel="modulepreload" href="/critical.js">                <!-- ES module preload -->
<link rel="preload" as="font" href="/font.woff2" crossorigin> <!-- font preload -->
```

Use sparingly — too many `preconnect` hints (>4) compete for bandwidth.

### Anti-Patterns Specific to 2026

- **`window.matchMedia` in render path** for theme/mobile detection — use CSS `@media` + container queries
- **JSON.parse on every render** in React — `useMemo` it
- **Animating layout properties** (`top`, `left`, `width`) instead of `transform` + `opacity` — still happens, still costs
- **Unbounded `useEffect` deps arrays** — every render triggers refetch
- **Heavy useState in App-level component** — every state change re-renders the whole tree; lift state down or use Zustand/Jotai
