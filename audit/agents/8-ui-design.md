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
- **Resolve tokens from the project theme, never from Tailwind defaults:** before ANY ratio calculation, check the project's CSS theme source (`app.css`/`theme.css` `@theme` block, CSS custom properties) for overrides of the utility's underlying token — including dark-mode overrides. A ratio computed against Tailwind's default hex for e.g. `gray-900` is invalid when the project redefines that token (real case: a dark-mode focus-ring ratio came out 2.97:1 against the default gray but was wrong — the project's achromatic OKLCH override was the actual background). State in the finding WHICH resolved values (project token or default, with source line) the ratio uses.
- **Confidence cap for contrast/dark mode:** contrast and dark-mode claims from this agent get at most `confidence: low` (this agent's model class is demonstrably unreliable on such claims). The orchestrator specifically re-verifies low-confidence findings — a verified finding beats a false Critical.
- **Findings against new dependencies:** Before a finding that attributes misbehavior to a library newly introduced in the diff, first check its defaults (README/docs in `node_modules/{pkg}/`, e.g. `respectMotionPreference`). Many libraries already handle the assumed behavior by default.
- **Variant/style-mismatch findings (button color/variant, badge style, spacing choice):** before flagging, check at least 2 comparable call sites of the same component elsewhere in the codebase and state which convention they establish. If the flagged code matches the majority convention, it is not a finding — the deviation may be elsewhere. Prevents apply-then-revert cycles on fixes that "corrected" code toward the wrong convention.
- **Flex-row layout fixes — long-content edge case (standard check):** whenever the diff changes a flex row containing text (name + badge, label + action), verify the long-content case: a 4-word name or long translation must wrap or truncate without pushing siblings out of the row (`min-w-0`, `truncate`, `shrink-0` on fixed parts). A flex fix verified only with short placeholder text is unverified.

## Full-Audit Focus (additional)

Overall picture: does the app look like one cohesive product or a patchwork? Look for views that visually feel "different" from the rest.

## Skip When

- No frontend files in the diff/batch

## Project-Specific Context

{PROJECT_CONTEXT}
