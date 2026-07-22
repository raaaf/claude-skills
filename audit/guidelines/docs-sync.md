---
applies_to: /[Ww]izard/|/config/|/migrations?/|_migration\.|Schema|\.env\.example
priority: mandatory
---

# Docs-Sync Checklist: Wizard-Step / Config / Schema Changes

When a diff touches wizard steps, config files, or the DB schema, the surrounding documentation drifts silently. Check each target below; "not present in this project" is a valid answer, "not checked" is not.

## Checklist

| Diff touches | Must be checked for drift |
|---|---|
| Wizard step (add/remove/reorder, labels, fields) | `CLAUDE.md` (step order / step description), `docs/manual-test-plan.md` (step walkthrough), `README.md` (feature list) |
| Config key (new, renamed, removed, default changed) | `.env.example` (matching env var), `CLAUDE.md` (documented defaults), `README.md` (setup section) |
| Schema / migration (column, table, enum, index) | `CLAUDE.md` (schema notes, CSV/export column contracts), `FEATURE_AUDIT.md` (field inventory), seeders/factories that reference the column |
| Route or page added/removed | `docs/manual-test-plan.md` (affected flows), sitemap/footer navigation, feature tests that enumerate routes |

## Rules

1. **Enumerating docs are the drift hotspot.** Any doc that lists steps, columns, routes, or config keys (test plans, CSV column contracts, step tables) breaks on every add/remove — grep the old identifier across `*.md` before closing the finding.
2. **Removed features leave doc corpses.** When code is deleted, grep docs for the feature name; a doc describing a removed page/field is an Important finding.
3. **`.env.example` mirrors config reads.** Every `env('X')` added to config needs a matching `X=` line in `.env.example`; every removed read should drop it.
4. **Doc drift severity:** wrong instructions (would mislead a developer following them) → Important; stale mention without instruction character → Minor.
5. **Lang-key call-sites on removal/rename.** When the diff removes or renames a translation-key call-site (`__('x.y')`, `trans()`, `window.translations.get`), grep the key across the codebase: zero remaining call-sites but the key still defined in `lang/*` → orphaned-key finding (Minor) in THIS diff, not one audit later. Same grep in reverse for keys removed from `lang/*` that still have call-sites (that one is Important — runtime fallback to the raw key).
