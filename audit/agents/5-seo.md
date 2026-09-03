# Subagent 5: SEO & Semantic HTML

- **subagent_type:** `audit-content-worker` (this module is read BY w4-content.md, never dispatched on its own; `seo-auditor` here was a stale reference to a type that was never registered)
- **model:** `sonnet`
- **maxTurns:** `10`

## Focus

Meta tags, semantic HTML, structured data, Core Web Vitals. Applies to ALL views — public AND app-internal (admin, dashboard, settings etc.). Heading hierarchy, semantic HTML, and accessibility are universal.

**Complete guidelines:** Read `guidelines/seo.md` in the skill directory and check the code against all rules described there.

## Full-Audit Focus (additional)

Heading hierarchy (`<h1>`-`<h6>`), semantic HTML (`<main>`, `<nav>`, `<header>`, `<footer>`, `<section>`, `<article>`). For public pages, additionally: meta tags, Open Graph tags, structured data (JSON-LD), URL structure, Core Web Vitals hints, sitemap, canonical tags, hreflang.

## Skip When

- No frontend files in the diff/batch
