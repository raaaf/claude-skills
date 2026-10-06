# Store specs

Stand: 2026-09-27. Re-verify against the source URLs below before any full render once this date
is older than 6 months (`SKILL.md` Ablauf, step 4).

## iOS App Store (App Store Connect)

- Format id `ios-6.9`: 1320 x 2868 px, portrait, iPhone 6.9" display class (iPhone 16 Pro Max and
  successors). JPEG or PNG, no alpha channel, sRGB or Display P3.
- Up to 10 screenshots per locale.
- Source: https://developer.apple.com/help/app-store-connect/reference/screenshot-specifications/

## Google Play (Play Console)

- Format id `play-phone`: 1440 x 2560 px, portrait phone screenshot. JPEG or 24-bit PNG, no alpha.
- Up to 8 phone screenshots per locale, minimum 2.
- Format id `play-feature`: 1024 x 500 px, Feature Graphic. JPEG or 24-bit PNG, no alpha. Exactly 1
  per locale (Play only accepts one).
- Source: https://support.google.com/googleplay/android-developer/answer/9866151

## App Preview (Meilenstein B, not yet implemented)

- Apple App Preview video: H.264, 15-30 s. Exact target resolution to be confirmed against
  https://developer.apple.com/help/app-store-connect/reference/app-preview-specifications/ before
  Step 10 is implemented (plan Step 10: "vor Umsetzung gegen Apple-Doku prüfen, Wert + Quelle in
  store-specs.md").
- YouTube companion export: 1920 x 1080 px, H.264.

## Devices

`bin/render.mjs` never hardcodes a bezel/status-bar path: it extracts the fenced JSON block below
(the first ` ```json ` fence under this heading) and resolves every `~`-prefixed path against
`os.homedir()`. Real device bezels and real status-bar captures, real machine assets under
`~/.cache/store-assets/` and the Android SDK, not the CSS-drawn frames from the previous round.

```json
{
  "iphone": {
    "bezel_size": { "width": 1470, "height": 3000 },
    "screen_rect": { "x": 75, "y": 66, "width": 1320, "height": 2868 },
    "corner_radius": 190,
    "bezel_path_pattern": "~/.cache/store-assets/bezels/iphone-18-pro-max/iPhone 18 Pro Max - {color} - Portrait.png",
    "colors": ["Black", "Silver", "Glacier", "Burgundy"],
    "screen_over_bezel": true,
    "status_bar_path_pattern": "~/.cache/store-assets/statusbar/ios-27-statusbar-{theme}.png",
    "status_bar_band_height": 186,
    "width_pct": 80
  },
  "android": {
    "bezel_size": { "width": 1408, "height": 2974 },
    "screen_rect": { "x": 60, "y": 61, "width": 1280, "height": 2856 },
    "corner_radius": 109,
    "bezel_path_pattern": "~/Library/Android/sdk/skins/pixel_9_pro/back.webp",
    "mask_path": "~/Library/Android/sdk/skins/pixel_9_pro/mask.webp",
    "screen_over_bezel": false,
    "status_bar_path_pattern": "~/.cache/store-assets/statusbar/android-37-statusbar-{theme}.png",
    "status_bar_band_height": 140,
    "width_pct": 74
  }
}
```

- `bezel_path_pattern` — `{color}` is substituted with one of `colors` (iPhone only; Android's
  `back.webp` has no color variants). Stack order: `screen_over_bezel: true` (iPhone) paints the
  screen first, the bezel on top (the bezel PNG's screen window is transparent, its Dynamic Island
  is opaque); `false` (Android) paints the bezel first, the screen on top, then `mask_path`'s webp
  (corners + punch-hole) as a final image overlay on top of the screen -- not a CSS mask.
- `screen_rect` — where the screenshot + status-bar overlay sit inside the bezel's own pixel grid;
  `corner_radius` is the screen container's own border-radius (matches the bezel art's screen
  window corners).
- `status_bar_path_pattern` — `{theme}` is `light` or `dark`. `bin/render.mjs` samples the source
  screenshot's own pixel color at `(20, crop_top_px + 4)` (`magick <path> -format
  "%[pixel:p{20,${crop+4}}]" info:`, converting the `srgb()`/`srgba()` string to `rgb()`/`rgba()`),
  computes luminance (`0.2126*r + 0.7152*g + 0.0722*b`, 0-255), and uses the `light` overlay when
  luminance < 0.5 (a dark screenshot needs light-colored status-bar icons). That sampled color also
  fills the status-bar band behind the (transparent) overlay image, and is the screen container's
  own background (visible where `crop_top_px` shifts the screenshot down instead of up). Source
  screenshot placement inside the screen: `top: status_bar_band_height - crop_top_px` (px, can go
  negative when `crop_top_px` exceeds the band height, which clips that much off the screenshot's
  own top instead).
- `width_pct` — the device's width as a percent of the canvas (`ios-6.9`/`play-phone`), the same
  role as Round-1's device-width constants, now per-device-kind here instead of in `scene.html`.
- iPhone bezel color by scene background (`bin/render.mjs`'s `IPHONE_COLOR_BY_BG`, a skill-level
  rule): `#04081f` (navy) -> Silver, `#f7f7f7` (light) -> Black, `#e0452f`
  (brand) -> Glacier. Any other background falls back to the first entry of `colors` above
  (Black). A `single` scene's own `ios_color` field overrides the lookup; a combo layout
  (`config-schema.md` "layout: combo") overrides it per phone via each part's `ios_color`. Android has no color variants (one `back.webp`).

### Asset provenance (rebuilding on another machine)

None of this is downloaded or generated by the skill itself; it is prepared once per machine.

- **iPhone bezels**: Apple's own bezel DMG,
  https://devimages-cdn.apple.com/design/resources/download/Bezel-iPhone-18.dmg -- mount it, and
  accept the license in Finder (a GUI step, not scriptable), then copy the four
  `iPhone 18 Pro Max - <color> - Portrait.png` files into
  `~/.cache/store-assets/bezels/iphone-18-pro-max/`.
- **iOS status bar**: `xcrun simctl status_bar <udid> override ...` on an iPhone 18 Pro Max
  simulator, iOS 27, locale `en_US` (matches the `9:41` App-Store-marketing convention), then a
  screenshot of the empty status bar area cropped to `1320x200` per theme (light/dark), saved as
  `~/.cache/store-assets/statusbar/ios-27-statusbar-{light,dark}.png`.
- **Android status bar**: a Pixel 9 Pro AVD, SystemUI demo mode
  (`adb shell am broadcast -a com.android.systemui.demo -e command enter` then `... -e command
  network -e mobile false` to hide the mobile signal/data icons per the mock, so the bar shows only
  clock + wifi + battery), booted with `-gpu host` (headless/software rendering shows no status bar
  at all), cropped to `1280x140` per theme, saved as
  `~/.cache/store-assets/statusbar/android-37-statusbar-{light,dark}.png`.
- **Android bezel**: ships with the SDK, `~/Library/Android/sdk/skins/pixel_9_pro/{back,mask}.webp`
  (installed by the Pixel 9 Pro system image / AVD skin, nothing to rebuild).

## Pinned tool versions

- HyperFrames (video, Meilenstein B only): `0.8.72` (`video-generator/node_modules/hyperframes/package.json`,
  confirmed 2026-09-27). Always invoke as `npx -y hyperframes@0.8.72 ...` (or the project's own
  config value under `runtime.hyperframes`, never a floating `npx hyperframes`).
- Playwright fallback pin (only when the target project has no own `playwright`/`@playwright/test`
  dependency): `1.63.0`, matching the pattern already used by `screens/templates/render-marketing.mjs`
  and `events`' own `package.json` (`playwright: ^1.63.0`).
