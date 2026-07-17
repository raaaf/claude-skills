---
applies_to: \.(css|scss|sass|less|styl)$|tailwind\.config|\.(jsx|tsx|vue|svelte|astro|html)$|\.blade\.php$
priority: recommended
---
# Color Guidelines (OKLCH, Contrast, Palettes)

OKLCH is a perceptually uniform color space: equal L steps mean equal perceived brightness, hue stays stable across lightness, chroma is independent of lightness. Most palette and contrast bugs come from HSL/hex not matching how humans see. These rules make color findings checkable instead of taste-based.

## I. OKLCH Syntax and Thresholds

```
oklch(L C H)          /* L 0-1, C 0-~0.4, H 0-360 */
oklch(L C H / alpha)  /* alpha via slash, never comma */
```

| Rule | Value |
|---|---|
| Light/dark boundary | L > 0.6 = light background, use dark text |
| Lightness gap (light bg, L > 0.9) | Foreground L < 0.35 for body text |
| Lightness gap (dark bg, L < 0.25) | Foreground L > 0.9 for body text |
| Hue drift threshold | > 10 degrees spread across palette steps = visible drift |
| Contrast fix | Adjust L only. Chroma has negligible effect on contrast |

## II. Contrast: WCAG Is the Gate, APCA Is the Advisor

WCAG 2.x ratios remain the blocking criterion (legal conformance, see accessibility guideline). APCA (Accessible Perceptual Contrast Algorithm) is more perceptually accurate and pairs naturally with OKLCH; use it as a secondary signal, severity Minor at most.

| Content type | APCA minimum | APCA preferred |
|---|---|---|
| Body text | Lc 75 | Lc 90 |
| Non-body text (labels, headlines) | Lc 60 | Lc 75 |
| Large text (>= 36px) | Lc 45 | Lc 60 |
| UI components | Lc 30 | n/a |

Fixing contrast in OKLCH: change the L distance between foreground and its actual background, keep C and H. Never fix contrast by pushing chroma.

**Impossible-fix guard:** mid-lightness backgrounds cap achievable contrast. On a background of L ~0.75 even pure black text only reaches about Lc 60. If a finding demands body-text contrast on such a background, the correct fix is changing the background, not the text. Do not propose text-color fixes that cannot mathematically reach the threshold.

## III. Hue Drift Detection

HSL ramps drift: `hsl(240, 80%, 20%)` and `hsl(240, 80%, 90%)` are not the same perceptual hue (the light step shifts ~16 degrees toward purple).

Check: convert each palette step to OKLCH, compare H values. Spread > 10 degrees = finding; fix by rebuilding the ramp with constant OKLCH hue.

## IV. Palette Consistency

- **Same absolute chroma across hues = unequal vividness.** Different hues have different max chroma at the same lightness (cyan lowest, purple highest). Multi-hue token sets (`--blue-500`, `--green-500`, ...) should share L and the same *percentage* of each hue's max chroma, not the same absolute C.
- **Gamut clamp per step.** A high-chroma base color cannot keep its chroma at the lightest/darkest steps; lower chroma at the ends is correct, not a bug.
- **Dark mode by L reversal.** Derive dark palettes by reversing the lightness mapping of the light palette (50 <-> 950) instead of hand-picking new colors. Hand-picked dark variants that break the L ordering are a finding.

## V. Gamut and P3

- Not every OKLCH value is displayable in sRGB. High chroma at certain L/H clips silently. Fix: reduce C, keep L and H.
- A P3-only color without an sRGB fallback is a finding:

```css
.accent { color: oklch(0.7 0.2 150); }              /* sRGB-safe base */
@media (color-gamut: p3) {
  .accent { color: oklch(0.7 0.3 150); }            /* P3 enhancement */
}
```

## VI. Tailwind v4

- Tailwind v4 defines its palette in OKLCH. Hex values in `@theme` blocks are a finding (Minor): convert to `oklch()`.
- Opacity modifiers (`bg-brand-500/50`) work with OKLCH tokens; no reason to keep hex for alpha.

## VII. What NOT to Flag

- Existing hex/rgb/hsl in an established codebase is NOT a finding by itself. Only flag color-space issues when they cause a checkable defect (drift, failed contrast, missing P3 fallback, hex inside a v4 `@theme`).
- CSS keywords (`currentColor`, `transparent`, `inherit`) are never conversion candidates.
- Colors in third-party configs that expect hex input stay hex.
- Do not propose a project-wide hex-to-oklch migration as an audit fix; that is a refactor decision for the user.
