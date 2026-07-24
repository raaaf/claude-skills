# UI Visual Design Checklist

## CSS Pseudo-Elements

| Rule | Implementation |
|------|---------------|
| `content` property required | `::before`/`::after` won't render without `content: ""` |
| Prefer pseudo-elements over DOM nodes | Decorative elements use `::before`/`::after`, not extra `<span>` |
| Parent must be `position: relative` | Required when pseudo-element uses `position: absolute` |
| Z-index layering | Use `z-index: -1` on pseudo-element to layer behind parent content; parent needs `z-index: 1` |
| Hit target expansion | `inset: -8px -12px` on pseudo-element expands clickable area without wrapper markup |
| Hit-area collision | Expanded hit areas of two interactive elements must never overlap — shrink the pseudo-element until they don't, keeping it as large as possible |

**Native pseudo-element selectors — use instead of JS/DOM workarounds:**

| Selector | Use for | Anti-pattern it replaces |
|----------|---------|------------------------|
| `dialog::backdrop` | Dialog/popover overlay with `backdrop-filter: blur(4px)` | Extra overlay `<div>` |
| `input::placeholder` | Placeholder styling (`opacity: 1` for consistency) | Conditional `<span>` placeholder |
| `::selection` | Text selection colors | — |
| `li::marker` | Custom list bullet styling | `list-style: none` + `background-image` hack |
| `::first-line` | Typographic treatments (small-caps, weight) | Hardcoded `<span>` wrapping first line |

---

## View Transitions API

Prefer native View Transitions over JS animation libraries (e.g. `motion/react` `layoutId`).

**Scope boundary:** View Transitions are for navigation-level changes (route/page/view swaps). For interaction-heavy UI (toggles, drags, rapidly-triggered state) they are the wrong tool — they cannot be smoothly interrupted or cancelled, and size changes may trigger layout. Use CSS transitions/springs there instead.

| Rule | Detail |
|------|--------|
| Assign `view-transition-name` | Elements must have it to participate in transitions |
| Names must be unique | Use `card-${id}` pattern, never same class-based name on multiple elements |
| Clean up source name | Set source `viewTransitionName = ""` inside `startViewTransition()` callback |
| Style transition pseudo-elements | `::view-transition-group(name)` for custom `animation-duration` and easing |

```ts
// Correct pattern
sourceImg.style.viewTransitionName = "card";
document.startViewTransition(() => {
  sourceImg.style.viewTransitionName = "";
  targetImg.style.viewTransitionName = "card";
});
```

```css
::view-transition-group(card) {
  animation-duration: 300ms;
  animation-timing-function: cubic-bezier(0.215, 0.61, 0.355, 1);
}
```

---

## Morphing Icons

Every icon = exactly 3 SVG lines. Fewer-line icons collapse extras to invisible center points.

### Architecture

```ts
interface IconLine { x1: number; y1: number; x2: number; y2: number; opacity?: number; }
interface IconDefinition { lines: [IconLine, IconLine, IconLine]; rotation?: number; group?: string; }

const CENTER = 7;
const collapsed: IconLine = { x1: CENTER, y1: CENTER, x2: CENTER, y2: CENTER, opacity: 0 };
```

### Rules

| Rule | Detail |
|------|--------|
| Exactly 3 lines | No more, no fewer. Unused lines = `collapsed` constant (not `null`) |
| Consistent viewBox | All icons use 14x14 (`CENTER = 7`) |
| Rotational variants share `group` + base lines | e.g. all arrows reuse `arrowLines` with different `rotation` and same `group: "arrow"` |
| Spring physics for grouped rotation | `useSpring(definition.rotation ?? 0, activeTransition)` |
| Instant jump for non-grouped transitions | `rotation.jump()` when switching between different groups |
| `prefers-reduced-motion` | `useReducedMotion()` — set `{ duration: 0 }` when true |
| `strokeLinecap="round"` | Always. Never `"butt"` |
| `aria-hidden="true"` | On all icon SVGs (decorative) |

### Icon patterns

```ts
// 2-line (check, minus, chevron) — one collapsed
const check = { lines: [
  { x1: 2, y1: 7.5, x2: 5.5, y2: 11 },
  { x1: 5.5, y1: 11, x2: 12, y2: 3 },
  collapsed,
]};

// 3-line (menu, asterisk) — all used
const menu = { lines: [
  { x1: 2, y1: 3.5, x2: 12, y2: 3.5 },
  { x1: 2, y1: 7, x2: 12, y2: 7 },
  { x1: 2, y1: 10.5, x2: 12, y2: 10.5 },
]};

// Dot icons (more, grip) — zero-length lines
const more = { lines: [
  { x1: 3, y1: 7, x2: 3, y2: 7 },
  { x1: 7, y1: 7, x2: 7, y2: 7 },
  { x1: 11, y1: 7, x2: 11, y2: 7 },
]};
```

**Default transition:** `{ ease: [0.19, 1, 0.22, 1], duration: 0.4 }`

---

## Border Radius

**Concentric radius for nested elements:** inner radius = outer radius - gap.

```css
.outer {
  --padding: 8px;
  --inner-radius: 8px;
  border-radius: calc(var(--inner-radius) + var(--padding));
  padding: var(--padding);
}
.inner { border-radius: var(--inner-radius); }
```

Anti-pattern: same `border-radius` on both parent and child.

**Exception:** if the padding between the layers exceeds ~24px, treat them as separate surfaces and pick each radius independently — strict concentric math is only for tightly nested elements.

---

## Optical Alignment

When geometric centering looks off, align optically. Geometric center and visual center differ for asymmetric shapes.

| Case | Fix |
|---|---|
| Button with trailing icon | Icon-side padding = text-side padding - 2px (e.g. `pl-4 pr-3.5`) |
| Play-button triangle | Shift the SVG ~2px toward the pointed side (`margin-left: 2px`) |
| Asymmetric icons (stars, arrows, carets) | Best: fix the viewBox/path in the SVG itself so no per-usage margin is needed. Fallback: `ml-px` style nudges |

Anti-pattern to flag: `justify-center`/`items-center` on an icon button whose icon is visibly asymmetric, with no optical correction anywhere.

---

## Image Outlines

Images get a subtle 1px outline so they read as intentional surfaces on any background:

```css
img.card-media {
  outline: 1px solid oklch(0 0 0 / 0.1);   /* light mode: pure black */
  outline-offset: -1px;                     /* inset, no layout shift */
}
.dark img.card-media {
  outline-color: oklch(1 0 0 / 0.1);        /* dark mode: pure white */
}
```

Rules:
- Pure black/white with low alpha only. Tinted neutrals (slate-900, zinc-900, `#111827`) pick up the surface color and read as dirt on the image edge — flag them. Scope: this 1px outline only. `box-shadow` color follows the Shadows section's deep-neutral rule below — the two rules do not conflict.
- Never the accent or brand color; the outline is a neutral separator.
- `outline` + negative offset instead of `border`: no added width/height.

---

## Shadows

### Layered shadows for realistic depth

Never use a single flat `box-shadow`. Layer 3+ shadows with increasing blur and decreasing opacity.

```css
.card {
  box-shadow:
    0 1px 2px rgba(17, 24, 39, 0.06),
    0 4px 8px rgba(17, 24, 39, 0.04),
    0 12px 24px rgba(17, 24, 39, 0.03);
}
```

### Shadow rules

| Rule | Detail |
|------|--------|
| Consistent direction | All shadows use same offset direction (top-down: `0 Npx`) — single light source |
| Neutral colors | Use deep neutrals like `rgba(17, 24, 39, 0.08)`, not pure black `rgba(0,0,0,...)` |
| Elevation scale | Larger blur+offset = higher elevation. Define `--shadow-1/2/3` tokens |
| Animate via pseudo-element | Never `transition: box-shadow`. Use `::after` with `opacity` transition instead |
| Dark mode | Layered depth shadows are invisible on dark backgrounds. Simplify to a single ring: `0 0 0 1px oklch(1 0 0 / 0.08)` (hover: `/ 0.13`) |

### Shadows vs. borders — decision table

"Shadows over borders" applies to depth/elevation only. Do NOT flag these as shadow candidates:

| Use shadows | Keep borders |
|---|---|
| Cards, containers with depth | Dividers between list items (`border-b`, `border-t`) |
| Buttons with bordered styles | Table cell boundaries |
| Elevated surfaces (dropdowns, modals) | Form input outlines (accessibility) |
| Elements on varied/image backgrounds | Hairline separators in dense UI |

### Elevation scale

```css
:root {
  --shadow-1: 0 1px 2px rgba(17, 24, 39, 0.05);   /* card */
  --shadow-2: 0 2px 8px rgba(17, 24, 39, 0.08);   /* dropdown */
  --shadow-3: 0 8px 24px rgba(17, 24, 39, 0.12);  /* modal */
}
```

### Shadow animation (pseudo-element pattern)

```css
.card { position: relative; box-shadow: var(--shadow-1); }
.card::after {
  content: ""; position: absolute; inset: 0;
  border-radius: inherit; box-shadow: var(--shadow-3);
  opacity: 0; transition: opacity 0.2s ease;
  pointer-events: none; z-index: -1;
}
.card:hover::after { opacity: 1; }
```

---

## Full Button Shadow Anatomy

A polished button uses 6 layered techniques:

1. **Outer cut shadow** — `0 0 0 0.5px rgba(17,24,39,0.3)` cuts button into surface
2. **Inner ambient highlight** — `inset 0 0 0 1px rgba(255,255,255,0.04)` environmental light
3. **Inner top highlight** — `inset 0 1px 0 rgba(255,255,255,0.07)` primary light from above
4. **Layered depth shadows** — 3+ external shadows for natural lighting
5. **Text drop-shadow** — `text-shadow: 0 1px 1px rgba(17,24,39,0.15)` on text/icons
6. **Subtle gradient background** — If you can tell there's a gradient, it's too much

```css
.button {
  background: linear-gradient(to bottom,
    color-mix(in srgb, var(--gray-12) 100%, white 4%), var(--gray-12));
  box-shadow:
    0 0 0 0.5px rgba(17, 24, 39, 0.3),
    inset 0 0 0 1px rgba(255, 255, 255, 0.04),
    inset 0 1px 0 rgba(255, 255, 255, 0.07),
    0 1px 2px rgba(17, 24, 39, 0.1),
    0 2px 4px rgba(17, 24, 39, 0.06),
    0 4px 8px rgba(17, 24, 39, 0.03);
  text-shadow: 0 1px 1px rgba(17, 24, 39, 0.15);
}
```

---

## Spacing

Use a consistent scale. Never arbitrary pixel values.

```css
:root {
  --space-1: 4px;  --space-2: 8px;  --space-3: 12px;  --space-4: 16px;
  --space-5: 24px; --space-6: 32px; --space-7: 48px;
}
```

Anti-pattern: `padding: 17px`, `margin: 13px`, `gap: 22px`.

---

## Borders

Use semi-transparent borders — they adapt to any background.

```css
.card { border: 1px solid var(--gray-a4); }
```

Anti-pattern: hardcoded hex like `border: 1px solid #e5e5e5`.

---

## Dark Mode Contrast

| Rule | Threshold |
|---|---|
| Card surface vs. page background | >= 1.4:1 contrast ratio, otherwise the card reads as flat/invisible in dark mode |
| Hairlines/borders against adjacent surface | >= 3:1 (WCAG 1.4.11 non-text contrast) |
| Check computed colors, not token names | Resolve the actual dark-mode values behind semantic tokens and compute the ratio; never trust names like `card`/`background` |

Computation: relative luminance L = 0.2126R + 0.7152G + 0.0722B on linearized sRGB; ratio = (L_lighter + 0.05) / (L_darker + 0.05).

---

## Materials & Translucency (2026)

Translucent surfaces (`backdrop-filter: blur()` + semi-transparent background) act as a floating functional layer that conveys hierarchy without stealing focus.

| Rule | Detail |
|---|---|
| Chrome as material | Sticky nav/toolbars/sheets: translucent layer with content scrolling underneath, not an opaque bar consuming a fixed strip |
| Material weight = hierarchy | Heavier/darker materials separate structural regions (sidebars); lighter materials for interactive elements |
| Never stack light-on-light | Two light translucent surfaces on top of each other collapse legibility — flag it |
| Bigger = thicker | Large surfaces get stronger blur + deeper shadow than small chips |
| Vibrancy for text on blur | No flat gray text over translucent surfaces: higher contrast, slightly heavier weight, small letter-spacing bump. Color belongs on a solid layer, not the translucent foreground |
| Scroll edge over hard divider | Where content meets floating chrome, prefer a small fade/blur mask to a 1px border under the sticky header |
| Modal vs. panel | Modal task = surface + dimming scrim. Parallel non-blocking panel = translucency + offset WITHOUT scrim |
| Materialize, don't fade | Glass surfaces animate blur radius and scale together on enter/exit, not plain opacity |

```css
.toolbar {
  background: rgba(255, 255, 255, 0.6);
  backdrop-filter: blur(20px) saturate(180%);
  border-top: 1px solid rgba(255, 255, 255, 0.4); /* light catching the top edge */
}
```

Every translucent surface needs `prefers-reduced-transparency` handling (see accessibility guideline).

---

## Layout Robustness (2026)

| Rule | Finding pattern |
|---|---|
| `h-dvh` over `h-screen` | `h-screen`/`100vh` on full-height layouts breaks under mobile browser chrome — use `100dvh`/`h-dvh` |
| Safe areas | `position: fixed` bars/FABs without `env(safe-area-inset-*)` padding clip under notches and home indicators |
| Fixed z-index scale | Arbitrary values (`z-[9999]`, `z-50` next to `z-40` next to `z-junk`) instead of a defined scale (`--z-dropdown`, `--z-modal`, `--z-toast`) — layering bugs are guaranteed once two ad-hoc values collide |

---

## Generated-UI Slop Heuristics (2026)

Patterns that mark an interface as generic AI output. Each is a Minor finding unless the project's design language explicitly calls for it:

- Purple or multicolor gradients as default decoration; gradients nobody asked for
- Glow effects as the primary affordance (glowing borders/buttons instead of real states)
- More than one accent color per view
- New one-off colors when theme/Tailwind tokens exist
- Empty states without exactly one clear next action
- Decorative blur orbs / floating gradient blobs in the background

---

## Blade Escaping Context in `<style>` Blocks (2026)

`{{ }}` inside a `<style>` block escapes to HTML entities that the browser
never decodes (RAWTEXT): a quoted font stack from config renders as
`&quot;Inter&quot;` and the whole declaration is silently dropped. Visual
symptom: fallback font, no error anywhere. Trusted, developer-controlled
config values in CSS need `{!! !!}` plus a trusted-source comment; anything
user-influenced must not be interpolated into `<style>` at all (use a
sanitized custom property). Full rule: security.md XVI.

## References

- [MDN Pseudo-elements](https://developer.mozilla.org/en-US/docs/Web/CSS/Reference/Selectors/Pseudo-elements)
- [View Transitions API](https://developer.mozilla.org/en-US/docs/Web/API/View_Transitions_API)
- [Motion useSpring](https://motion.dev/docs/react-use-spring)
- [Designing Beautiful Shadows](https://www.joshwcomeau.com/css/designing-shadows/)
- [Concentric Border Radius](https://jakub.kr/work/concentric-border-radius)
