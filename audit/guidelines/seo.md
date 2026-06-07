# SEO Guidelines

Search engine optimization is not a marketing afterthought — it is a technical discipline that determines whether your carefully built application is discoverable at all. Every page that lacks a proper title, every image without alt text, every broken heading hierarchy is a missed signal to search engines and a worse experience for the users who find you through search.

## I. Meta Tags

The `<title>` and `<meta name="description">` are the most important on-page SEO elements. They are what appears in search results and are the first impression a potential visitor has of your page.

```html
<head>
    <!-- Title: 50-60 characters, unique per page, primary keyword near the front -->
    <title>Project Management for Remote Teams | AppName</title>

    <!-- Description: 120-160 characters, compelling, includes call to action -->
    <meta name="description" content="Manage remote teams with real-time collaboration, task tracking, and automated standups. Start your free trial today.">

    <!-- Canonical: the single authoritative URL for this content -->
    <link rel="canonical" href="https://example.com/features/project-management">

    <!-- Robots: control indexing per page when needed -->
    <meta name="robots" content="index, follow">
    <!-- For pages that should not be indexed: -->
    <meta name="robots" content="noindex, nofollow">
</head>
```

**Every page must have a unique `<title>`.** Duplicate titles across pages signal to search engines that the pages are redundant. Set titles per view or via a shared layout variable:

```html
<!-- In layout template -->
<title>{{ pageTitle || 'Default Site Title' }}</title>

<!-- In child view or component -->
<!-- Set pageTitle = 'Pricing Plans | AppName' -->
```

**Canonical URLs** prevent duplicate content issues. If the same content is accessible at multiple URLs (with/without trailing slash, with query parameters, paginated pages), the canonical tells search engines which version to index:

```html
<!-- On paginated pages, canonical points to the first page or the series -->
<link rel="canonical" href="https://example.com/blog">

<!-- On filtered/sorted views, canonical points to the unfiltered version -->
<link rel="canonical" href="https://example.com/products">
```

## II. Open Graph & Social Meta Tags

When your pages are shared on social media, messaging apps, or Slack, Open Graph tags control the preview card. Without them, platforms guess — poorly.

```html
<!-- Open Graph (Facebook, LinkedIn, Slack, etc.) -->
<meta property="og:type" content="website">
<meta property="og:title" content="Project Management for Remote Teams">
<meta property="og:description" content="Manage remote teams with real-time collaboration and task tracking.">
<meta property="og:image" content="https://example.com/images/og-project-management.jpg">
<meta property="og:image:width" content="1200">
<meta property="og:image:height" content="630">
<meta property="og:url" content="https://example.com/features/project-management">
<meta property="og:site_name" content="AppName">

<!-- Twitter Card -->
<meta name="twitter:card" content="summary_large_image">
<meta name="twitter:title" content="Project Management for Remote Teams">
<meta name="twitter:description" content="Manage remote teams with real-time collaboration and task tracking.">
<meta name="twitter:image" content="https://example.com/images/og-project-management.jpg">
```

**OG image dimensions:** 1200x630 pixels is the universal safe size. Always use absolute URLs for images. Test previews with the sharing debuggers provided by each platform.

## III. Heading Hierarchy

Headings communicate document structure to both search engines and assistive technologies. A broken hierarchy tells crawlers that your content is disorganized.

| Rule | Explanation |
|------|-------------|
| Single `<h1>` per page | The page title — matches or closely relates to the `<title>` tag |
| No skipped levels | `<h1>` followed by `<h2>`, then `<h3>` — never jump from `<h1>` to `<h3>` |
| Headings reflect content sections | Each heading introduces the section that follows it |
| Don't use headings for styling | If you need large bold text that is not a section heading, use CSS on a `<p>` or `<span>` |

```html
<!-- GOOD structure -->
<h1>Remote Team Management Guide</h1>
  <h2>Setting Up Communication Channels</h2>
    <h3>Synchronous Tools</h3>
    <h3>Asynchronous Tools</h3>
  <h2>Task Tracking Best Practices</h2>
    <h3>Daily Standups</h3>
    <h3>Sprint Planning</h3>
```

## IV. Semantic HTML for Content

Search engines parse HTML structure, not visual appearance. Semantic elements provide meaning that `<div>` and `<span>` cannot:

- `<article>` for self-contained content (blog posts, product cards, comments)
- `<section>` for thematic groupings within a page
- `<nav>` for navigation blocks (primary nav, breadcrumbs, pagination)
- `<aside>` for tangentially related content (sidebars, related articles)
- `<time datetime="2026-03-22">` for dates — machines parse the `datetime` attribute
- `<address>` for contact information
- `<blockquote cite="...">` for quotations with attribution

Using the right elements helps search engines understand content relationships, extract structured information, and present rich results.

## V. Structured Data / JSON-LD

Structured data tells search engines exactly what your content represents, enabling rich results (star ratings, FAQ dropdowns, breadcrumb trails, event listings) that dramatically increase click-through rates.

Always use JSON-LD format in a `<script>` tag — it is cleaner than microdata and does not mix with your HTML:

```html
<!-- Organization (site-wide, on homepage) -->
<script type="application/ld+json">
{
    "@context": "https://schema.org",
    "@type": "Organization",
    "name": "AppName",
    "url": "https://example.com",
    "logo": "https://example.com/images/logo.png",
    "sameAs": [
        "https://twitter.com/appname",
        "https://linkedin.com/company/appname"
    ]
}
</script>

<!-- BreadcrumbList (on every page with breadcrumbs) -->
<script type="application/ld+json">
{
    "@context": "https://schema.org",
    "@type": "BreadcrumbList",
    "itemListElement": [
        { "@type": "ListItem", "position": 1, "name": "Home", "item": "https://example.com" },
        { "@type": "ListItem", "position": 2, "name": "Features", "item": "https://example.com/features" },
        { "@type": "ListItem", "position": 3, "name": "Project Management" }
    ]
}
</script>

<!-- FAQ Page -->
<script type="application/ld+json">
{
    "@context": "https://schema.org",
    "@type": "FAQPage",
    "mainEntity": [
        {
            "@type": "Question",
            "name": "How does the free trial work?",
            "acceptedAnswer": {
                "@type": "Answer",
                "text": "Start a 14-day free trial with full access. No credit card required."
            }
        }
    ]
}
</script>

<!-- Article / Blog Post -->
<script type="application/ld+json">
{
    "@context": "https://schema.org",
    "@type": "Article",
    "headline": "Remote Team Management Guide",
    "author": { "@type": "Person", "name": "Jane Smith" },
    "datePublished": "2026-03-15",
    "dateModified": "2026-03-20",
    "image": "https://example.com/images/remote-teams.jpg",
    "publisher": {
        "@type": "Organization",
        "name": "AppName",
        "logo": { "@type": "ImageObject", "url": "https://example.com/images/logo.png" }
    }
}
</script>
```

Validate structured data with Google's Rich Results Test before deploying. Invalid markup is worse than no markup — it can trigger manual actions.

## VI. Image Optimization

Images are typically the largest assets on a page. Unoptimized images slow page load, hurt Core Web Vitals scores, and waste bandwidth.

```html
<!-- Always set dimensions to prevent layout shift -->
<img
    src="product.webp"
    alt="Blue wireless headphones with noise cancellation"
    width="600"
    height="400"
    loading="lazy"
    decoding="async"
>

<!-- Hero images: preload, don't lazy load -->
<link rel="preload" as="image" href="hero.webp" type="image/webp">
<img src="hero.webp" alt="..." width="1200" height="600">
```

| Practice | Implementation |
|----------|---------------|
| Modern formats | Serve WebP or AVIF with `<picture>` fallback to JPEG |
| Responsive sizes | Use `srcset` and `sizes` to serve appropriately sized images |
| Lazy loading | `loading="lazy"` on all images below the fold |
| Explicit dimensions | Always set `width` and `height` to reserve layout space |
| Meaningful alt text | Describe the image's purpose, not just its appearance |
| File naming | Use descriptive, hyphenated filenames: `blue-wireless-headphones.webp` |

**Do not lazy load above-the-fold images** — especially the LCP (Largest Contentful Paint) element. Lazy loading the hero image delays the most important content metric.

## VII. URL Structure

URLs are permanent. Changing them breaks bookmarks, inbound links, and search engine trust. Design them carefully from the start.

| Principle | Good | Bad |
|-----------|------|-----|
| Readable slugs | `/blog/remote-team-management` | `/blog/post?id=12847` |
| Lowercase, hyphenated | `/features/task-tracking` | `/Features/Task_Tracking` |
| No unnecessary nesting | `/blog/seo-guide` | `/blog/2026/03/22/seo-guide` |
| No file extensions | `/about` | `/about.html` |
| Content pages without query params | `/products/headphones` | `/products?category=headphones` |
| Trailing slashes: pick one, enforce it | Always or never — be consistent | Mixing both creates duplicate content |

When you must change a URL, always implement a 301 (permanent) redirect from the old URL to the new one. Never 302 — that tells search engines the old URL is still the canonical one.

## VIII. Internal Linking

Internal links distribute page authority (link equity) across your site and help search engines discover and understand the relationship between pages.

- **Link from high-authority pages** (homepage, popular blog posts) to important pages you want to rank
- **Use descriptive anchor text** — the linked text should describe the destination, not "click here":
  ```html
  <!-- BAD -->
  <a href="/features">Click here</a> to learn more.

  <!-- GOOD -->
  Learn more about our <a href="/features">project management features</a>.
  ```
- **Breadcrumbs** provide both navigational context and internal linking. Implement them with structured data (see Section V).
- **Related content links** at the end of blog posts keep users engaged and distribute authority
- **Avoid orphan pages** — every important page should be reachable from at least one other page through a link
- **Fix broken internal links** regularly — 404s waste crawl budget and frustrate users

## IX. Mobile-Friendliness

Google uses mobile-first indexing — it crawls and ranks based on the mobile version of your page. If your site is not mobile-friendly, it will not rank well regardless of desktop quality.

```html
<!-- Viewport meta tag — required for responsive design -->
<meta name="viewport" content="width=device-width, initial-scale=1">
```

- Ensure all content is accessible on mobile — nothing hidden behind "desktop only" interactions
- Touch targets must be at least 44x44 pixels (see Accessibility guidelines)
- Text must be readable without zooming — minimum 16px font size for body text
- No horizontal scrolling — content must fit the viewport width
- Test with Google's Mobile-Friendly Test and real devices, not just browser dev tools

## X. Core Web Vitals

Core Web Vitals are Google's page experience metrics. They measure real-user experience and directly impact search rankings.

### LCP (Largest Contentful Paint) — target: under 2.5 seconds

LCP measures when the largest visible element (usually a hero image, video poster, or large text block) finishes rendering.

**Common causes of poor LCP and fixes:**

| Cause | Fix |
|-------|-----|
| Large, unoptimized hero image | Compress, serve WebP/AVIF, use `srcset` |
| Hero image lazy-loaded | Remove `loading="lazy"` from LCP element, add `<link rel="preload">` |
| Render-blocking CSS/JS | Inline critical CSS, defer non-critical JS |
| Slow server response (TTFB) | Server-side caching, CDN, optimize database queries |
| Web fonts blocking render | Use `font-display: swap`, preload critical fonts |

### INP (Interaction to Next Paint) — target: under 200 milliseconds

INP measures the responsiveness of all user interactions throughout the page lifecycle — clicks, taps, key presses.

**Common causes of poor INP and fixes:**

| Cause | Fix |
|-------|-----|
| Long JavaScript tasks blocking main thread | Break into smaller tasks, use `requestIdleCallback` |
| Heavy event handlers | Debounce/throttle, offload to Web Workers |
| Server roundtrip for simple interactions | Use client-side JavaScript for UI-only state changes |
| Large DOM re-renders | Minimize DOM size, use virtual scrolling for long lists |

### CLS (Cumulative Layout Shift) — target: under 0.1

CLS measures unexpected layout movement — elements shifting position after the page appears stable.

**Common causes of poor CLS and fixes:**

| Cause | Fix |
|-------|-----|
| Images without dimensions | Always set `width` and `height` attributes |
| Dynamically injected content above viewport | Reserve space with min-height or aspect-ratio |
| Web fonts causing text reflow | Use `font-display: swap` with size-adjusted fallback |
| Ads or embeds without reserved space | Set explicit container dimensions |
| Dynamic component re-renders shifting layout | Use stable keys and stable DOM structure |

## XI. Sitemap & Robots.txt

**`robots.txt`** tells crawlers which parts of your site to access. Place it at the root:

```
User-agent: *
Disallow: /admin/
Disallow: /api/
Disallow: /dashboard/
Allow: /

Sitemap: https://example.com/sitemap.xml
```

Do not block CSS or JS in `robots.txt` — search engines need to render your pages to evaluate them. Only block truly private paths (admin panels, API endpoints, user dashboards).

**XML Sitemap** lists all pages you want indexed. Include only canonical, indexable pages:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">
    <url>
        <loc>https://example.com/</loc>
        <lastmod>2026-03-22</lastmod>
        <changefreq>weekly</changefreq>
        <priority>1.0</priority>
    </url>
    <url>
        <loc>https://example.com/features</loc>
        <lastmod>2026-03-15</lastmod>
        <changefreq>monthly</changefreq>
        <priority>0.8</priority>
    </url>
</urlset>
```

Generate sitemaps dynamically using a sitemap generation library or framework plugin and submit them to Google Search Console. Keep sitemaps under 50,000 URLs and 50 MB — use sitemap indexes for larger sites.

## XII. Multilingual Sites (hreflang)

If your site serves content in multiple languages or targets multiple regions, `hreflang` tags prevent duplicate content issues and ensure users see the right language version in search results.

```html
<link rel="alternate" hreflang="de" href="https://example.com/de/funktionen">
<link rel="alternate" hreflang="en" href="https://example.com/en/features">
<link rel="alternate" hreflang="x-default" href="https://example.com/en/features">
```

- Every page in every language must reference all other language versions AND itself
- `x-default` indicates the fallback for users whose language is not specifically targeted
- Use ISO 639-1 language codes (`de`, `en`, `fr`) optionally combined with ISO 3166-1 region codes (`de-AT`, `en-US`)
- Implement in `<head>`, HTTP headers, or the XML sitemap — pick one method and be consistent
- Each hreflang page must have its own canonical pointing to itself, not to another language version

Incorrect hreflang implementation is worse than none — validate with Google Search Console's International Targeting report and third-party hreflang validators.

## XIII. Answer Engine Optimization (AEO) — 2026

Search increasingly happens inside AI answer engines (ChatGPT, Perplexity, Google AI Overviews, Claude). They cite sources differently than classic search. Optimize for both.

### Content patterns that AI engines cite

- **Direct answer in first paragraph.** AI engines pull "lead paragraphs" as quote candidates. Bury the answer 5 paragraphs deep and it does not get cited.
- **Lists and tables** are over-represented in AI citations vs flowing prose. Convert prose to bullets where possible.
- **Question-as-heading + clear answer below** matches how AI engines retrieve. `## What is X?` followed by 1-2 sentence definition.
- **Statistics with sources** get cited. "User retention dropped 23% (source: Mixpanel cohort, 2025-Q3)" beats "user retention dropped a lot".
- **Recency signal.** Last-updated dates in HTML (`<time>` element) and structured data. AI engines de-prioritize undated content.

### Structured data for AEO

Beyond standard JSON-LD, prioritize:
- **`FAQPage`** schema for question-answer sections
- **`HowTo`** schema for instructional content
- **`Article` with `dateModified`** explicitly set
- **`Author` with `sameAs`** pointing to social/scholar profiles — establishes author E-E-A-T
- **`Speakable`** for audio-podcast/voice-search content

### llms.txt

Emerging standard (proposed late 2024, adopted 2025-2026) for telling LLM crawlers what content is safe to cite vs proprietary:

```
/llms.txt
```

Format: markdown listing canonical URLs + summaries. Anthropic, OpenAI, Perplexity respect it for citation context. Cloudflare offers automatic generation.

### IndexNow

Push protocol (Microsoft, Yandex, with Google testing) — notify search engines instantly on content update instead of waiting for crawl. Free, simple POST endpoint. CMS plugins exist for WordPress, Drupal.

### Anti-Patterns 2026

- **AI-generated content without editorial pass.** Detection is reliable; ranking penalty exists. AI-assisted writing is fine, AI-only is risk.
- **Keyword stuffing reborn as "prompt stuffing"** — repeating likely-AI-query phrases. Search engines pattern-match this.
- **Cloaking AI crawlers** (different content to GPTBot vs Googlebot). Both Google and Anthropic explicitly flag this as policy violation.
- **Schema for content that does not exist** — claiming `FAQPage` when the page is not Q&A format. AI engines verify before citing.

### Audit Implications

For content-heavy sites (blog, docs, marketing), check:
- Does each page answer one clear question in the first 50 words?
- Are FAQs marked up with `FAQPage` JSON-LD?
- Is `dateModified` accurate?
- Does `llms.txt` exist if the site has content worth being cited?
