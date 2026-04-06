# UI Visual Design Checklist

## CSS Pseudo-Elements

| Rule | Implementation |
|------|---------------|
| `content` property required | `::before`/`::after` won't render without `content: ""` |
| Prefer pseudo-elements over DOM nodes | Decorative elements use `::before`/`::after`, not extra `<span>` |
| Parent must be `position: relative` | Required when pseudo-element uses `position: absolute` |
| Z-index layering | Use `z-index: -1` on pseudo-element to layer behind parent content; parent needs `z-index: 1` |
| Hit target expansion | `inset: -8px -12px` on pseudo-element expands clickable area without wrapper markup |

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

---

## Shadows

### Layered shadows for realistic depth

Never use a single flat `box-shadow`. Layer 3+ shadows with increasing blur and decreasing opacity.

```css
.card {
  box-shadow:
    0 1px 2px rgba(0, 0, 0, 0.06),
    0 4px 8px rgba(0, 0, 0, 0.04),
    0 12px 24px rgba(0, 0, 0, 0.03);
}
```

### Shadow rules

| Rule | Detail |
|------|--------|
| Consistent direction | All shadows use same offset direction (top-down: `0 Npx`) — single light source |
| Neutral colors | Use deep neutrals like `rgba(17, 24, 39, 0.08)`, not pure black `rgba(0,0,0,...)` |
| Elevation scale | Larger blur+offset = higher elevation. Define `--shadow-1/2/3` tokens |
| Animate via pseudo-element | Never `transition: box-shadow`. Use `::after` with `opacity` transition instead |

### Elevation scale

```css
:root {
  --shadow-1: 0 1px 2px rgba(0, 0, 0, 0.05);   /* card */
  --shadow-2: 0 2px 8px rgba(0, 0, 0, 0.08);   /* dropdown */
  --shadow-3: 0 8px 24px rgba(0, 0, 0, 0.12);  /* modal */
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

1. **Outer cut shadow** — `0 0 0 0.5px rgba(0,0,0,0.3)` cuts button into surface
2. **Inner ambient highlight** — `inset 0 0 0 1px rgba(255,255,255,0.04)` environmental light
3. **Inner top highlight** — `inset 0 1px 0 rgba(255,255,255,0.07)` primary light from above
4. **Layered depth shadows** — 3+ external shadows for natural lighting
5. **Text drop-shadow** — `text-shadow: 0 1px 1px rgba(0,0,0,0.15)` on text/icons
6. **Subtle gradient background** — If you can tell there's a gradient, it's too much

```css
.button {
  background: linear-gradient(to bottom,
    color-mix(in srgb, var(--gray-12) 100%, white 4%), var(--gray-12));
  box-shadow:
    0 0 0 0.5px rgba(0, 0, 0, 0.3),
    inset 0 0 0 1px rgba(255, 255, 255, 0.04),
    inset 0 1px 0 rgba(255, 255, 255, 0.07),
    0 1px 2px rgba(0, 0, 0, 0.1),
    0 2px 4px rgba(0, 0, 0, 0.06),
    0 4px 8px rgba(0, 0, 0, 0.03);
  text-shadow: 0 1px 1px rgba(0, 0, 0, 0.15);
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

## References

- [MDN Pseudo-elements](https://developer.mozilla.org/en-US/docs/Web/CSS/Reference/Selectors/Pseudo-elements)
- [View Transitions API](https://developer.mozilla.org/en-US/docs/Web/API/View_Transitions_API)
- [Motion useSpring](https://motion.dev/docs/react-use-spring)
- [Designing Beautiful Shadows](https://www.joshwcomeau.com/css/designing-shadows/)
- [Concentric Border Radius](https://jakub.kr/work/concentric-border-radius)
