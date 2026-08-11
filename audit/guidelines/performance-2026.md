# Performance: 2026 Additions

Continuation of performance.md (section XII). Always read together with performance.md.

## Contents
- XII. 2026 Web Performance — INP, Streaming, New APIs

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

### CSS containment visual gotcha

`contain: paint` (also via `layout style paint`) and `content-visibility: auto` clip everything a child paints OUTSIDE the container box — including box-shadow, outline and focus/hover rings that extend past the border edge. Symptoms: a hover ring or elevation shadow that silently disappears, but only on cards inside the contained ancestor.

Checklist before flagging or changing container-driven hover effects:
- Grep ancestors of the affected component for `contain:` and `content-visibility` before assuming the ring/shadow CSS is wrong.
- Fixes that keep containment: render the ring inside the box (`outline-offset` negative, inset ring), or move the effect to the contained element itself instead of a child.
- Removing containment is a performance regression — treat as last resort and flag the trade-off.

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

### Swift Hot-Path Pitfalls

Observed repeatedly in native-macOS audits (learning log 2026-07-09):

- **Character-based String APIs on byte-oriented data.** `split(separator: "\n")`, `trimmingCharacters`, and friends operate on grapheme clusters, allocate per line, and mis-handle CRLF (`\r\n` is ONE Character). For file formats (G-code, STL, CSV) parse on the UTF-8 view or raw bytes.
- **`Data.firstIndex(of:)` in scan loops.** The generic Collection scan is ~25x slower than a `withUnsafeBytes` + `memchr` scan (measured). For chunked parsers, translate raw-buffer offsets back to slice-relative indices carefully — `Data` slices keep non-zero `startIndex`.
- **Dictionary copy-on-write on accumulate.** `var bucket = dict[key] ?? default; bucket.x.append(...); dict[key] = bucket` copies the whole accumulated value per iteration (refcount 2 at append time) — O(n²) per bucket. Use `dict[key, default: ...].x.append(...)` (`_modify` accessor, in place).
- **Per-iteration array literals in hot loops.** `for v in [a, b, c]` heap-allocates each pass; unroll or use tuples in million-iteration loops.
