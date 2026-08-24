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

These L-thresholds are heuristics for picking a starting point, not proof of pass/fail. Before emitting or fixing a contrast finding, compute the actual ratio (WCAG) or Lc (APCA), especially for high-chroma colors near L 0.6, where perceived contrast can diverge from the L value alone.

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

## VII. Gradient Interpolation Space

A gradient without a declared interpolation space is interpolated in sRGB, which is why the classic blue-to-yellow gradient runs through a muddy grey midpoint: sRGB interpolation does not preserve perceived lightness. Declare the space when the endpoints differ much in hue or lightness:

```css
/* even perceived brightness across the ramp */
background: linear-gradient(in oklab, var(--from), var(--to));

/* keeps midtones vivid instead of desaturating them */
background: linear-gradient(in oklch, var(--from), var(--to));
```

Rule of thumb: `in oklab` when an even brightness ramp matters (overlays, scrims, chart fills), `in oklch` when the midpoint should stay saturated (brand gradients, accent surfaces). Plain sRGB is a deliberate choice, not a default to fall into.

Only a finding when the muddy midpoint is actually visible: a two-stop gradient between distant hues with no `in <space>`. A subtle same-hue gradient (light blue to slightly darker blue) is fine in sRGB and must not be flagged.

## VIII. One Theme Mechanism, Not Two

Dark mode is switched either by the OS query or by a class on the root, never by both in the same codebase:

```css
/* mechanism A */  @media (prefers-color-scheme: dark) { :root { --bg: #111; } }
/* mechanism B */  .dark { --bg: #111; }
```

Mixing them is a real defect, not a style preference: a user who picks "light" explicitly still matches `prefers-color-scheme: dark`, so half the tokens flip and half do not, and the result is unreadable text in exactly one of the four combinations. It usually appears when a manual toggle is added later to a codebase that started with the media query.

Finding (Important) when both appear and the media-query block is not guarded, e.g. `:root:not(.light)`. A codebase using only one of the two is correct either way. Note the mechanism choice also decides whether a server-rendered page can avoid the first-paint flash, which is a separate concern from consistency.

## IX. What NOT to Flag

- Existing hex/rgb/hsl in an established codebase is NOT a finding by itself. Only flag color-space issues when they cause a checkable defect (drift, failed contrast, missing P3 fallback, hex inside a v4 `@theme`).
- CSS keywords (`currentColor`, `transparent`, `inherit`) are never conversion candidates.
- Colors in third-party configs that expect hex input stay hex.
- Do not propose a project-wide hex-to-oklch migration as an audit fix; that is a refactor decision for the user.
