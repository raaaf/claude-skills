# Subagent 1: Feature Gaps, Product & Growth Potential

- **subagent_type:** `Explore`
- **model:** `opus`
- **maxTurns:** `30`

## Task

Understand what the app DOES — then think from a product, marketing, business, and growth perspective about what it COULD ALSO do. Actively read code, routes, models, views, components. Build a mental model of the app, its user journeys, and its business model.

**Think like a product owner + growth lead + marketing strategist. Not like a code reviewer.**

**Grounding rule (hard):** every suggestion must cite evidence from THIS repo (file, route, model, TODO, README line). A suggestion that would fit any project in the category ("dark mode", "AI feature", "mobile app") is noise and is not reported. The strongest evidence sources:

1. **Unfinished intent:** TODO/FIXME clusters around a theme, feature flags never rolled out, stub modules, commented-out feature code, abandoned work in the git history.
2. **Stated-but-undelivered:** README/docs/roadmap promises without matching code, no-op CLI flags/config options. A PRD/PRODUCT.md that the code lags behind is the strongest signal of all — and anything a decision doc explicitly rejected is NOT suggested (only the contradiction is noted).
3. **Surface asymmetries:** one-sided pairs (export without import, create without bulk-create, webhooks out but not in), entities with CRUD minus one, internally hand-rolled workarounds for a missing public API.
4. **Adjacent possible:** capabilities the existing architecture makes disproportionately cheap (plugin system one interface away, public API one route file away, an integration the data model already supports).
5. **Friction worth productizing:** things users of the project visibly build by hand around it (docs, examples, issues) that the product could absorb.

## Focus

### A. Inventory (ALWAYS first)
- What core features exist?
- What user roles exist?
- What data is managed?
- How does the app monetize (if identifiable)?
- What external services are integrated?
- What is the primary user journey?

### B. Feature Gaps (product thinking)
- What would a user of THIS project type look for next?
- Which flows are started but not thought through to the end?
- Where does a user journey end abruptly (no "next step")?
- Which CRUD operations are missing (e.g. create exists but no edit/delete)?
- Search/filter on lists that don't have one
- Export/import for data management
- Bulk operations where only single actions exist
- Notifications for events that affect the user

### C. Growth & Engagement (growth thinking)
- **Onboarding:** Is there a guided entry for new users? Or do they land on an empty page?
- **Retention:** What brings users back? Notifications, emails, dashboards, reports?
- **Virality:** Can content be shared? Are there invite flows? Social sharing? Referral?
- **Analytics:** Is what users do measured? Conversion tracking? Funnel analysis?
- **Feedback loop:** Can users give feedback? Support channel? Feature requests?

### D. Marketing & Visibility (marketing thinking)
- **Landing page:** Does one exist? Does it explain what the app does?
- **SEO content:** Blog, help pages, changelog, use cases that drive traffic?
- **Social proof:** Testimonials, customer counts, reviews, case studies?
- **CTA strategy:** Are the next steps clear for visitors?
- **Email marketing:** Newsletter signup, drip campaigns, transactional emails?

### E. Business & Monetization (business thinking)
- **Pricing:** Are there different plans/tiers? Freemium? Trial?
- **Upsell opportunities:** Premium features that could sit behind an upgrade?
- **Admin/analytics dashboard:** Can the operator see what's happening?
- **API:** Is there a public API? Could it be a product?
- **Webhook/integration opportunities:** Can the app work with other tools?

### F. Unfinished Features (what was started)
- TODOs, FIXMEs, HACKs in the code — what's behind them?
- Empty controllers/components/pages that only have a skeleton
- Routes/endpoints that are defined but not implemented
- Commented-out code that hints at planned features
- Database columns/tables that exist but are used nowhere

## Do NOT report (that's /audit's job)

- Code quality, DRY, naming
- Performance issues
- Security vulnerabilities
- A11y/SEO errors (technical)
- Missing error pages, validations

## Context

Framework: {FRAMEWORK}
Source Dirs: {SOURCE_DIRS}
Tech Stack: {TECH_STACK}
Project Context: {PROJECT_CONTEXT}

## Output Format

### Inventory
Paragraph (5-10 sentences): what the app is, does, and who uses it.

### Feature Ideas
For each idea:
- **Feature:** Concrete description (1-2 sentences)
- **Evidence:** file:line / route / README spot that anchors the suggestion in the repo (mandatory — no evidence, no idea)
- **Perspective:** Product / Growth / Marketing / Business
- **Why:** What user or business problem it solves, including trade-off in 1 sentence
- **Effort:** Small (< 1h) / Medium (1h-1d) / Large (> 1d)
- **Where to start:** Files/directories that would be affected

### Unfinished Features
For each:
- **What:** What was started
- **Status:** Stub / half done / almost done
- **Where:** File:line

No findings? Reply exactly: "Keine Findings."
