---
name: store-assets
description: "Generates App Store and Play Store screenshots (stills) and an App Preview video from a folder of app screens plus a project config, so store images no longer need hand-built Figma frames per release. Look (fonts, colors, logo, device pose) comes from the project's own store-assets.json, never hardcoded in the skill. Use when the user runs /store-assets, wants to regenerate App Store or Play Store screenshots, or needs an App Preview video."
when_to_use: "/store-assets, Store-Screenshots erzeugen, App-Store-Bilder, Play-Store-Bilder, App Preview Video"
argument-hint: "[--project <path>] [--video]"
model: inherit
effort: medium
allowed-tools:
  - Bash
  - Read
  - Edit
  - Write
  - Glob
  - Grep
---

# /store-assets: Store Screenshots and App Preview from Code

Generates store-ready stills (Meilenstein A) and, once the HyperFrames spike has proven the
sub-composition mechanism, an App Preview video (Meilenstein B) from a project's own app screens
and a project-local config (`.store-assets/store-assets.json`). Pattern follows `screens/`: this
`SKILL.md` orchestrates, `bin/*.mjs` is deterministic, `references/*.md` holds specs and schema,
`templates/` holds the rendering surface. No brand values live in this skill; everything (fonts,
colors, logo, device pose, headlines) comes from the target project's config.

## Ablauf

1. **Config lesen.** Read `<project>/.store-assets/store-assets.json`. Missing file: report and
   stop (nothing to render). Schema: `references/config-schema.md`.
2. **Headlines-Gate.** Every scene's headline/subline per locale needs `reviewed: true` with a
   `reviewed_hash` (SHA-256 of `headline + subline`) matching the current text. Any mismatch or
   `reviewed: false`: report which scenes are unreviewed, do not render until the project owner
   confirms them (Gate 1 in the store-assets plan).
3. **Muster-Gate.** Before a full render across every scene/locale/format, render one representative
   sample (hero scene, one format, one locale) and show it next to the project's previous store
   images for a look-and-feel approval (Gate 2).
4. **Vollrender.** `bin/render.mjs --project <path>` renders every scene x locale x format into
   `<project>/native/store-assets/generated/<format>/<locale>/NN-<id>.jpg`, plus a contact-sheet
   `generated/index.html`.
5. **Validator.** `bin/validate.mjs --project <path>` checks exact pixel dimensions, no alpha
   channel, sRGB profile, file size, per-format image counts, and that every rendered scene is
   `reviewed: true` with a matching hash. Exit 0 only when every check passes.
6. **Video (optional, Meilenstein B).** Only once `templates/preview.html` and
   `bin/render-video.mjs` exist (they do not yet — see `docs/plans/2026-09-27-store-assets-skill.md`
   Step 10). Until then, stills are the whole deliverable.

Before any full render, check `references/store-specs.md`'s `Stand` date: if it is older than 6
months, re-verify the sizes against the source URLs there before trusting them.

## Runtime

Playwright: the target project's own `playwright`/`@playwright/test` devDependency always wins
(any installed version, no pin comparison). Only when the project has neither, fall back to
`npx -y playwright@<pinned version, see references/store-specs.md>` plus
`npx playwright install chromium` with `PLAYWRIGHT_BROWSERS_PATH=~/.cache/store-assets/browsers`
(only when that cache does not already have the browser — never re-download it, and never install
a Chromium copy under this skill's own directory or the project's `node_modules`).

HyperFrames (video only, Meilenstein B): exact pinned version in
`references/store-specs.md` "HyperFrames version", never `npx hyperframes` unpinned (a floating
`npx hyperframes render` silently pulls the latest published version).

## Devices

`templates/devices/iphone.svg` and `templates/devices/android.svg` are frame-only SVGs (no Apple
marketing asset): a bezel with a transparent viewport window. `templates/scene.html` places the
project's screen PNG behind the frame, aligned to that window, then applies pose (rotation,
translation) from the scene's config entry.

## Edge Cases

- Source PNG missing for a locale/theme: pre-flight in `render.mjs` fails before any render, lists
  every missing combination.
- Source PNG aspect ratio differs from the device viewport: `object-fit: cover` from the top, and
  the contact sheet flags the image with a visible warning.
- A font fails to load (`document.fonts.check`): abort, no silent fallback font in the output.
- Headline text too long for its box: CSS `clamp()` down to a minimum size; below that, error.
- Headline or subline text changed after Gate 1 approval: `reviewed_hash` no longer matches ->
  `reviewed` is treated as `false` -> validator fails.
- Chromium not cached and no network: stop with the exact install command
  (`npx playwright install chromium`), do not attempt a partial render.

## References

- `references/config-schema.md` — every `store-assets.json` field.
- `references/store-specs.md` — exact store sizes, formats, limits, source URLs, HyperFrames
  version, Playwright pin.
