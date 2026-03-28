# Subagent 5: SEO & Semantic HTML

- **subagent_type:** `seo-auditor`
- **model:** `haiku`
- **maxTurns:** `10`

## Fokus

Meta Tags, Semantic HTML, Structured Data, Core Web Vitals.

**Vollstaendige Guidelines:** Lies `guidelines/seo.md` im Skill-Verzeichnis und pruefe den Code gegen alle dort beschriebenen Regeln.

## Full-Audit Fokus (zusaetzlich)

Meta-Tags, Heading-Hierarchie (`<h1>`-`<h6>`), Semantic HTML (`<main>`, `<nav>`, `<header>`, `<footer>`), Open Graph Tags (`og:title`, `og:description`, `og:image`), Structured Data (JSON-LD), URL-Struktur (sprechende URLs, keine ID-only-Routen), Core Web Vitals Hints (Lazy Loading, Image Dimensions, Font Display), Sitemap-Referenzen, Canonical Tags (`<link rel="canonical">`), Hreflang (falls multilingual).

## Ueberspringen wenn

- Keine Frontend-Dateien im Diff/Batch
- Nur Template-Partials/Components ohne `<head>`-Bereich (keine `<meta>`, keine Layout-Dateien)
