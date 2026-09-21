---
applies_to: /[Ww]izard/|/config/|/migrations?/|_migration\.|Schema|\.env\.example|(^|/)routes?/|(^|/)pages?/|/page\.(t|j)sx?$|urls\.py
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
| Tests added/removed (incl. by fix agents mid-audit) | Every numeric "N Tests" claim in `README.md`/`CLAUDE.md` — `bin/check-test-count-drift.sh` flags candidates; confirm against the actual test-run output, not the source count |

## Rules

0. **The deleted-path half is checked mechanically, not by reading.** `bin/check-docs-path-drift.sh` runs in Phase 1 and reports every live doc that still names a file the diff deleted or renamed away (`DOCSPATH {doc}:{line}`). Do not re-derive those by hand and do not treat a clean result as "docs are in sync" — the script only decides the question that needs no judgment. Everything below is what is left: whether the surviving text is still TRUE. This split exists because docs drift is the most frequent finding class in this pipeline (18 of 27 audits) and years of prose reminders in this very file did not move that number.
1. **Enumerating docs are the drift hotspot.** Any doc that lists steps, columns, routes, or config keys (test plans, CSV column contracts, step tables) breaks on every add/remove — grep the old identifier across `*.md` before closing the finding.
2. **Removed features leave doc corpses.** When code is deleted, grep docs for the feature name; a doc describing a removed page/field is an Important finding.
3. **`.env.example` mirrors config reads.** Every `env('X')` added to config needs a matching `X=` line in `.env.example`; every removed read should drop it.
4. **Doc drift severity:** wrong instructions (would mislead a developer following them) → Important; stale mention without instruction character → Minor.
5. **Lang-key call-sites on removal/rename.** When the diff removes or renames a translation-key call-site (`__('x.y')`, `trans()`, `window.translations.get`), grep the key across the codebase: zero remaining call-sites but the key still defined in `lang/*` → orphaned-key finding (Minor) in THIS diff, not one audit later. Same grep in reverse for keys removed from `lang/*` that still have call-sites (that one is Important — runtime fallback to the raw key).
6. **Cited `file:line` ranges are claims too.** A doc that cites `Path.swift:268-273` (plans, QA defect logs, retro notes) asserts what is AT those lines. When the diff touches a file that any doc cites by line, open the citation: if the named function or section no longer starts within +/-5 lines of the cited range, the citation is stale (Minor; Important when the doc gives instructions that depend on it). The mechanical path check only sees deleted paths, not shifted lines, and this is the top recurring pattern in the store (3x by 2026-09-20: `docs/plans/*.md` and `docs/qa/defects.md` citing `RecipeDetailView.swift` lines that moved under active edits).
