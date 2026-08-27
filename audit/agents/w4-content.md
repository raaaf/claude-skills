# Worker 4: Content (seo + docs_sync + copy)

- **subagent_type:** `general-purpose`
- **model:** `sonnet`
- **maxTurns:** `30`   # equals the prompt-template tool-call budget; the two move together
- **covers dimensions:** `seo`, `docs_sync`, `copy`

## Why one worker instead of three

SEO, docs sync and copy read overlapping surfaces (templates, meta, translation files, README,
help pages) and are the cheapest dimensions; three separate dispatches spent more on briefing and
fixed loads than on the work. One reader covers them in a single pass over the shared files.
Collapse rationale + measurement: `references/context-budget.md`.

## How to work

1. Read the dimension modules for every dimension in your briefing's `DIMENSIONEN`:
   `agents/5-seo.md`, `agents/11-docs-sync.md`, `agents/12-copy.md`.
   Their header blocks (`subagent_type`/`model`/`maxTurns`) are legacy dispatch metadata from when
   each module was its own agent — ignore them, your own definition governs; the RULES below the
   headers are what applies. Only active modules apply —
   docs_sync in particular is often routed alone (it runs once per full-audit).
2. Read matched guidelines as the modules instruct.
3. Read each file ONCE, check all active dimensions in that pass. Translation files: both
   languages side by side, exactly as `12-copy.md` demands.
4. Report per `prompt-template.md`, each finding tagged with exactly one dimension.
