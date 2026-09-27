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
      "source": {
        "de": { "light": "tests/Browser/screenshots/marketing/appstore/de/light/eventpage-top.png" },
        "en": { "light": "tests/Browser/screenshots/marketing/appstore/en/light/eventpage-top.png" }
      },
      "background": "#04081f",
      "foreground": "#ffffff",
      "crop_top_px": 60,
      "text": {
        "de": {
          "headline": "Schluss mit dem WhatsApp-Chaos.",
          "subline": "Eine Seite für dein ganzes Event, ohne Account für deine Gäste.",
          "reviewed": false,
          "reviewed_hash": null
        },
        "en": {
          "headline": "End the WhatsApp chaos.",
          "subline": "One page for your whole event, no account needed for guests.",
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
    color on every screen.
  - `crop_top_px` — how many pixels to hide from the top of the source screenshot (its own browser
    chrome / page header), calibrated against a 1320px-wide canvas (`ios-6.9`) and scaled linearly
    for other canvas widths (`templates/scene.html`'s `--crop-scaled`, `bin/render.mjs`'s
    `cropTopPx` param). `0` when the screenshot needs no cropping.
  - `text.<locale>.headline` / `.subline` — the rendered copy for that locale. `play-feature`
    renders only `headline` (plus the logo), never `subline` (`templates/scene.html`'s
    `isLandscape` branch).
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
