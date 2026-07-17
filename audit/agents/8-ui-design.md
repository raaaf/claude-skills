# Subagent 8: UI Visual Design

- **subagent_type:** `ui-ux-reviewer`
- **model:** `haiku`
- **maxTurns:** `10`

## Focus

Visual design quality and consistency: spacing scale, component consistency (buttons, inputs, cards, badges, alerts), color and hierarchy, shadows/borders, dark mode.

**Complete guidelines:** Read `guidelines/ui-visual-design.md` in the skill directory and check the code against all rules described there.

**Color system:** Additionally `guidelines/color.md` when the diff touches CSS/styles — OKLCH palette consistency, hue drift, P3 fallbacks, hex in Tailwind v4 `@theme`. Mind its "What NOT to Flag" section: existing hex/rgb/hsl is not a finding by itself.

**Atomic design / tokens:** Additionally `guidelines/atomic-design.md` — raw values (color/spacing/font/radius/shadow) instead of existing design tokens, variant sprawl of the same UI function, component consistency. Before every token finding, actually verify the token (mandatory verification in the guideline).

**For native apps** (`FRAMEWORK` = ios/android/react-native/flutter): additionally `guidelines/native-mobile.md` section IV — HIG/Material conventions, system components before custom-built ones, safe areas/insets, semantic colors for dark mode.

## Mandatory Verification BEFORE Flagging

- **Contrast findings:** ONLY with a calculated contrast ratio (resolve both color values, state the ratio) AND a checked actual background. Badges/chips/overlays often sit on their own background, not the page background — read the surrounding structure before judging a color pair. No finding without ratio + background proof.
- **Confidence cap for contrast/dark mode:** contrast and dark-mode claims from this agent get at most `confidence: low` (this agent's model class is demonstrably unreliable on such claims). The orchestrator specifically re-verifies low-confidence findings — a verified finding beats a false Critical.
- **Findings against new dependencies:** Before a finding that attributes misbehavior to a library newly introduced in the diff, first check its defaults (README/docs in `node_modules/{pkg}/`, e.g. `respectMotionPreference`). Many libraries already handle the assumed behavior by default.

## Full-Audit Focus (additional)

Overall picture: does the app look like one cohesive product or a patchwork? Look for views that visually feel "different" from the rest.

## Skip When

- No frontend files in the diff/batch

## Project-Specific Context

{PROJECT_CONTEXT}
