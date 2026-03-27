# UI Animation Guidelines

## Core Philosophy

### Taste is trained, not innate

Good taste is not personal preference. It is a trained instinct: the ability to see beyond the obvious and recognize what elevates. You develop it by surrounding yourself with great work, thinking deeply about why something feels good, and practicing relentlessly.

When building UI, don't just make it work. Study why the best interfaces feel the way they do. Reverse engineer animations. Inspect interactions. Be curious.

### Unseen details compound

Most details users never consciously notice. That is the point. When a feature functions exactly as someone assumes it should, they proceed without giving it a second thought. That is the goal.

Every decision in this document exists because the aggregate of invisible correctness creates interfaces people love without knowing why.

### Beauty is leverage

People select tools based on the overall experience, not just functionality. Good defaults and good animations are real differentiators. Beauty is underutilized in software. Use it as leverage to stand out.

---

## Animation Decision Framework

Before writing any animation code, answer these questions in order:

### 1. Should this animate at all?

**Ask:** How often will users see this animation?

| Frequency | Decision |
| --- | --- |
| 100+ times/day (keyboard shortcuts, command palette toggle) | No animation. Ever. |
| Tens of times/day (hover effects, list navigation) | Remove or drastically reduce |
| Occasional (modals, drawers, toasts) | Standard animation |
| Rare/first-time (onboarding, feedback forms, celebrations) | Can add delight |

**Never animate keyboard-initiated actions.** These actions are repeated hundreds of times daily. Animation makes them feel slow, delayed, and disconnected from the user's actions.

**No animation for high-frequency interactions.** Typing feedback, fast toggles, and similar rapid interactions should have zero animation — animation adds noise and feels slower.

**Incorrect (animated on every keystroke):**

```tsx
function SearchInput() {
  return (
    <motion.div animate={{ scale: [1, 1.02, 1] }}>
      <input onChange={handleSearch} />
    </motion.div>
  );
}
```

**Correct (no animation):**

```tsx
function SearchInput() {
  return <input onChange={handleSearch} />;
}
```

**No animation for keyboard navigation:**

**Incorrect (animated focus):**

```tsx
function Menu() {
  return items.map(item => (
    <motion.li
      whileFocus={{ scale: 1.05 }}
      transition={{ duration: 0.2 }}
    />
  ));
}
```

**Correct (CSS focus-visible only):**

```tsx
function Menu() {
  return items.map(item => (
    <li className={styles.menuItem} />
  ));
}
```

### 2. What is the purpose?

Every animation must have a clear answer to "why does this animate?"

Valid purposes:

- **Spatial consistency**: toast enters and exits from the same direction, making swipe-to-dismiss feel intuitive
- **State indication**: a morphing feedback button shows the state change
- **Explanation**: a marketing animation that shows how a feature works
- **Feedback**: a button scales down on press, confirming the interface heard the user
- **Preventing jarring changes**: elements appearing or disappearing without transition feel broken

If the purpose is just "it looks cool" and the user will see it often, don't animate.

### 3. What easing should it use?

Decision tree:

| Motion Type | Best Choice | Why |
| --- | --- | --- |
| User-driven (drag, flick, gesture) | Spring | Survives interruption, preserves velocity |
| System-driven (state change, feedback) | Easing | Clear start/end, predictable timing |
| Time representation (progress, loading) | Linear | 1:1 relationship between time and progress |
| High-frequency (typing, fast toggles) | None | Animation adds noise, feels slower |

For easing-based animations:

- **Entering the screen?** Use ease-out (starts fast, feels responsive)
- **Exiting the screen?** Use ease-in (builds momentum before departure)
- **Moving/morphing on screen?** Use ease-in-out (natural acceleration/deceleration)
- **Hover/color change?** Use ease
- **Constant motion (marquee, progress bar)?** Use linear
- **Default?** Use ease-out

**Critical: use custom easing curves.** The built-in CSS easings are too weak. They lack the punch that makes animations feel intentional.

```css
/* Strong ease-out for UI interactions */
--ease-out: cubic-bezier(0.23, 1, 0.32, 1);

/* Strong ease-in-out for on-screen movement */
--ease-in-out: cubic-bezier(0.77, 0, 0.175, 1);

/* iOS-like drawer curve (from Ionic Framework) */
--ease-drawer: cubic-bezier(0.32, 0.72, 0, 1);
```

**Never use ease-in for UI entrance animations.** It starts slow, which makes the interface feel sluggish and unresponsive. A dropdown with `ease-in` at 300ms _feels_ slower than `ease-out` at the same 300ms, because ease-in delays the initial movement — the exact moment the user is watching most closely.

**Easing curve resources:** Don't create curves from scratch. Use [easing.dev](https://easing.dev/) or [easings.co](https://easings.co/) to find stronger custom variants of standard easings.

### 4. How fast should it be?

| Element | Duration |
| --- | --- |
| Button press / hover feedback | 100-180ms |
| Tooltips, small popovers | 125-200ms |
| Dropdowns, selects | 150-250ms |
| Small state changes (toggles) | 180-260ms |
| Modals, drawers | 200-500ms |
| Marketing/explanatory | Can be longer |

**Rule: UI animations should stay under 300ms.** If animation feels slow, shorten duration before adjusting curve.

**Incorrect (adjusting curve instead of duration):**

```css
.element { transition: 400ms cubic-bezier(0, 0.9, 0.1, 1); }
```

**Correct (shorter duration):**

```css
.element { transition: 200ms ease-out; }
```

### Perceived performance

Speed in animation is not just about feeling snappy — it directly affects how users perceive your app's performance:

- A **fast-spinning spinner** makes loading feel faster (same load time, different perception)
- A **180ms select** animation feels more responsive than a **400ms** one
- **Instant tooltips** after the first one is open (skip delay + skip animation) make the whole toolbar feel faster

The perception of speed matters as much as actual speed. Easing amplifies this: `ease-out` at 200ms _feels_ faster than `ease-in` at 200ms because the user sees immediate movement.

### Quick reference

| Interaction | Timing | Type |
| --- | --- | --- |
| Drag release | Spring | `stiffness: 500, damping: 30` |
| Button press | 150ms | `ease` |
| Modal enter | 200ms | `ease-out` |
| Modal exit | 150ms | `ease-in` |
| Page transition | 250ms | `ease-in-out` |
| Progress bar | varies | `linear` |
| Typing feedback | 0ms | none |

---

## Animation Principles

### Consistent timing for similar elements

Similar elements must use identical timing values.

**Incorrect (inconsistent timing):**

```css
.button-primary { transition: 200ms; }
.button-secondary { transition: 150ms; }
```

**Correct (consistent timing):**

```css
.button-primary { transition: 200ms; }
.button-secondary { transition: 200ms; }
```

### No entrance animation on context menus

Context menus should not animate on entrance (exit only).

**Incorrect (animates entrance):**

```tsx
<motion.div
  initial={{ opacity: 0, scale: 0.95 }}
  animate={{ opacity: 1, scale: 1 }}
  exit={{ opacity: 0 }}
/>
```

**Correct (exit only):**

```tsx
<motion.div exit={{ opacity: 0, scale: 0.95 }} />
```

### No linear easing for motion

Linear easing should only be used for progress indicators, not motion.

**Incorrect (linear for motion):**

```css
.card { transition: transform 200ms linear; }
```

**Correct (linear for progress only):**

```css
.progress-bar { transition: width 100ms linear; }
```

### Active state scale transform

Interactive elements must have active/pressed state with scale transform.

**Incorrect (no active state):**

```css
.button:hover { background: var(--gray-3); }
/* Missing :active state */
```

**Correct (active state present):**

```css
.button:active { transform: scale(0.98); }
```

### Subtle squash and stretch

Squash/stretch deformation must be subtle (0.95-1.05 range).

**Incorrect (excessive deformation):**

```tsx
<motion.div whileTap={{ scale: 0.8 }} />
```

**Correct (subtle deformation):**

```tsx
<motion.div whileTap={{ scale: 0.98 }} />
```

### Exponential ramps for natural decay

Use exponential ramps, not linear, for natural decay.

**Incorrect (linear ramp):**

```ts
gain.gain.linearRampToValueAtTime(0, t + 0.05);
```

**Correct (exponential ramp):**

```ts
gain.gain.exponentialRampToValueAtTime(0.001, t + 0.05);
```

### Single focal point

Only one element should animate prominently at a time.

**Incorrect (competing animations):**

```tsx
<motion.div animate={{ scale: 1.1 }} />
<motion.div animate={{ scale: 1.1 }} />
```

### Dim background for focus

Modal/dialog backgrounds should dim to direct focus.

**Incorrect (transparent overlay):**

```css
.overlay { background: transparent; }
```

**Correct (dimmed overlay):**

```css
.overlay { background: var(--black-a6); }
```

### Z-index layering for animated elements

Animated elements must respect z-index layering.

**Incorrect (no z-index):**

```css
.tooltip { /* No z-index, may render behind other elements */ }
```

**Correct (explicit z-index):**

```css
.tooltip { z-index: 50; }
```

---

## Timing Functions

### Springs vs Easing vs Linear vs None

| Motion Type | Best Choice | Why |
| --- | --- | --- |
| User-driven (drag, flick, gesture) | Spring | Survives interruption, preserves velocity |
| System-driven (state change, feedback) | Easing | Clear start/end, predictable timing |
| Time representation (progress, loading) | Linear | 1:1 relationship between time and progress |
| High-frequency (typing, fast toggles) | None | Animation adds noise, feels slower |

### Springs for gesture-driven motion

Gesture-driven motion (drag, flick, swipe) must use springs.

**Incorrect (easing for drag):**

```tsx
<motion.div
  drag="x"
  transition={{ duration: 0.3, ease: "easeOut" }}
/>
```

**Correct (spring for drag):**

```tsx
<motion.div
  drag="x"
  transition={{ type: "spring", stiffness: 500, damping: 30 }}
/>
```

### Springs for interruptible motion

Motion that can be interrupted must use springs.

**Incorrect (easing for interruptible):**

```tsx
<motion.div
  animate={{ x: isOpen ? 200 : 0 }}
  transition={{ duration: 0.3 }}
/>
```

**Correct (spring for interruptible):**

```tsx
<motion.div
  animate={{ x: isOpen ? 200 : 0 }}
  transition={{ type: "spring", stiffness: 400, damping: 25 }}
/>
```

### Springs preserve input velocity

When velocity matters, use springs to preserve input energy.

**Incorrect (velocity ignored):**

```tsx
onDragEnd={(e, info) => {
  animate(target, { x: 0 }, { duration: 0.3 });
}}
```

**Correct (velocity preserved):**

```tsx
onDragEnd={(e, info) => {
  animate(target, { x: 0 }, {
    type: "spring",
    velocity: info.velocity.x,
  });
}}
```

### Balanced spring parameters

Spring parameters must be balanced; avoid excessive oscillation.

**Incorrect (too bouncy):**

```tsx
transition={{
  type: "spring",
  stiffness: 1000,
  damping: 5,
}}
```

**Correct (balanced):**

```tsx
transition={{
  type: "spring",
  stiffness: 500,
  damping: 30,
}}
```

### Easing for system state changes

System-initiated state changes should use easing curves, not springs.

**Incorrect (spring for announcement):**

```tsx
<motion.div
  animate={{ y: 0 }}
  transition={{ type: "spring" }}
/>
```

**Correct (easing for announcement):**

```tsx
<motion.div
  animate={{ y: 0 }}
  transition={{ duration: 0.2, ease: "easeOut" }}
/>
```

### Ease-out for entrances

Entrances must use ease-out (arrive fast, settle gently).

**Incorrect (ease-in for entrance):**

```css
.modal-enter { animation-timing-function: ease-in; }
```

**Correct (ease-out for entrance):**

```css
.modal-enter { animation-timing-function: ease-out; }
```

### Ease-in for exits

Exits must use ease-in (build momentum before departure).

**Incorrect (ease-out for exit):**

```css
.modal-exit { animation-timing-function: ease-out; }
```

**Correct (ease-in for exit):**

```css
.modal-exit { animation-timing-function: ease-in; }
```

### Ease-in-out for view transitions

View/mode transitions use ease-in-out for neutral attention.

```css
.page-transition { animation-timing-function: ease-in-out; }
```

---

## Spring Animations

Springs feel more natural than duration-based animations because they simulate real physics. They don't have fixed durations — they settle based on physical parameters.

### When to use springs

- Drag interactions with momentum
- Elements that should feel "alive" (like Apple's Dynamic Island)
- Gestures that can be interrupted mid-animation
- Decorative mouse-tracking interactions
- Any motion where overshoot-and-settle is desired

### Spring-based mouse interactions

Tying visual changes directly to mouse position feels artificial because it lacks motion. Use `useSpring` from Motion to interpolate value changes with spring-like behavior instead of updating immediately.

```jsx
import { useSpring } from 'framer-motion';

// Without spring: feels artificial, instant
const rotation = mouseX * 0.1;

// With spring: feels natural, has momentum
const springRotation = useSpring(mouseX * 0.1, {
  stiffness: 100,
  damping: 10,
});
```

This works because the animation is **decorative** — it doesn't serve a function. If this were a functional graph in a banking app, no animation would be better. Know when decoration helps and when it hinders.

### Spring configuration

**Apple's approach (recommended — easier to reason about):**

```js
{ type: "spring", duration: 0.5, bounce: 0.2 }
```

**Traditional physics (more control):**

```js
{ type: "spring", mass: 1, stiffness: 100, damping: 10 }
```

Keep bounce subtle (0.1-0.3) when used. Avoid bounce in most UI contexts. Use it for drag-to-dismiss and playful interactions.

### Interruptibility advantage

Springs maintain velocity when interrupted — CSS animations and keyframes restart from zero. This makes springs ideal for gestures users might change mid-motion. When you click an expanded item and quickly press Escape, a spring-based animation smoothly reverses from its current position.

---

## Exit Animations

Correct AnimatePresence usage prevents layout shifts, stale interactions, and orphaned elements.

### AnimatePresence wrapper required

Conditional motion elements must be wrapped in AnimatePresence.

**Incorrect (no wrapper):**

```tsx
{isVisible && (
  <motion.div exit={{ opacity: 0 }} />
)}
```

**Correct (wrapped):**

```tsx
<AnimatePresence>
  {isVisible && (
    <motion.div exit={{ opacity: 0 }} />
  )}
</AnimatePresence>
```

### Exit prop required inside AnimatePresence

**Incorrect (missing exit):**

```tsx
<AnimatePresence>
  {isOpen && (
    <motion.div initial={{ opacity: 0 }} animate={{ opacity: 1 }} />
  )}
</AnimatePresence>
```

**Correct (exit defined):**

```tsx
<AnimatePresence>
  {isOpen && (
    <motion.div
      initial={{ opacity: 0 }}
      animate={{ opacity: 1 }}
      exit={{ opacity: 0 }}
    />
  )}
</AnimatePresence>
```

### Unique keys in AnimatePresence lists

Dynamic lists inside AnimatePresence must have unique, stable keys.

**Incorrect (index as key):**

```tsx
<AnimatePresence>
  {items.map((item, index) => (
    <motion.div key={index} exit={{ opacity: 0 }} />
  ))}
</AnimatePresence>
```

**Correct (stable unique key):**

```tsx
<AnimatePresence>
  {items.map((item) => (
    <motion.div key={item.id} exit={{ opacity: 0 }} />
  ))}
</AnimatePresence>
```

### Exit mirrors initial for symmetry

Exit animation should mirror initial for symmetry.

**Incorrect (asymmetric exit):**

```tsx
<motion.div
  initial={{ opacity: 0, y: 20 }}
  animate={{ opacity: 1, y: 0 }}
  exit={{ scale: 0 }}
/>
```

**Correct (symmetric exit):**

```tsx
<motion.div
  initial={{ opacity: 0, y: 20 }}
  animate={{ opacity: 1, y: 0 }}
  exit={{ opacity: 0, y: 20 }}
/>
```

### useIsPresent in child component

useIsPresent must be called from a child of AnimatePresence, not the parent.

**Incorrect (hook in parent):**

```tsx
function Parent() {
  const isPresent = useIsPresent();
  return (
    <AnimatePresence>
      {show && <Child />}
    </AnimatePresence>
  );
}
```

**Correct (hook in child):**

```tsx
function Child() {
  const isPresent = useIsPresent();
  return <motion.div data-exiting={!isPresent} />;
}
```

### Call safeToRemove after async work

When using usePresence, always call safeToRemove after async work.

**Incorrect (missing safeToRemove):**

```tsx
function AsyncComponent() {
  const [isPresent, safeToRemove] = usePresence();

  useEffect(() => {
    if (!isPresent) {
      cleanup();
    }
  }, [isPresent]);
}
```

**Correct (safeToRemove called):**

```tsx
function AsyncComponent() {
  const [isPresent, safeToRemove] = usePresence();

  useEffect(() => {
    if (!isPresent) {
      cleanup().then(safeToRemove);
    }
  }, [isPresent, safeToRemove]);
}
```

### Disable interactions on exiting elements

**Incorrect (clickable during exit):**

```tsx
function Card() {
  const isPresent = useIsPresent();
  return <button onClick={handleClick}>Click</button>;
}
```

**Correct (disabled during exit):**

```tsx
function Card() {
  const isPresent = useIsPresent();
  return (
    <button onClick={handleClick} disabled={!isPresent}>
      Click
    </button>
  );
}
```

### Mode "wait" doubles duration

Mode "wait" nearly doubles animation duration; adjust timing accordingly.

**Incorrect (too slow with wait):**

```tsx
<AnimatePresence mode="wait">
  <motion.div transition={{ duration: 0.3 }} />
</AnimatePresence>
```

**Correct (halved timing):**

```tsx
<AnimatePresence mode="wait">
  <motion.div transition={{ duration: 0.15 }} />
</AnimatePresence>
```

### Mode "sync" causes layout conflicts

Use popLayout instead of sync to prevent layout competition during list animations.

**Incorrect (sync with layout competition):**

```tsx
<AnimatePresence mode="sync">
  {items.map(item => (
    <motion.div exit={{ opacity: 0 }}>{item}</motion.div>
  ))}
</AnimatePresence>
```

**Correct (popLayout instead):**

```tsx
<AnimatePresence mode="popLayout">
  {items.map(item => (
    <motion.div exit={{ opacity: 0 }}>{item}</motion.div>
  ))}
</AnimatePresence>
```

### Propagate prop for nested AnimatePresence

Nested AnimatePresence must use propagate prop for coordinated exits.

**Incorrect (children vanish instantly):**

```tsx
<AnimatePresence>
  {isOpen && (
    <motion.div exit={{ opacity: 0 }}>
      <AnimatePresence>
        {items.map(item => (
          <motion.div key={item.id} exit={{ scale: 0 }} />
        ))}
      </AnimatePresence>
    </motion.div>
  )}
</AnimatePresence>
```

**Correct (propagate on both):**

```tsx
<AnimatePresence propagate>
  {isOpen && (
    <motion.div exit={{ opacity: 0 }}>
      <AnimatePresence propagate>
        {items.map(item => (
          <motion.div key={item.id} exit={{ scale: 0 }} />
        ))}
      </AnimatePresence>
    </motion.div>
  )}
</AnimatePresence>
```

### Coordinated parent-child exit timing

Parent and child exit durations should be coordinated.

**Incorrect (parent too fast):**

```tsx
<motion.div exit={{ opacity: 0 }} transition={{ duration: 0.1 }}>
  <motion.div exit={{ scale: 0 }} transition={{ duration: 0.5 }} />
</motion.div>
```

**Correct (coordinated timing):**

```tsx
<motion.div exit={{ opacity: 0 }} transition={{ duration: 0.2 }}>
  <motion.div exit={{ scale: 0 }} transition={{ duration: 0.15 }} />
</motion.div>
```

---

## Container Animation

Animating container width and height using a measure-and-animate pattern with ResizeObserver and Motion.

### Two-div pattern for animated bounds

Use an outer animated div and an inner measured div. Never measure and animate the same element — it creates a feedback loop.

**Incorrect (measure and animate same element):**

```tsx
function AnimatedContainer({ children }) {
  const [ref, bounds] = useMeasure();
  return (
    <motion.div ref={ref} animate={{ height: bounds.height }}>
      {children}
    </motion.div>
  );
}
```

**Correct (separate measure and animate targets):**

```tsx
function AnimatedContainer({ children }) {
  const [ref, bounds] = useMeasure();
  return (
    <motion.div animate={{ height: bounds.height }}>
      <div ref={ref}>{children}</div>
    </motion.div>
  );
}
```

### Guard against zero on initial render

On initial render, measured bounds are 0. Guard against this to prevent animating from 0 to actual size.

**Incorrect (animates from 0 on mount):**

```tsx
<motion.div animate={{ width: bounds.width }}>
  <div ref={ref}>{children}</div>
</motion.div>
```

**Correct (falls back to auto on first frame):**

```tsx
<motion.div animate={{ width: bounds.width > 0 ? bounds.width : "auto" }}>
  <div ref={ref}>{children}</div>
</motion.div>
```

### Use ResizeObserver for measurement

Use ResizeObserver to track element dimensions. It fires on resize without causing layout thrashing.

**Incorrect (measuring on every render):**

```tsx
function useMeasure(ref) {
  const [bounds, setBounds] = useState({ width: 0, height: 0 });
  useEffect(() => {
    if (ref.current) {
      const rect = ref.current.getBoundingClientRect();
      setBounds({ width: rect.width, height: rect.height });
    }
  });
  return bounds;
}
```

**Correct (ResizeObserver):**

```tsx
function useMeasure() {
  const [element, setElement] = useState(null);
  const [bounds, setBounds] = useState({ width: 0, height: 0 });
  const ref = useCallback((node) => setElement(node), []);

  useEffect(() => {
    if (!element) return;
    const observer = new ResizeObserver(([entry]) => {
      setBounds({
        width: entry.contentRect.width,
        height: entry.contentRect.height,
      });
    });
    observer.observe(element);
    return () => observer.disconnect();
  }, [element]);

  return [ref, bounds];
}
```

### Overflow hidden on animated container

Set overflow: hidden on the animated outer container to clip content during size transitions.

**Incorrect (content overflows during animation):**

```tsx
<motion.div animate={{ height: bounds.height }}>
  <div ref={ref}>{children}</div>
</motion.div>
```

**Correct (clipped during transition):**

```tsx
<motion.div animate={{ height: bounds.height }} style={{ overflow: "hidden" }}>
  <div ref={ref}>{children}</div>
</motion.div>
```

### Use animated bounds sparingly

Animated bounds is a subtle effect. Reserve it for interactive elements where size changes are meaningful.

**Good use cases:** loading state buttons, expandable sections, accordions, FAQs, content reveals.

**Bad use cases:** every container on the page, static layouts, elements that don't change size.

### Use callback ref for measurement

Use a callback ref (not useRef) for measurement hooks so the observer attaches when the DOM node is ready.

**Incorrect (useRef may be null on first effect):**

```tsx
const ref = useRef(null);
useEffect(() => {
  if (!ref.current) return;
  observer.observe(ref.current);
}, []);
```

**Correct (callback ref guarantees node):**

```tsx
const [element, setElement] = useState(null);
const ref = useCallback((node) => setElement(node), []);
useEffect(() => {
  if (!element) return;
  observer.observe(element);
  return () => observer.disconnect();
}, [element]);
```

### Add delay for natural container transitions

Add a small delay so the transition feels like it's catching up to the content.

```tsx
<motion.div
  animate={{ height: bounds.height }}
  transition={{ duration: 0.2, delay: 0.05 }}
  style={{ overflow: "hidden" }}
>
  <div ref={ref}>{children}</div>
</motion.div>
```

---

## Component Building Principles

### Buttons must feel responsive

Add `transform: scale(0.97)` on `:active`. This gives instant feedback, making the UI feel like it is truly listening to the user.

```css
.button {
  transition: transform 160ms ease-out;
}

.button:active {
  transform: scale(0.97);
}
```

This applies to any pressable element. The scale should be subtle (0.95-0.98).

### Never animate from scale(0)

Nothing in the real world disappears and reappears completely. Elements animating from `scale(0)` look like they come out of nowhere.

Start from `scale(0.9)` or higher, combined with opacity. Even a barely-visible initial scale makes the entrance feel more natural.

```css
/* Bad */
.entering {
  transform: scale(0);
}

/* Good */
.entering {
  transform: scale(0.95);
  opacity: 0;
}
```

### Make popovers origin-aware

Popovers should scale in from their trigger, not from center. The default `transform-origin: center` is wrong for almost every popover. **Exception: modals.** Modals should keep `transform-origin: center` because they are not anchored to a specific trigger.

```css
/* Radix UI */
.popover {
  transform-origin: var(--radix-popover-content-transform-origin);
}

/* Base UI */
.popover {
  transform-origin: var(--transform-origin);
}
```

### Tooltips: skip delay on subsequent hovers

Tooltips should delay before appearing to prevent accidental activation. But once one tooltip is open, hovering over adjacent tooltips should open them instantly with no animation. This feels faster without defeating the purpose of the initial delay.

```css
.tooltip {
  transition: transform 125ms ease-out, opacity 125ms ease-out;
  transform-origin: var(--transform-origin);
}

.tooltip[data-starting-style],
.tooltip[data-ending-style] {
  opacity: 0;
  transform: scale(0.97);
}

/* Skip animation on subsequent tooltips */
.tooltip[data-instant] {
  transition-duration: 0ms;
}
```

### Use CSS transitions over keyframes for interruptible UI

CSS transitions can be interrupted and retargeted mid-animation. Keyframes restart from zero. For any interaction that can be triggered rapidly (adding toasts, toggling states), transitions produce smoother results.

```css
/* Interruptible — good for UI */
.toast {
  transition: transform 400ms ease;
}

/* Not interruptible — avoid for dynamic UI */
@keyframes slideIn {
  from {
    transform: translateY(100%);
  }
  to {
    transform: translateY(0);
  }
}
```

### Use blur to mask imperfect transitions

When a crossfade between two states feels off despite trying different easings and durations, add subtle `filter: blur(2px)` during the transition. Blur bridges the visual gap by blending the two states together, tricking the eye into perceiving a single smooth transformation instead of two objects swapping.

```css
.button {
  transition: transform 160ms ease-out;
}

.button:active {
  transform: scale(0.97);
}

.button-content {
  transition: filter 200ms ease, opacity 200ms ease;
}

.button-content.transitioning {
  filter: blur(2px);
  opacity: 0.7;
}
```

Keep blur under 20px. Heavy blur is expensive, especially in Safari.

### Animate enter states with @starting-style

The modern CSS way to animate element entry without JavaScript:

```css
.toast {
  opacity: 1;
  transform: translateY(0);
  transition: opacity 400ms ease, transform 400ms ease;

  @starting-style {
    opacity: 0;
    transform: translateY(100%);
  }
}
```

This replaces the common React pattern of using `useEffect` to set `mounted: true` after initial render. Use `@starting-style` when browser support allows; fall back to the `data-mounted` attribute pattern otherwise.

```jsx
// Legacy pattern (still works everywhere)
useEffect(() => {
  setMounted(true);
}, []);
// <div data-mounted={mounted}>
```

### Asymmetric enter/exit timing

Pressing should be slow when it needs to be deliberate (hold-to-delete: 2s linear), but release should always be snappy (200ms ease-out). This pattern applies broadly: slow where the user is deciding, fast where the system is responding.

```css
/* Release: fast */
.overlay {
  transition: clip-path 200ms ease-out;
}

/* Press: slow and deliberate */
.button:active .overlay {
  transition: clip-path 2s linear;
}
```

### Cohesion matters

Animation should match the personality of the component. A playful component can be bouncier. A professional dashboard should be crisp and fast. Match the motion to the mood.

The easing and duration should fit the vibe of the component. It is not just about technical correctness — it is about the animation style matching the design, the personality, the name — everything in harmony.

---

## CSS Transform Mastery

### translateY with percentages

Percentage values in `translate()` are relative to the element's own size. Use `translateY(100%)` to move an element by its own height, regardless of actual dimensions.

```css
/* Works regardless of drawer height */
.drawer-hidden {
  transform: translateY(100%);
}

/* Works regardless of toast height */
.toast-enter {
  transform: translateY(-100%);
}
```

Prefer percentages over hardcoded pixel values. They are less error-prone and adapt to content.

### scale() scales children too

Unlike `width`/`height`, `scale()` also scales an element's children. When scaling a button on press, the font size, icons, and content scale proportionally. This is a feature, not a bug.

### 3D transforms for depth

`rotateX()`, `rotateY()` with `transform-style: preserve-3d` create real 3D effects in CSS. Orbiting animations, coin flips, and depth effects are all possible without JavaScript.

```css
.wrapper {
  transform-style: preserve-3d;
}

@keyframes orbit {
  from {
    transform: translate(-50%, -50%) rotateY(0deg) translateZ(72px) rotateY(360deg);
  }
  to {
    transform: translate(-50%, -50%) rotateY(360deg) translateZ(72px) rotateY(0deg);
  }
}
```

### transform-origin

Every element has an anchor point from which transforms execute. The default is center. Set it to match where the trigger lives for origin-aware interactions.

---

## clip-path for Animation

`clip-path` is not just for shapes. It is one of the most powerful animation tools in CSS.

### The inset shape

`clip-path: inset(top right bottom left)` defines a rectangular clipping region. Each value "eats" into the element from that side.

```css
/* Fully hidden from right */
.hidden {
  clip-path: inset(0 100% 0 0);
}

/* Fully visible */
.visible {
  clip-path: inset(0 0 0 0);
}

/* Reveal from left to right */
.overlay {
  clip-path: inset(0 100% 0 0);
  transition: clip-path 200ms ease-out;
}
.button:active .overlay {
  clip-path: inset(0 0 0 0);
  transition: clip-path 2s linear;
}
```

### Tabs with perfect color transitions

Duplicate the tab list. Style the copy as "active" (different background, different text color). Clip the copy so only the active tab is visible. Animate the clip on tab change. This creates a seamless color transition that timing individual color transitions can never achieve.

### Hold-to-delete pattern

Use `clip-path: inset(0 100% 0 0)` on a colored overlay. On `:active`, transition to `inset(0 0 0 0)` over 2s with linear timing. On release, snap back with 200ms ease-out. Add `scale(0.97)` on the button for press feedback.

### Image reveals on scroll

Start with `clip-path: inset(0 0 100% 0)` (hidden from bottom). Animate to `inset(0 0 0 0)` when the element enters the viewport. Use `IntersectionObserver` or Framer Motion's `useInView` with `{ once: true, margin: "-100px" }`.

### Comparison sliders

Overlay two images. Clip the top one with `clip-path: inset(0 50% 0 0)`. Adjust the right inset value based on drag position. No extra DOM elements needed, fully hardware-accelerated.

---

## Gesture and Drag Interactions

### Momentum-based dismissal

Don't require dragging past a threshold. Calculate velocity: `Math.abs(dragDistance) / elapsedTime`. If velocity exceeds ~0.11, dismiss regardless of distance. A quick flick should be enough.

```js
const timeTaken = new Date().getTime() - dragStartTime.current.getTime();
const velocity = Math.abs(swipeAmount) / timeTaken;

if (Math.abs(swipeAmount) >= SWIPE_THRESHOLD || velocity > 0.11) {
  dismiss();
}
```

### Damping at boundaries

When a user drags past the natural boundary (e.g., dragging a drawer up when already at top), apply damping. The more they drag, the less the element moves. Things in real life don't suddenly stop; they slow down first.

### Pointer capture for drag

Once dragging starts, set the element to capture all pointer events. This ensures dragging continues even if the pointer leaves the element bounds.

### Multi-touch protection

Ignore additional touch points after the initial drag begins. Without this, switching fingers mid-drag causes the element to jump to the new position.

```js
function onPress() {
  if (isDragging) return;
  // Start drag...
}
```

### Friction instead of hard stops

Instead of preventing upward drag entirely, allow it with increasing friction. It feels more natural than hitting an invisible wall.

---

## Performance Rules

### Only animate transform and opacity

These properties skip layout and paint, running on the GPU. Animating `padding`, `margin`, `height`, or `width` triggers all three rendering steps.

### CSS variables are inheritable

Changing a CSS variable on a parent recalculates styles for all children. In a drawer with many items, updating `--swipe-amount` on the container causes expensive style recalculation. Update `transform` directly on the element instead.

```js
// Bad: triggers recalc on all children
element.style.setProperty('--swipe-amount', `${distance}px`);

// Good: only affects this element
element.style.transform = `translateY(${distance}px)`;
```

### Framer Motion hardware acceleration caveat

Framer Motion's shorthand properties (`x`, `y`, `scale`) are NOT hardware-accelerated. They use `requestAnimationFrame` on the main thread. For hardware acceleration, use the full `transform` string:

```jsx
// NOT hardware accelerated (convenient but drops frames under load)
<motion.div animate={{ x: 100 }} />

// Hardware accelerated (stays smooth even when main thread is busy)
<motion.div animate={{ transform: "translateX(100px)" }} />
```

This matters when the browser is simultaneously loading content, running scripts, or painting.

### CSS animations beat JS under load

CSS animations run off the main thread. When the browser is busy loading a new page, Framer Motion animations (using `requestAnimationFrame`) drop frames. CSS animations remain smooth. Use CSS for predetermined animations; JS for dynamic, interruptible ones.

### Use WAAPI for programmatic CSS animations

The Web Animations API gives you JavaScript control with CSS performance. Hardware-accelerated, interruptible, and no library needed.

```js
element.animate([{ clipPath: 'inset(0 0 100% 0)' }, { clipPath: 'inset(0 0 0 0)' }], {
  duration: 1000,
  fill: 'forwards',
  easing: 'cubic-bezier(0.77, 0, 0.175, 1)',
});
```

---

## Stagger Animations

When multiple elements enter together, stagger their appearance. Each element animates in with a small delay after the previous one. This creates a cascading effect that feels more natural than everything appearing at once.

```css
.item {
  opacity: 0;
  transform: translateY(8px);
  animation: fadeIn 300ms ease-out forwards;
}

.item:nth-child(1) {
  animation-delay: 0ms;
}
.item:nth-child(2) {
  animation-delay: 50ms;
}
.item:nth-child(3) {
  animation-delay: 100ms;
}
.item:nth-child(4) {
  animation-delay: 150ms;
}

@keyframes fadeIn {
  to {
    opacity: 1;
    transform: translateY(0);
  }
}
```

Keep stagger delays short (30-50ms between items). Long delays make the interface feel slow. Stagger is decorative — never block interaction while stagger animations are playing.

**Incorrect (excessive stagger):**

```tsx
transition={{ staggerChildren: 0.15 }}
```

**Correct (reasonable stagger):**

```tsx
transition={{ staggerChildren: 0.03 }}
```

---

## Debugging

### Slow motion testing

Play animations at reduced speed to spot issues invisible at full speed. Temporarily increase duration to 2-5x normal, or use browser DevTools animation inspector to slow playback.

Things to look for in slow motion:

- Do colors transition smoothly, or do you see two distinct states overlapping?
- Does the easing feel right, or does it start/stop abruptly?
- Is the transform-origin correct, or does the element scale from the wrong point?
- Are multiple animated properties (opacity, transform, color) in sync?

### Frame-by-frame inspection

Step through animations frame by frame in Chrome DevTools (Animations panel). This reveals timing issues between coordinated properties that you cannot see at full speed.

### Test on real devices

For touch interactions (drawers, swipe gestures), test on physical devices. Connect your phone via USB, visit your local dev server by IP address, and use Safari's remote devtools. The Xcode Simulator is an alternative but real hardware is better for gesture testing.

### Review with fresh eyes

Review animations with fresh eyes the next day. You notice imperfections the next day that you missed during development.

---

## Review Checklist

| Issue | Fix |
| --- | --- |
| `transition: all` | Specify exact properties: `transition: transform 200ms ease-out` |
| `scale(0)` entry animation | Start from `scale(0.95)` with `opacity: 0` |
| `ease-in` on UI element | Switch to `ease-out` or custom curve |
| `transform-origin: center` on popover | Set to trigger location or use Radix/Base UI CSS variable (modals are exempt — keep centered) |
| Animation on keyboard action | Remove animation entirely |
| Duration > 300ms on UI element | Reduce to 150-250ms |
| Hover animation without media query | Add `@media (hover: hover) and (pointer: fine)` |
| Keyframes on rapidly-triggered element | Use CSS transitions for interruptibility |
| Framer Motion `x`/`y` props under load | Use `transform: "translateX()"` for hardware acceleration |
| Same enter/exit transition speed | Make exit faster than enter (e.g., enter 2s, exit 200ms) |
| Elements all appear at once | Add stagger delay (30-50ms between items) |
| Linear easing on motion | Switch to ease-out or spring |
| Excessive squash/stretch (< 0.95 or > 1.05) | Keep scale within 0.95-1.05 range |
| Missing active state on button | Add `transform: scale(0.97)` on `:active` |
| Inconsistent timing on similar elements | Use identical timing values |
| No AnimatePresence wrapper on conditional motion | Wrap in AnimatePresence |
| Missing exit prop inside AnimatePresence | Add exit prop matching initial |
| Measure and animate same container element | Use two-div pattern (outer animated, inner measured) |
| Competing simultaneous animations | Ensure single focal point |
| No z-index on animated overlay/tooltip | Add explicit z-index |
| Animated high-frequency interaction | Remove animation entirely |
| Context menu with entrance animation | Remove entrance, keep exit only |
