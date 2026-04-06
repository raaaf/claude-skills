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

## X. Scaling — Von 1 bis 1000+ gleichzeitige User

Performance-Anforderungen ändern sich fundamental mit der Anzahl gleichzeitiger User. Prüfe Code immer im Kontext der erwarteten Last.

### 1-10 User (Prototyp, internes Tool)

Hier reicht solider Code ohne spezielle Optimierung:
- N+1-Queries vermeiden (immer)
- Keine unbounded Data Structures (immer)
- Synchrone Verarbeitung ist akzeptabel für kurze Tasks
- SQLite oder einfache DB-Setups funktionieren

### 10-100 User (kleine SaaS, Kunden-App)

- **Connection Pooling:** DB-Connections wiederverwenden statt pro Request neu aufbauen
- **Queue/Background Jobs:** E-Mail, PDF, Webhooks MÜSSEN asynchron laufen
- **Session-Handling:** File-basierte Sessions durch DB- oder Redis-Sessions ersetzen
- **Rate Limiting:** API-Endpunkte und Login-Versuche begrenzen
- **Caching:** Häufig gelesene, selten geschriebene Daten cachen (Config, Permissions, Feature-Flags)

### 100-500 User (wachsende App)

- **Read Replicas:** Lese-Queries auf Read-Replicas verteilen wenn DB zum Bottleneck wird
- **Query-Analyse:** Slow-Query-Log aktivieren, alle Queries >50ms untersuchen
- **Asset-CDN:** Statische Assets (CSS, JS, Bilder, Fonts) über CDN ausliefern
- **HTTP-Caching:** `Cache-Control`, `ETag`, `Last-Modified` korrekt setzen
- **Pagination:** ALLE Listen paginieren — keine unbegrenzten Ergebnismengen
- **Eager Loading Audit:** Jede Seite auf N+1 prüfen — bei 100 Usern werden aus 10 Extra-Queries 1000
- **Locks und Concurrency:** Optimistic Locking für parallele Schreibzugriffe (Bestell-Prozesse, Buchungen, Inventar)

### 500-1000+ User (Scale)

- **Horizontal Scaling:** App muss stateless sein — keine lokalen Sessions, kein lokaler File-Upload, keine In-Memory-Caches die pro Instance leben
- **Redis/Memcached:** Für Sessions, Cache, Queues, Rate Limiting, Locks
- **Database Indexes:** Jede WHERE-/ORDER BY-/JOIN-Spalte muss einen Index haben. Composite Indexes für häufige Query-Kombinationen
- **Lazy Loading verbieten:** In Produktion Strict Mode aktivieren — jeder Lazy Load ist ein N+1 Kandidat der bei 1000 Usern die DB killt
- **Queue Workers skalieren:** Nicht ein Worker für alles — getrennte Queues für kritische (Payment) und unkritische (E-Mail) Jobs
- **Health Checks und Circuit Breaker:** Externe Services (Payment, Mail, API) mit Timeouts und Fallbacks absichern
- **Database Connection Limits:** Bei 1000 gleichzeitigen Requests braucht die DB 1000 Connections — Connection Pooling ist Pflicht, nicht optional
- **Bulk Operations:** Statt 1000 einzelne INSERT/UPDATE → Batch-Operationen verwenden
- **WebSocket/SSE für Realtime:** Polling ist bei 1000 Usern eine DDoS auf die eigene App — Polling-Intervalle durch Push-basierte Updates ersetzen

### Anti-Patterns bei Scale

| Anti-Pattern | Warum tödlich ab Scale | Fix |
|-------------|----------------------|-----|
| `User.all()` ohne Pagination | 100k User = OOM | Cursor-Pagination |
| Synchrone E-Mail im Request | 1000 Requests = 1000 SMTP-Connections = Timeout | Queue |
| File-Upload auf lokale Disk | Horizontales Scaling unmöglich | Object Storage (S3, MinIO) |
| Session in File-System | Load Balancer verteilt auf andere Instance → Session weg | Redis/DB Sessions |
| `sleep()` oder `usleep()` in Code | Blockiert Worker-Thread, bei 1000 Requests = Deadlock | Queue oder Event-basiert |
| Globale Variablen/Singletons mit State | Nicht thread-safe, nicht multi-instance-safe | Dependency Injection, Redis |
| Uncached Config-Reads pro Request | 1000 Requests = 1000 Filesystem-Reads | Config cachen |
| Unbounded `SELECT` ohne LIMIT | Ein Bot-Crawl mit `?page=99999` killt die DB | Immer LIMIT, Cursor-Pagination |

### Checkliste für Code-Review

Bei jedem Performance-Audit diese Fragen stellen:
1. **Was passiert wenn 100 User gleichzeitig diese Seite aufrufen?** — Queries linear? Cache vorhanden?
2. **Was passiert wenn die Tabelle 1 Million Rows hat?** — Index vorhanden? Pagination?
3. **Was passiert wenn der externe Service 5 Sekunden braucht?** — Timeout? Queue? Fallback?
4. **Was passiert wenn zwei User gleichzeitig dasselbe Objekt ändern?** — Locking? Atomic Updates?
5. **Wie viele DB-Queries feuert diese Seite?** — Zählen. >10 pro Pageload = verdächtig. >50 = kritisch.

## XI. Monitoring & Measurement

You cannot optimize what you do not measure. Performance work without profiling is guesswork.

- **Use development profiling tools** (query debuggers, request profilers) to catch N+1 queries, slow queries, and excessive query counts before they reach production.
- **Log slow queries** in production: configure query listeners to log queries exceeding a threshold (e.g., 100ms).
- **Track Core Web Vitals** (LCP, INP, CLS) with real user monitoring — synthetic tests do not capture the diversity of real-world conditions.
- **Set performance budgets** and alert when they are breached: maximum query count per page load, maximum response time, maximum bundle size.
- **Profile before optimizing.** A profiler shows you where time is actually spent. Optimizing code that accounts for 1% of response time yields a 1% improvement at most — find the 80% first.
