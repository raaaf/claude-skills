# `.store-assets/store-assets.json` schema

Lives inside the target project, never inside this skill (Non-Goal: no brand values hardcoded
here). One config per project.

```json
{
  "brand": {
    "headline_font": { "family": "Holdstone", "path": "resources/fonts/Holdstone.woff2" },
    "subline_font": { "family": "Inter Variable", "path": "public/fonts/Inter.woff2" },
    "logo": "public/images/auth/events-logo.svg"
  },
  "locales": ["de", "en"],
  "formats": {
    "ios-6.9": { "width": 1320, "height": 2868 },
    "play-phone": { "width": 1440, "height": 2560 },
    "play-feature": { "width": 1024, "height": 500 }
  },
  "scenes": [
    {
      "id": "01-hero",
      "layout": "combo",
      "combo": {
        "front": {
          "source": { "de": { "dark": "tests/Browser/screenshots/marketing/appstore/de/dark/eventpage-top.png" }, "en": { "dark": "tests/Browser/screenshots/marketing/appstore/en/dark/eventpage-top.png" } },
          "crop_top_px": 210,
          "ios_color": "Black"
        },
        "back": {
          "source": { "de": { "dark": "tests/Browser/screenshots/marketing/appstore/de/dark/bring-list.png" }, "en": { "dark": "tests/Browser/screenshots/marketing/appstore/en/dark/bring-list.png" } },
          "crop_top_px": 270,
          "ios_color": "Silver"
        }
      },
      "background": "#04081f",
      "foreground": "#ffffff",
      "text": {
        "de": { "headline": "Schluss mit dem WhatsApp-Chaos.", "reviewed": false, "reviewed_hash": null },
        "en": { "headline": "End the WhatsApp chaos.", "reviewed": false, "reviewed_hash": null }
      }
    },
    {
      "id": "08-expenses",
      "source": {
        "de": { "light": "tests/Browser/screenshots/marketing/appstore/de/light/expenses.png" },
        "en": { "light": "tests/Browser/screenshots/marketing/appstore/en/light/expenses.png" }
      },
      "background": "#f7f7f7",
      "foreground": "#04081f",
      "crop_top_px": 0,
      "pills": {
        "de": ["Erstes Event kostenlos", "Kein Account für Gäste"],
        "en": ["First event is free", "No account needed for guests"]
      },
      "text": {
        "de": {
          "headline": "Schluss mit Excel für die Kostenteilung.",
          "subline": "Ausgaben eintragen, automatisch fair aufgeteilt.",
          "reviewed": false,
          "reviewed_hash": null
        },
        "en": {
          "headline": "No more spreadsheets for splitting costs.",
          "subline": "Log expenses, split automatically and fair.",
          "reviewed": false,
          "reviewed_hash": null
        }
      }
    }
  ],
  "video": {
    "scene_order": ["01-hero", "02-rsvp"],
    "duration_per_scene_s": 3.5
  },
  "runtime": {
    "hyperframes": "0.8.72"
  }
}
```

## Field reference

- `brand.headline_font` / `brand.subline_font` — `family`: the CSS `font-family` name used in the
  scene's `@font-face`. `path`: project-relative path to the font file (woff2). No fallback font is
  ever baked into the output (Edge Cases in `SKILL.md`): a font that fails
  `document.fonts.check()` aborts the render instead of silently substituting one.
- `brand.logo` — project-relative path to the logo asset placed on the canvas.
- `locales` — ordered list of locale codes to render (`de`, `en`, ...).
- `formats.<id>` — pixel `width`/`height` per store target. `store-specs.md` is the source of
  truth for which format ids exist and their exact sizes; this list mirrors it for the given
  project (a project may render a subset, never a size store-specs.md does not list). Device choice
  follows the format, not the scene: `ios-6.9` always renders an iPhone screen, `play-phone` always
  an Android screen (`bin/render.mjs`'s `DEVICE_BY_FORMAT`), `play-feature` never shows a device.
- `scenes[]` — one entry per screen in the store screenshot sequence.
  - `id` — stable scene id, also the output filename prefix (`<id>.jpg`).
  - `source.<locale>.<theme>` — project-relative path to the source screen PNG for that
    locale/theme combination. A scene without a source for a configured locale/theme fails
    pre-flight (Edge Cases).
  - `background` / `foreground` — this scene's canvas background and text color (hex), so
    consecutive store screenshots can alternate a project's brand palette instead of repeating one
    color on every screen. Also selects the iPhone bezel color on `ios-6.9`
    (`store-specs.md` "Devices", `IPHONE_COLOR_BY_BG`), unless the scene is a `combo` layout (each
    phone sets its own `ios_color`).
  - `layout` — `"single"` (default, one device) or `"combo"` (two devices, `01-hero` only so far).
    A `single` scene needs `source`/`crop_top_px`; a `combo` scene needs `combo` instead of both.
  - `source.<locale>.<theme>` (layout `single`) — project-relative path to the source screen PNG.
    `<theme>` is normally `light`; a scene can point at `dark` instead (e.g. `07-tasks`, "uses the
    dark source") to render that screen's dark-mode capture. A scene without a source for a
    configured locale/theme fails pre-flight (Edge Cases).
  - `crop_top_px` (layout `single`) — how many pixels to hide from the top of the source
    screenshot (its own page header), in the device's own native pixel space (the whole device,
    screenshot included, is later scaled down as one unit, so this number is canvas-size
    independent, unlike Round 1's canvas-relative version). `0` when the screenshot needs no
    cropping. The hidden strip is backfilled by the real status-bar overlay, not left blank
    (`store-specs.md` "Devices").
  - `combo` (layout `combo`) — `front`/`back`, each `{ source, crop_top_px, ios_color }`. `source`
    has the same `<locale>.<theme>` shape as a `single` scene's own `source` field. `ios_color` is
    ignored on `play-phone` (Android has no bezel color variants); on Play the same two-device
    composition renders with Pixel frames instead of iPhone frames.
  - `pills` (optional, any layout) — `{ "<locale>": [pill1, pill2] }`, up to two short badges
    below the subline (`08-expenses` only, so far). Absent on every other scene; the template
    renders nothing when absent (Edge Cases).
  - `text.<locale>.headline` — the rendered headline. Required.
  - `text.<locale>.subline` — optional; omitted entirely on the `01-hero` combo scene (headline
    only) and on `play-feature` (`templates/scene.html`'s `isLandscape` branch never renders one).
  - `text.<locale>.reviewed` — `true` only once a human has approved this exact headline/subline
    pair (Gate 1). Renders never happen against `reviewed: false` text in the full-render step
    (Muster/Vollrender still run against it for preview purposes, the validator is what blocks).
  - `text.<locale>.reviewed_hash` — SHA-256 of `headline + subline` at the moment of approval. If
    the current text's hash no longer matches, `reviewed` is treated as `false` regardless of the
    stored boolean (Edge Cases: "Headline nach Freigabe geändert").
- `video.scene_order` / `video.duration_per_scene_s` — Meilenstein B only: the sequence and timing
  `templates/preview.html` reads once it exists.
- `runtime.hyperframes` — exact HyperFrames version this project's video render is pinned to
  (Meilenstein B). Stills never read this field.

`play-feature` is not scene-driven: `bin/render.mjs` always renders it once per locale from
`scenes[0]` (the config's hero scene), reusing that scene's `background`/`foreground`/`headline`
plus the project logo, since Play accepts exactly one Feature Graphic (`store-specs.md`).

## CLI flags (`bin/render.mjs`)

- `--project <path>`, `--scene <id>`, `--format <id>`, `--locale <code>` — as before (Step 4).
- `--background <hex>` — forces every rendered scene's `background` to this value and `foreground`
  to `#ffffff` for this invocation only (never edits the config file); the iPhone bezel color still
  follows `IPHONE_COLOR_BY_BG`, so this is how a uniform-palette variant strip gets rendered without
  hand-editing every scene. A `combo` scene's `ios_color` per phone is overridden the same way (both
  phones use the derived color instead of their own configured ones).
- `--out <dir>` — writes directly into `<dir>` (project-relative) instead of
  `native/store-assets/generated/<format>/<locale>/`, and skips the `generated/index.html` rewrite
  (a `--out` run is a partial/variant run, not the project's main catalog).
