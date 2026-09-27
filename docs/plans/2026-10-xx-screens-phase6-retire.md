# Retire /screens Phase 6 (marketing renders) in favor of /store-assets

Stub. Not yet planned in detail.

## Meta
- Planned at: stub only, created alongside the `store-assets` skill, 2026-09-27
- Status: Stub, not started

## Problem
`/screens` Phase 6 (`screens/templates/marketing.html`, `screens/bin/screens.mjs`'s `marketing`
subcommand, `render-marketing.mjs`) and `/store-assets` are now two separate ways to turn a
project's own screenshots into App-Store-ready marketing images. `/store-assets` is the newer,
more capable path (real device bezels, a fixed headline/device grid, a two-phone hero
composition); Phase 6 is the older CSS-drawn-frame approach it was meant to eventually replace
(store-assets plan, 2026-09-27, "Known Costs": "Zwei Marketing-Wege ... bis zum Folgeplan").

## Trigger
Do not start this plan until `/store-assets` has completed a second real project's full run
(config + render + validate) without needing a code change to the skill itself. Before that point,
`/store-assets`'s schema and layout are still moving per-project (events was the only user through
at least 8 REVISE rounds); retiring Phase 6 first would leave projects using it with no working
replacement if `/store-assets` still needs project-specific skill changes for its second user.

## Scope (to fill in once triggered)
- Migrate any project still on `/screens` Phase 6 to a `.store-assets/store-assets.json`.
- Remove `screens/templates/marketing.html`, `screens/bin/screens.mjs`'s `marketing` subcommand,
  `render-marketing.mjs`, and Phase 6 from `screens/SKILL.md`'s Ablauf.
- Decide whether `/delegate`'s before/after proof (which currently only uses `/screens`'s catalog,
  not marketing renders) needs any change; likely not, since Phase 6 and `/store-assets` both sit
  downstream of the same view catalog.
