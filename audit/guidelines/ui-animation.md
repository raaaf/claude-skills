---
applies_to: \.(css|scss|sass|less|styl)$|\.(jsx|tsx|vue|svelte|astro|html)$|\.blade\.php$|\.(swift|kt|dart)$|\.(js|ts)$
priority: recommended
---
# UI Animation Checklist

## 1. Should This Animate?

| Frequency | Decision |
|---|---|
| 100+/day (keyboard shortcuts, cmd palette) | No animation. Ever. |
| Tens/day (hover, list nav) | Remove or drastically reduce |
| Occasional (modals, drawers, toasts) | Standard animation |
| Rare/first-time (onboarding, celebrations) | Can add delight |

- **Never animate keyboard-initiated actions** — feels slow and disconnected
- **No animation for high-frequency interactions** — typing feedback, fast toggles = 0ms
- **Context menus**: no entrance animation, exit only

## 2. Animation Purpose

Every animation must answer "why does this animate?" Valid reasons:
- Spatial consistency (toast enters/exits same direction)
- State indication (morphing feedback button)
- Explanation (marketing feature demo)
- Feedback (button press confirmation)
- Preventing jarring changes (appear/disappear without transition feels broken)

If the answer is "looks cool" and the user sees it often — don't animate.

## 3. Easing Selection

| Motion Type | Use | Easing Direction |
|---|---|---|
| User-driven (drag, flick, gesture) | Spring | — |
| System-driven (state change, feedback) | Easing | See below |
| Time representation (progress, loading) | Linear | — |
| High-frequency (typing, fast toggles) | None | — |

| Action | Easing |
|---|---|
| Entering screen | `ease-out` (starts fast, feels responsive) |
| Exiting screen | `ease-in` (builds momentum) |
| Moving/morphing on screen | `ease-in-out` |
| Hover / color change | `ease` |
| Constant motion (marquee, progress) | `linear` |
| View/page transitions | `ease-in-out` |
| Default | `ease-out` |

**Use custom easing curves** — built-in CSS easings are too weak:

```css
--ease-out: cubic-bezier(0.23, 1, 0.32, 1);
--ease-in-out: cubic-bezier(0.77, 0, 0.175, 1);
--ease-drawer: cubic-bezier(0.32, 0.72, 0, 1); /* iOS-like */
```

Resources: [easing.dev](https://easing.dev/) / [easings.co](https://easings.co/)

**Never use `ease-in` for entrance animations** — starts slow, feels sluggish.

## 4. Duration Reference

| Element | Duration |
|---|---|
| Button press / hover feedback | 100-180ms |
| Tooltips, small popovers | 125-200ms |
| Dropdowns, selects | 150-250ms |
| Small state changes (toggles) | 180-260ms |
| Modals, drawers | 200-500ms |
| Marketing/explanatory | Can be longer |

**Rule: UI animations stay under 300ms.** If it feels slow, shorten duration first — don't adjust the curve.

### Quick Reference

| Interaction | Timing | Type |
|---|---|---|
| Drag release | Spring | `stiffness: 500, damping: 30` |
| Button press | 150ms | `ease` |
| Modal enter | 200ms | `ease-out` |
| Modal exit | 150ms | `ease-in` |
| Page transition | 250ms | `ease-in-out` |
| Progress bar | varies | `linear` |
| Typing feedback | 0ms | none |

## 5. Spring Animations

### When to Use Springs
- Drag interactions with momentum
- Gestures that can be interrupted mid-animation
- Decorative mouse-tracking interactions
- Any motion where overshoot-and-settle is desired

### Configuration

```js
// Apple-style (recommended)
{ type: "spring", duration: 0.5, bounce: 0.2 }

// Traditional physics (more control)
{ type: "spring", mass: 1, stiffness: 100, damping: 10 }
```

- Keep bounce subtle: 0.1-0.3
- Avoid bounce in most UI contexts; use for drag-to-dismiss and playful interactions
- Springs maintain velocity when interrupted — CSS keyframes restart from zero
- Use `useSpring` from Motion for mouse-tracking (not raw values)

### Spring Rules
- Gesture-driven motion (drag, flick, swipe) **must** use springs
- Interruptible motion **must** use springs
- Preserve input velocity: pass `velocity: info.velocity.x` to spring
- Balanced params: `stiffness: 500, damping: 30` — avoid `stiffness: 1000, damping: 5` (too bouncy)
- System-initiated state changes use easing, **not** springs

### Apple parametrization (damping ratio + response)

Think in two designer parameters instead of the physics triplet: **damping ratio** (1.0 = critically damped, no overshoot; < 1.0 = bounce) and **response** (seconds to approach target; lower = snappier).

- Default UI: damping `1.0`, response `0.3-0.4` — no overshoot
- **Bounce only when the gesture itself carried momentum** (flick, throw, drag release: damping ~`0.8`). Overshoot on a menu that just faded in is a finding; overshoot on a card the user flicked is correct
- Apple's shipped values: move/reposition `1.0/0.4`, rotation `0.8/0.4`, drawer/sheet `0.8/0.3`
- Motion's `bounce` + `duration` API maps to this: `{ type: "spring", bounce: 0, duration: 0.4 }` = critically damped

## 6. Exit Animations (AnimatePresence)

- Conditional motion elements **must** be wrapped in `<AnimatePresence>`
- **Must** have `exit` prop inside AnimatePresence
- Exit should mirror initial for symmetry (e.g., `initial={{ opacity: 0, y: 20 }}` -> `exit={{ opacity: 0, y: 20 }}`)
- Dynamic lists: use unique stable keys (`item.id`), never array index
- `useIsPresent` must be called from a **child** of AnimatePresence, not the parent
- Call `safeToRemove` after async cleanup when using `usePresence`
- Disable interactions on exiting elements: `disabled={!isPresent}`
- Mode `"wait"` nearly doubles duration — halve your timing values
- Avoid mode `"sync"` — use `"popLayout"` for list animations
- Nested AnimatePresence: use `propagate` prop on both levels
- Parent exit duration must be >= child exit duration
- `initial={false}` on AnimatePresence for default-state elements (icon swaps, toggles, tabs): no enter animation on page load, only on state changes. Do NOT apply where the component relies on `initial` for a deliberate first-run entrance (staggered hero) — that would skip the whole entrance

## 7. Container Animation

- **Two-div pattern**: outer `<motion.div>` animates, inner `<div ref={ref}>` measures — never measure and animate the same element
- Guard zero on mount: `bounds.width > 0 ? bounds.width : "auto"`
- Use `ResizeObserver` for measurement (not `getBoundingClientRect` on every render)
- Set `overflow: hidden` on the animated outer container
- Use callback ref (`useState` + `useCallback`), not `useRef`, for measurement hooks
- Add small delay for natural feel: `transition={{ duration: 0.2, delay: 0.05 }}`
- Reserve animated bounds for meaningful size changes (accordions, loading buttons, expandable sections)

## 8. Component Patterns

| Pattern | Rule |
|---|---|
| Button press feedback | `transform: scale(0.97)` on `:active`, 160ms ease-out. Scale range: 0.95-0.98 |
| Never scale from 0 | Start from `scale(0.9)` or higher + opacity |
| Popover origin | Scale from trigger, not center. Use `var(--radix-popover-content-transform-origin)`. Exception: modals keep `center` |
| Tooltip timing | Delay first show; skip delay + animation on subsequent hovers (`data-instant` with `transition-duration: 0ms`) |
| Interruptible UI | Use CSS transitions, not keyframes — transitions retarget mid-animation |
| Blur for crossfade | `filter: blur(2px)` during imperfect state transitions. Keep blur < 20px (Safari perf) |
| CSS entry animation | Use `@starting-style` (modern CSS); fallback: `data-mounted` attribute pattern |
| Asymmetric timing | Deliberate actions slow (hold-to-delete: 2s linear), release always fast (200ms ease-out) |
| Stagger animations | 30-50ms between items. Never block interaction during stagger. |
| Cohesion | Match motion personality to component (playful = bouncier, dashboard = crisp) |

## 9. CSS Transform Rules

- `translateY(100%)` = element's own height — prefer percentages over hardcoded pixels
- `scale()` scales children too — intentional for button press feedback
- Set `transform-origin` to match trigger location for origin-aware interactions
- `clip-path: inset()` is powerful for reveals, tabs, hold-to-delete, comparison sliders

## 10. Gesture & Drag

- **Respond on pointer-down, not release**: press feedback fires the instant the pointer goes down; waiting for `click`/touch-up feels dead. During a drag, the UI tracks the pointer 1:1 the whole way — never animate only at gesture end
- **Respect the grab offset**: the element follows from where it was grabbed; snapping its center to the pointer breaks the illusion
- **Momentum dismissal**: calculate velocity (`distance / time`), dismiss if > ~0.11 regardless of distance
- **Momentum projection**: pick the snap target from where the gesture is *going*, not from the release position. Apple's exponential-decay projection (not the textbook `v²/2a`):
  ```js
  // decelerationRate 0.998 = normal scroll feel, 0.99 = snappier
  const project = (v, rate = 0.998) => (v / 1000) * rate / (1 - rate);
  const target = nearestSnapPoint(current + project(releaseVelocity));
  ```
- **Velocity handoff**: the spring after release starts at the finger's exact velocity — no seam between drag and animation. APIs wanting relative velocity: `gestureVelocity / (target - current)`; Motion takes raw px/s via `velocity`
- **Interrupt from the presentation value**: on retarget, read the live on-screen transform and start there — starting from the logical target value causes a visible jump. Blend velocity through the retarget instead of hard-cutting it ("brick wall")
- **Decompose 2D motion into separate X and Y springs**: a single spring on the 2D distance desyncs when the axes have different velocities
- **Damping at boundaries / rubber-band**: reduce movement the further past the boundary the user drags:
  ```js
  const rubberband = (over, dim, c = 0.55) => (over * dim * c) / (dim + c * Math.abs(over));
  ```
- **Pointer capture**: set on drag start so dragging continues outside element bounds
- **Multi-touch protection**: ignore additional touch points after drag begins
- **Friction over hard stops**: allow over-drag with increasing resistance instead of invisible walls

## 11. Performance

| Rule | Detail |
|---|---|
| Only animate `transform` and `opacity` | These skip layout and paint (GPU-composited) |
| Avoid CSS variable animation on parents | Changing `--var` on parent recalculates all children. Set `transform` directly. |
| Framer Motion `x`/`y`/`scale` are NOT GPU-accelerated | Use `transform: "translateX(100px)"` for hardware acceleration |
| CSS animations beat JS under load | CSS runs off main thread; Framer Motion uses rAF (drops frames when busy) |
| Use WAAPI for programmatic + performant | `element.animate([...], { duration, fill, easing })` — hardware-accelerated, interruptible, no library |
| `will-change` only for compositor props | `transform`, `opacity`, `filter`, `clip-path` — properties the GPU can composite. `will-change: all` or on layout/paint props is a finding |
| `will-change` only around active animation | Not preemptively on every animated element (each promoted layer costs memory). Add when first-frame stutter is observed; Safari benefits most |
| Batch layout reads before writes | Interleaving `getBoundingClientRect` and style writes in one frame = layout thrashing. Measure once, then animate via transform (FLIP pattern) |
| No scroll listeners driving animation | Prefer Scroll/View Timelines (`animation-timeline: view()`/`scroll()`); fall back to IntersectionObserver. Polling `scrollY` per frame is a finding |
| Pause off-screen loops | Looping animations (marquee, pulse, spinner in hidden tab) must pause when not visible — IntersectionObserver or `animation-play-state` |
| No rAF loop without stop condition | Every `requestAnimationFrame` loop needs a documented exit (flag or cancellation), otherwise it burns CPU forever |
| Animated blur <= 8px, never continuous | Blur transitions stay small and one-shot. Continuous blur animation or animated blur on large surfaces is a finding (crossfade-masking blur of 2px from §8 is fine) |

## 12. Reduced Motion

- Wrap hover animations in `@media (hover: hover) and (pointer: fine)`

**Named check — new animated/scrollable component gates on reduced motion:** any NEW component the diff introduces that animates on its own (auto-playing, looping, parallax, marquee/auto-scroll, decorative motion) must gate on the platform's reduced-motion signal before shipping — `prefers-reduced-motion` (web), `accessibilityReduceMotion` / `UIAccessibility.isReduceMotionEnabled` (iOS), `Settings.Global.ANIMATOR_DURATION_SCALE` (Android). Missing gate on a new self-animating component → Important [Animation]. Two audits in a row shipped one without it. The global-catch-all exception below still applies on web; native platforms have no catch-all, so there the per-component check is always required.

**Before flagging "missing `prefers-reduced-motion`":** check whether a global catch-all already exists (e.g. a `@media (prefers-reduced-motion: reduce) { * { animation-duration: 0.01ms !important; ... } }` block in the base/app CSS). If it does, an individual animated element without its own reduced-motion rule is already covered — not a finding.

**Before flagging "missing duration" on a Tailwind `transition*` utility:** Tailwind's `transition`, `transition-colors`, `transition-transform`, etc. ship a default duration of 150ms. A bare utility class without an explicit `duration-*` is not a finding unless the default 150ms is demonstrably wrong for that interaction.

## 13. Review Checklist

| Issue | Fix |
|---|---|
| `transition: all` | Specify exact properties: `transition: transform 200ms ease-out` |
| `scale(0)` entry | Start from `scale(0.95)` + `opacity: 0` |
| `ease-in` on UI entrance | Switch to `ease-out` or custom curve |
| `transform-origin: center` on popover | Set to trigger location (modals exempt) |
| Animation on keyboard action | Remove animation entirely |
| Duration > 300ms on UI element | Reduce to 150-250ms |
| Hover without media query | Add `@media (hover: hover) and (pointer: fine)` |
| Keyframes on rapidly-triggered element | Use CSS transitions for interruptibility |
| Framer Motion `x`/`y` under load | Use `transform: "translateX()"` for GPU |
| Same enter/exit speed | Make exit faster than enter |
| Elements all appear at once | Add stagger (30-50ms between items) |
| Linear easing on motion | Switch to ease-out or spring |
| Excessive scale (< 0.95 or > 1.05) | Keep within 0.95-1.05 |
| Missing `:active` on button | Add `transform: scale(0.97)` |
| Inconsistent timing on similar elements | Use identical values |
| No AnimatePresence on conditional motion | Wrap in AnimatePresence |
| Missing exit prop | Add exit matching initial |
| Measure + animate same element | Two-div pattern |
| Competing simultaneous animations | Single focal point only |
| No z-index on animated overlay/tooltip | Add explicit z-index |
| Animated high-frequency interaction | Remove animation entirely |
| Context menu with entrance animation | Remove entrance, keep exit only |
| No dimmed backdrop on modal/dialog | Add `background: var(--black-a6)` overlay |
| Linear ramp for decay (audio/visual) | Use exponential ramp |
| `will-change: all` or on layout props | Restrict to transform/opacity/filter/clip-path, only around active animation |
| Scroll listener drives animation | Scroll/View Timelines or IntersectionObserver |
| Looping animation runs off-screen | Pause via IntersectionObserver / `animation-play-state` |
| Layout read+write interleaved per frame | Batch reads, then writes (FLIP) |

## 14. Debugging

- **Slow motion**: temporarily 2-5x duration to spot issues. Check: smooth color transitions, correct easing feel, correct transform-origin, property sync.
- **Frame-by-frame**: Chrome DevTools Animations panel
- **Real devices**: test touch/gesture interactions on physical hardware via USB + Safari remote devtools
- **Fresh eyes**: review animations the next day

## 15. Common Implementation Bugs (2026)

These are the failure modes that ship most often and break silently. All three are easy to grep for.

| Bug | Symptom | Fix |
|---|---|---|
| **Close-state class not cleaned up** | First open animates correctly. Subsequent opens skip or stutter because `.is-closing` / `[data-state="closing"]` was never removed after the close completed. | Listen for `animationend`/`transitionend` and remove the close-state class explicitly. Or use `@starting-style` so no state attribute is needed. |
| **No reflow between class toggles** | Re-triggering the same animation does nothing — browser collapses the back-to-back state changes. | Insert `void el.offsetHeight;` between `el.classList.remove('on')` and `el.classList.add('on')`. Or use `requestAnimationFrame` between toggles. Or restart via `el.getAnimations().forEach(a => { a.cancel(); a.play(); })`. |
| **`transition: all` with dynamic properties** | Transitioning unintended properties (background, padding, border-radius) when only `transform` was supposed to animate, causing jank and visual bugs. | Specify exact properties: `transition: transform 200ms ease-out, opacity 200ms ease-out`. Already in §13 — but this is the single most common animation bug, worth re-stating. |

**Additional gotchas:**
- **Stripping `transform-origin` on reopen** — origin-aware popovers lose their origin when the close-state class is wiped along with origin variables. Keep origin separate from state classes.
- **Animating containers instead of inner pieces** — outer container resizes are jarring. Animate inner content with the two-div pattern (§7).
- **Hardcoded `stroke-dasharray` on SVG path-draw** — breaks if the path changes. Calculate length via `path.getTotalLength()` at mount, set via custom property.
- **Inline `transition-timing-function`** when CSS controls the timing — overrides theme curves silently. Set in CSS, not inline style.

**Pattern reference for building (not auditing):** Concrete production-ready snippets for 18 named patterns (card resize, modal, tooltip, tabs sliding, success check, error shake, skeleton reveal, etc.) live at [transitions.dev](https://transitions.dev/) with a semantic CSS variable system. Useful as a vocabulary when an audit finding says "the modal pattern is wrong" — refer to the transitions.dev recipe to clarify what the correct pattern looks like.
