# UI Visual Design Guidelines

## CSS Pseudo Elements

::before and ::after require content property to render.

### Content Property Required for Pseudo-Elements

**Incorrect (missing content):**

```css
.button::before {
  position: absolute;
  background: var(--gray-3);
}
```

**Correct (content set):**

```css
.button::before {
  content: "";
  position: absolute;
  background: var(--gray-3);
}
```

### Pseudo-Elements Over DOM Nodes

Use pseudo-elements for decorative content instead of extra DOM nodes.

**Incorrect (extra DOM node):**

```tsx
<button className={styles.button}>
  <span className={styles.background} />
  Click me
</button>
```

**Correct (pseudo-element):**

```tsx
<button className={styles.button}>
  Click me
</button>
```

```css
.button::before {
  content: "";
  /* decorative background */
}
```

### Position Relative Parent for Pseudo-Elements

Parent must have position: relative for absolute pseudo-elements.

**Incorrect (no position on parent):**

```css
.button::before {
  content: "";
  position: absolute;
  inset: 0;
}
/* .button has no position */
```

**Correct (parent positioned):**

```css
.button {
  position: relative;
}

.button::before {
  content: "";
  position: absolute;
  inset: 0;
}
```

### Z-Index Layering for Pseudo-Elements

Pseudo-elements need z-index to layer correctly with content.

**Incorrect (covers button text):**

```css
.button::before {
  content: "";
  position: absolute;
  inset: 0;
  background: var(--gray-3);
}
```

**Correct (layered behind):**

```css
.button {
  position: relative;
  z-index: 1;
}

.button::before {
  content: "";
  position: absolute;
  inset: 0;
  background: var(--gray-3);
  z-index: -1;
}
```

### Hit Target Expansion with Pseudo-Elements

Use negative inset values to expand hit targets without extra markup.

**Incorrect (wrapper for hit target):**

```tsx
<div className={styles.wrapper}>
  <a className={styles.link}>Link</a>
</div>
```

**Correct (pseudo-element expansion):**

```css
.link {
  position: relative;
}

.link::before {
  content: "";
  position: absolute;
  inset: -8px -12px;
}
```

### View Transition Name Required

Elements participating in view transitions need view-transition-name.

**Incorrect (no transition name):**

```ts
document.startViewTransition(() => {
  targetImg.src = newSrc;
});
```

**Correct (transition name assigned):**

```ts
sourceImg.style.viewTransitionName = "card";
document.startViewTransition(() => {
  sourceImg.style.viewTransitionName = "";
  targetImg.style.viewTransitionName = "card";
});
```

### Unique View Transition Names

Each view-transition-name must be unique on the page during transition.

**Incorrect (duplicate names):**

```css
.card {
  view-transition-name: card;
}
/* Multiple cards with same name */
```

**Correct (unique per element):**

```ts
element.style.viewTransitionName = `card-${id}`;
```

### Clean Up View Transition Names

Remove view-transition-name after transition completes.

**Incorrect (stale name):**

```ts
sourceImg.style.viewTransitionName = "card";
document.startViewTransition(() => {
  targetImg.style.viewTransitionName = "card";
});
```

**Correct (name cleaned up):**

```ts
sourceImg.style.viewTransitionName = "card";
document.startViewTransition(() => {
  sourceImg.style.viewTransitionName = "";
  targetImg.style.viewTransitionName = "card";
});
```

### View Transitions Over JS Libraries

Prefer View Transitions API over JavaScript animation libraries for page transitions.

**Incorrect (JS-based transition):**

```tsx
import { motion } from "motion/react";

function ImageLightbox() {
  return (
    <motion.img layoutId="hero" />
  );
}
```

**Correct (native View Transition):**

```ts
function openLightbox(img: HTMLImageElement) {
  img.style.viewTransitionName = "hero";
  document.startViewTransition(() => {
    // Native browser transition
  });
}
```

### Style View Transition Pseudo-Elements

Style view transition pseudo-elements for custom animations.

**Incorrect (default crossfade only):**

```ts
document.startViewTransition(() => { /* ... */ });
```

**Correct (custom animation):**

```css
::view-transition-group(card) {
  animation-duration: 300ms;
  animation-timing-function: cubic-bezier(0.215, 0.61, 0.355, 1);
}
```

### Use ::backdrop for Dialog Backgrounds

Use ::backdrop pseudo-element for dialog/popover backgrounds.

**Incorrect (extra overlay node):**

```tsx
<>
  <div className={styles.overlay} onClick={close} />
  <dialog className={styles.dialog}>{children}</dialog>
</>
```

**Correct (native ::backdrop):**

```css
dialog::backdrop {
  background: var(--black-a6);
  backdrop-filter: blur(4px);
}
```

### Use ::placeholder for Input Styling

Use ::placeholder for input placeholder styling, not wrapper elements.

**Incorrect (custom placeholder node):**

```tsx
<div className={styles.inputWrapper}>
  {!value && <span className={styles.placeholder}>Enter text...</span>}
  <input value={value} />
</div>
```

**Correct (native ::placeholder):**

```css
input::placeholder {
  color: var(--gray-9);
  opacity: 1;
}
```

### Use ::selection for Text Styling

Use ::selection for text selection styling.

**Correct:**

```css
::selection {
  background: var(--blue-a5);
  color: var(--gray-12);
}
```

### Use ::marker for Custom List Bullets

Use ::marker to style list bullets without extra elements or background-image hacks.

**Incorrect (background image hack):**

```css
li {
  list-style: none;
  background: url("bullet.svg") no-repeat 0 4px;
  padding-left: 20px;
}
```

**Correct (native ::marker):**

```css
li::marker {
  color: var(--gray-8);
  font-size: 0.8em;
}
```

### Use ::first-line for Typographic Treatments

Use ::first-line for drop-cap-adjacent styling without JavaScript or hardcoded spans.

**Incorrect (manual span):**

```tsx
<p>
  <span className={styles["first-line"]}>The opening line</span>
  is styled differently from the rest.
</p>
```

**Correct (native ::first-line):**

```css
.article p:first-of-type::first-line {
  font-variant-caps: small-caps;
  font-weight: var(--font-weight-medium);
}
```

Reference: [MDN Pseudo-elements Reference](https://developer.mozilla.org/en-US/docs/Web/CSS/Reference/Selectors/Pseudo-elements), [View Transitions API](https://developer.mozilla.org/en-US/docs/Web/API/View_Transitions_API)

---

## Morphing Icons

Every icon is composed of exactly three SVG lines. Icons that need fewer lines collapse the extras to invisible center points. This constraint enables seamless morphing between any two icons.

**Architecture:**

```ts
interface IconLine {
  x1: number;
  y1: number;
  x2: number;
  y2: number;
  opacity?: number;
}

interface IconDefinition {
  lines: [IconLine, IconLine, IconLine];
  rotation?: number;
  group?: string;
}

const CENTER = 7;
const collapsed: IconLine = {
  x1: CENTER, y1: CENTER, x2: CENTER, y2: CENTER, opacity: 0,
};
```

### Icons Must Use Exactly Three Lines

Every icon MUST use exactly 3 lines. No more, no fewer.

**Incorrect (only 2 lines):**

```ts
const checkIcon = {
  lines: [
    { x1: 2, y1: 7.5, x2: 5.5, y2: 11 },
    { x1: 5.5, y1: 11, x2: 12, y2: 3 },
  ],
};
```

**Correct (3 lines with collapsed):**

```ts
const checkIcon = {
  lines: [
    { x1: 2, y1: 7.5, x2: 5.5, y2: 11 },
    { x1: 5.5, y1: 11, x2: 12, y2: 3 },
    collapsed,
  ],
};
```

### Use Collapsed Constant for Unused Lines

Unused lines must use the collapsed constant, not omission or null.

**Incorrect (null for unused):**

```ts
const minusIcon = {
  lines: [
    { x1: 2, y1: 7, x2: 12, y2: 7 },
    null,
    null,
  ],
};
```

**Correct (collapsed constant):**

```ts
const minusIcon = {
  lines: [
    { x1: 2, y1: 7, x2: 12, y2: 7 },
    collapsed,
    collapsed,
  ],
};
```

### Consistent ViewBox Size

All icons must use the same viewBox (14x14 recommended).

**Incorrect (mixed scales):**

```ts
const icon1 = { lines: [{ x1: 2, y1: 7, x2: 12, y2: 7 }, ...] }; // 14x14
const icon2 = { lines: [{ x1: 4, y1: 14, x2: 24, y2: 14 }, ...] }; // 28x28
```

**Correct (consistent scale):**

```ts
const VIEWBOX_SIZE = 14;
const CENTER = 7;
```

### Shared Group for Rotational Variants

Icons that are rotational variants MUST share the same group and base lines.

**Incorrect (different line definitions):**

```ts
const arrowRight = { lines: [{ x1: 2, y1: 7, x2: 12, y2: 7 }, ...] };
const arrowDown = { lines: [{ x1: 7, y1: 2, x2: 7, y2: 12 }, ...] };
```

**Correct (shared base lines):**

```ts
const arrowLines: [IconLine, IconLine, IconLine] = [
  { x1: 2, y1: 7, x2: 12, y2: 7 },
  { x1: 7.5, y1: 2.5, x2: 12, y2: 7 },
  { x1: 7.5, y1: 11.5, x2: 12, y2: 7 },
];

const icons = {
  "arrow-right": { lines: arrowLines, rotation: 0, group: "arrow" },
  "arrow-down": { lines: arrowLines, rotation: 90, group: "arrow" },
  "arrow-left": { lines: arrowLines, rotation: 180, group: "arrow" },
  "arrow-up": { lines: arrowLines, rotation: -90, group: "arrow" },
};
```

### Spring Physics for Rotation

Rotation between grouped icons should use spring physics for natural motion.

**Incorrect (duration-based rotation):**

```tsx
<motion.g animate={{ rotate: rotation }} transition={{ duration: 0.3 }} />
```

**Correct (spring rotation):**

```tsx
const rotation = useSpring(definition.rotation ?? 0, activeTransition);

<motion.g style={{ rotate: rotation, transformOrigin: "center" }} />
```

### Reduced Motion Support for Icons

Respect prefers-reduced-motion by disabling animations.

**Incorrect (always animates):**

```tsx
function MorphingIcon({ icon }: Props) {
  return <motion.line animate={...} transition={{ duration: 0.4 }} />;
}
```

**Correct (respects preference):**

```tsx
function MorphingIcon({ icon }: Props) {
  const reducedMotion = useReducedMotion() ?? false;
  const activeTransition = reducedMotion ? { duration: 0 } : transition;

  return <motion.line animate={...} transition={activeTransition} />;
}
```

### Instant Jump for Non-Grouped Icons

When transitioning between icons NOT in the same group, rotation should jump instantly.

**Incorrect (always animates rotation):**

```tsx
useEffect(() => {
  rotation.set(definition.rotation ?? 0);
}, [definition]);
```

**Correct (jumps when not grouped):**

```tsx
useEffect(() => {
  if (shouldRotate) {
    rotation.set(definition.rotation ?? 0);
  } else {
    rotation.jump(definition.rotation ?? 0);
  }
}, [definition, shouldRotate]);
```

### Round Stroke Line Caps

Lines should use strokeLinecap="round" for polished endpoints.

**Incorrect (butt caps):**

```tsx
<motion.line strokeLinecap="butt" />
```

**Correct (round caps):**

```tsx
<motion.line strokeLinecap="round" />
```

### Aria Hidden on Icon SVGs

Icon SVGs should be aria-hidden since they're decorative.

**Incorrect (no aria attribute):**

```tsx
<svg width={size} height={size}>...</svg>
```

**Correct (aria-hidden):**

```tsx
<svg width={size} height={size} aria-hidden="true">...</svg>
```

**Common icon patterns:**

```ts
// Two-line icons (check, minus, chevron) — one collapsed line
const check = {
  lines: [
    { x1: 2, y1: 7.5, x2: 5.5, y2: 11 },
    { x1: 5.5, y1: 11, x2: 12, y2: 3 },
    collapsed,
  ],
};

// Three-line icons (menu, asterisk) — all lines used
const menu = {
  lines: [
    { x1: 2, y1: 3.5, x2: 12, y2: 3.5 },
    { x1: 2, y1: 7, x2: 12, y2: 7 },
    { x1: 2, y1: 10.5, x2: 12, y2: 10.5 },
  ],
};

// Point icons (more, grip) — zero-length lines as dots
const more = {
  lines: [
    { x1: 3, y1: 7, x2: 3, y2: 7 },
    { x1: 7, y1: 7, x2: 7, y2: 7 },
    { x1: 11, y1: 7, x2: 11, y2: 7 },
  ],
};
```

**Recommended transition:**

```ts
const defaultTransition: Transition = {
  ease: [0.19, 1, 0.22, 1],
  duration: 0.4,
};
```

Reference: [Motion useSpring](https://motion.dev/docs/react-use-spring), [SVG Line Element](https://developer.mozilla.org/en-US/docs/Web/SVG/Element/line)

---

## Visual Design Fundamentals

CSS design fundamentals that compound into visual polish. Small details that separate considered interfaces from default ones.

### Concentric Border Radius for Nested Elements

When nesting rounded elements, inner radius must equal outer radius minus the gap. Same radius on both creates uneven curves.

**Incorrect (same radius on both):**

```css
.outer {
  border-radius: 16px;
  padding: 8px;
}

.inner {
  border-radius: 16px;
}
```

**Correct (concentric radius):**

```css
.outer {
  --padding: 8px;
  --inner-radius: 8px;

  border-radius: calc(var(--inner-radius) + var(--padding));
  padding: var(--padding);
}

.inner {
  border-radius: var(--inner-radius);
}
```

### Layer Multiple Shadows for Realistic Depth

A single box-shadow looks flat. Layer multiple shadows with increasing blur and decreasing opacity to mimic real light.

**Incorrect (single flat shadow):**

```css
.card {
  box-shadow: 0 4px 16px rgba(0, 0, 0, 0.2);
}
```

**Correct (layered shadows):**

```css
.card {
  box-shadow:
    0 1px 2px rgba(0, 0, 0, 0.06),
    0 4px 8px rgba(0, 0, 0, 0.04),
    0 12px 24px rgba(0, 0, 0, 0.03);
}
```

### Consistent Shadow Direction Across UI

All shadows must share the same offset direction to imply a single light source. Mixed directions feel broken.

**Incorrect (conflicting light sources):**

```css
.card { box-shadow: 0 4px 8px rgba(0, 0, 0, 0.1); }
.modal { box-shadow: 4px 0 8px rgba(0, 0, 0, 0.1); }
.tooltip { box-shadow: 0 -4px 8px rgba(0, 0, 0, 0.1); }
```

**Correct (consistent top-down light):**

```css
.card { box-shadow: 0 2px 8px rgba(0, 0, 0, 0.08); }
.modal { box-shadow: 0 8px 24px rgba(0, 0, 0, 0.12); }
.tooltip { box-shadow: 0 4px 12px rgba(0, 0, 0, 0.1); }
```

### Use Neutral Colors for Shadows

Pure black shadows look harsh. Use deep neutrals or semi-transparent dark colors.

**Incorrect (pure black):**

```css
.card {
  box-shadow: 0 4px 12px rgba(0, 0, 0, 0.25);
}
```

**Correct (neutral shadow):**

```css
.card {
  box-shadow: 0 4px 12px rgba(17, 24, 39, 0.08);
}
```

### Shadow Size Indicates Elevation

Larger blur and offset means higher elevation. Use a consistent shadow scale.

**Correct (elevation scale):**

```css
:root {
  --shadow-1: 0 1px 2px rgba(0, 0, 0, 0.05);
  --shadow-2: 0 2px 8px rgba(0, 0, 0, 0.08);
  --shadow-3: 0 8px 24px rgba(0, 0, 0, 0.12);
}

.card { box-shadow: var(--shadow-1); }
.dropdown { box-shadow: var(--shadow-2); }
.modal { box-shadow: var(--shadow-3); }
```

### Animate Shadows via Pseudo-Element Opacity

Transitioning box-shadow directly forces expensive repaints. Animate opacity on a pseudo-element instead.

**Incorrect (animating box-shadow):**

```css
.card {
  box-shadow: var(--shadow-1);
  transition: box-shadow 0.2s ease;
}
.card:hover {
  box-shadow: var(--shadow-3);
}
```

**Correct (pseudo-element opacity):**

```css
.card {
  position: relative;
  box-shadow: var(--shadow-1);
}
.card::after {
  content: "";
  position: absolute;
  inset: 0;
  border-radius: inherit;
  box-shadow: var(--shadow-3);
  opacity: 0;
  transition: opacity 0.2s ease;
  pointer-events: none;
  z-index: -1;
}
.card:hover::after {
  opacity: 1;
}
```

### Use a Consistent Spacing Scale

Don't use arbitrary pixel values. Define a scale and use it throughout.

**Incorrect (arbitrary values):**

```css
.header { padding: 17px; }
.card { margin-bottom: 13px; }
.section { gap: 22px; }
```

**Correct (consistent scale):**

```css
:root {
  --space-1: 4px;
  --space-2: 8px;
  --space-3: 12px;
  --space-4: 16px;
  --space-5: 24px;
  --space-6: 32px;
  --space-7: 48px;
}

.header { padding: var(--space-4); }
.card { margin-bottom: var(--space-3); }
.section { gap: var(--space-5); }
```

### Use Semi-Transparent Borders

Semi-transparent borders adapt to any background color and create subtle, non-jarring separation.

**Incorrect (hardcoded border color):**

```css
.card {
  border: 1px solid #e5e5e5;
}
```

**Correct (alpha border):**

```css
.card {
  border: 1px solid var(--gray-a4);
}
```

### Full Shadow Anatomy on Buttons

A polished button uses six layered techniques, not just a single box-shadow:

1. **Outer cut shadow** — 0.5px dark box-shadow to "cut" the button into the surface
2. **Inner ambient highlight** — 1px inset box-shadow on all sides for environmental light reflections
3. **Inner top highlight** — 1px inset top highlight for the primary light source from above
4. **Layered depth shadows** — At least 3 external shadows for natural lighting
5. **Text drop-shadow** — Drop-shadow on text/icons for better contrast against the button background
6. **Subtle gradient background** — If you can tell there's a gradient, it's too much

**Incorrect (flat button):**

```css
.button {
  background: var(--gray-12);
  color: var(--gray-1);
  box-shadow: 0 2px 4px rgba(0, 0, 0, 0.1);
}
```

**Correct (full shadow anatomy):**

```css
.button {
  background: linear-gradient(
    to bottom,
    color-mix(in srgb, var(--gray-12) 100%, white 4%),
    var(--gray-12)
  );
  color: var(--gray-1);
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

Reference: [Designing Beautiful Shadows in CSS](https://www.joshwcomeau.com/css/designing-shadows/), [Concentric Border Radius](https://jakub.kr/work/concentric-border-radius), [@PixelJanitor](https://threadreaderapp.com/thread/1623358514440859649)
