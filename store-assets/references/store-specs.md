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

## Pinned tool versions

- HyperFrames (video, Meilenstein B only): `0.8.72` (`video-generator/node_modules/hyperframes/package.json`,
  confirmed 2026-09-27). Always invoke as `npx -y hyperframes@0.8.72 ...` (or the project's own
  config value under `runtime.hyperframes`, never a floating `npx hyperframes`).
- Playwright fallback pin (only when the target project has no own `playwright`/`@playwright/test`
  dependency): `1.63.0`, matching the pattern already used by `screens/templates/render-marketing.mjs`
  and `events`' own `package.json` (`playwright: ^1.63.0`).
