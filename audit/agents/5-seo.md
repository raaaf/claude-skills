# Dimension: SEO & Semantic HTML

## Look for

Meta tags, semantic HTML, structured data, Core Web Vitals. Applies to ALL views — public AND
app-internal (admin, dashboard, settings). Heading hierarchy, semantic HTML and accessibility are
universal. Read `guidelines/seo.md` in full.

Systematically: heading hierarchy (`<h1>`-`<h6>`), semantic HTML (`<main>`, `<nav>`, `<header>`,
`<footer>`, `<section>`, `<article>`). For public pages additionally: meta tags, Open Graph tags,
structured data (JSON-LD), URL structure, Core Web Vitals hints, sitemap, canonical tags, hreflang.

Skip when no frontend files are in scope.

**Defect class calibrated against a real finding (2026-09-05 audit):** protected/access-gated page
content leaking through a metadata sink that a first-party access check does not cover — meta
description, Open Graph, Twitter Card, JSON-LD, sitemap entry, or `llms.txt`/`llms-full.txt` for a
page an anonymous or unauthorized visitor cannot open directly. Check every metadata sink
independently, including ones added by a third-party SEO plugin, not just the page body.

## Severity

No `Critical` — a broken meta tag or heading hierarchy does not lose data or grant access. Missing
required meta/structured data that harms indexing is `Important`; everything else `Minor`.

Examples (2026-09-05 audit): `Important` — an access-gated page stayed indexable through its meta
description, Open Graph, JSON-LD and sitemap entry, exactly the metadata-sink gap this severity
level covers. `Minor` — `goldene-strategie`'s `SeoMetaDescriptionTest` fixtures still spoke of
"Stiftungen", stale test copy with no ranking impact.

## Output

Reply with the specialist schema: `findings[{id, severity, confidence, files, issue, impact}]`
plus `coverage`. Every ID is prefixed `seo-`. Set `coverage` to `COVERAGE: full` or
`COVERAGE: partial | not read: {file1}, {file2}`.
