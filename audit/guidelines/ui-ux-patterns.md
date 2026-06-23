# UI/UX Pattern Guidelines

## Laws of UX

Reference: [Laws of UX](https://lawsofux.com/) by Jon Yablonski

| # | Law | Actionable Rule | What to Check in Code |
|---|-----|----------------|----------------------|
| 1 | Fitts's Law | Interactive targets must be at least 32px; use padding to reach it | `width`/`height` < 32px on buttons/icons; missing `padding` on small interactive elements |
| 2 | Fitts's Law (hit area) | Expand clickable area beyond visible bounds with pseudo-elements or invisible padding | Links/icons without `::before`/`::after` hit-area expansion; `inset: -8px -12px` pattern missing |
| 3 | Hick's Law | Limit visible choices; use progressive disclosure (`<details>`, collapsibles) | Flat lists rendering `allOptions.map()`; no "Advanced"/"More" grouping for 7+ items |
| 4 | Miller's Law | Chunk data into groups of 5--9 items; format long strings with spaces | Raw unformatted numbers/IDs; lists > 9 items without visual grouping |
| 5 | Doherty Threshold | Respond within 400ms; use optimistic UI for anything slower | `await` without prior `setState(optimisticData)`; no loading state before async call |
| 6 | Perceived Performance | Show skeletons or progress indicators during loading -- never blank screens | `if (isLoading) return null`; missing `<Skeleton />` or spinner fallback |
| 7 | Postel's Law | Accept messy input, output clean data; parse flexibly, validate generously | Rigid `pattern` attributes; single-format `placeholder` hints; no `parseFlexible*` helpers |
| 8 | Progressive Disclosure | Show primary controls first; reveal advanced options on demand | All tool tiers rendered simultaneously; no `useState` toggle for secondary UI |
| 9 | Jakob's Law | Use standard, recognizable UI patterns (labeled nav, conventional icons) | Custom icon-only navigation without labels; non-standard interaction patterns |
| 10 | Aesthetic-Usability | Visual polish increases perceived usability; use design tokens consistently | Raw `border: 1px solid black`; hardcoded colors instead of `var(--*)` tokens; missing `border-radius`, `box-shadow` |
| 11 | Law of Proximity | Tighter spacing within groups, larger spacing between groups | Uniform `margin-bottom` on label + input + hint; no spacing hierarchy (4px/2px vs 24px) |
| 12 | Law of Similarity | Same-function elements must look identical; use shared CSS classes | Duplicate button styles (`.save-button` vs `.submit-button`) with different visuals for same role |
| 13 | Law of Common Region | Wrap related controls in bounded sections (`<section>`, cards) | Flat `<div>` with mixed unrelated toggles/inputs; no `<section>` or card grouping |
| 14 | Von Restorff Effect | Make the primary/destructive action visually distinct from secondary actions | All buttons sharing one `.button` class; no `.button-danger` or `.button-primary` variant |
| 15 | Serial Position Effect | Place key items first or last in sequences (nav, lists) | Important links buried mid-nav; CTAs in the middle of button groups |
| 16 | Peak-End Rule | End flows with clear success states, not silent redirects | `router.push("/")` immediately after submit; no `<SuccessScreen />` or confirmation |
| 17 | Tesler's Law | Move complexity to the system; use smart components (DatePicker over raw input) | `placeholder="YYYY-MM-DDTHH:mm:ss.sssZ"`; complex format requirements on user-facing inputs |
| 18 | Goal-Gradient Effect | Show progress toward completion (progress bars, step counters) | Multi-step flows without `<ProgressBar />`; no "Step X of Y" indicator |
| 19 | Zeigarnik Effect | Show incomplete state to drive completion (profile %, onboarding banners) | Dashboard loads without checking `profile.isComplete`; no completion percentage display |
| 20 | Law of Pragnanz | Reduce visual noise; simplify to the clearest possible form | Multiple borders + gradients + outlines on one element; competing visual treatments |
| 21 | Pareto Principle | Make the critical 20% of features prominent; tuck the rest in overflow menus | `allFeatures.map()` rendered equally; no `<MoreMenu />` for secondary actions |
| 22 | Cognitive Load | Remove extraneous elements; only show what helps task completion | Dialogs with redundant warnings, oversized icons, "Learn More" on destructive confirms |
| 23 | Law of Uniform Connectedness | Visually connect related elements with lines, color, or shared containers | Step indicators without connector lines; related items with no visual link |

### Anti-Patterns Summary

- Touch target < 32px (mobile: < 44px per Apple HIG)
- No immediate feedback on user action (> 400ms gap)
- Blank screen during loading instead of skeleton/spinner
- All options dumped at once without progressive disclosure
- Uniform spacing everywhere (no visual grouping hierarchy)
- Same-function buttons styled differently
- Custom navigation with no standard labels
- Multi-step flow with no progress indicator
- Silent redirect after form submission (no success state)
- Hardcoded colors/sizes instead of design tokens

---

## Predictive Prefetching

Reference: [ForesightJS](https://foresightjs.com), [Next.js Prefetching Docs](https://nextjs.org/docs/app/guides/prefetching)

### Rules

- **Trajectory over hover:** Use cursor trajectory prediction (`useForesight`) instead of `onMouseEnter` -- reclaims 100--200ms
- **Intent over viewport:** Set `prefetch={false}` on `<Link>`; prefetch only on predicted intent, not on visibility
- **Expand prediction area:** Use `hitSlop: 20` (minimum) to trigger predictions before cursor reaches the element
- **Touch fallback:** `useForesight` handles touch gracefully; never rely on `onMouseMove` alone
- **Keyboard awareness:** Prefetch on focus/tab proximity, not just cursor movement
- **Use selectively:** Apply to data-heavy dashboards, multi-page apps, e-commerce -- skip for static sites or fully preloaded SPAs

### What to Check in Code

- `onMouseEnter={() => prefetch()}` -- replace with `useForesight` callback
- `prefetch={true}` on all `<Link>` components -- wasteful viewport-based prefetching
- `hitSlop: 0` or missing `hitSlop` -- prediction triggers too late
- `onMouseMove` without touch fallback -- breaks on mobile
- Prefetching on static/instant-nav sites -- unnecessary bandwidth usage

### Pattern: ForesightJS Integration

```tsx
const { elementRef } = useForesight({
  callback: () => router.prefetch("/target"),
  hitSlop: 20,
  name: "target-link",
});

<Link ref={elementRef} href="/target">Target</Link>
```

### Good vs Bad Use Cases

- **Use:** Data-heavy dashboards, multi-page apps with slow APIs, e-commerce product pages
- **Skip:** Static sites with instant navigation, SPAs with all data preloaded

## CMS / Settings Field with View Fallback

An editable CMS/settings field that also has a default has **three consistency points** that must all carry the same text:

1. **Seed value** — what the seeder writes on first deploy.
2. **View fallback** — what renders when the field is empty.
3. **Form default / placeholder** — what the admin sees in the editor.

If these drift, the admin edits one value but the visitor sees another, or an emptied field renders something the admin never chose.

**The empty-string trap (high-recurrence bug):** `??` only catches `null`, NOT an empty string. When an admin clears a field, most form/DB layers store `""`, which sails straight through `??` and renders an empty heading.

```blade
{{-- BAD — admin clears the field, visitor sees a blank <h1> --}}
<h1>{{ $page['hero_title'] ?? 'Standardtitel' }}</h1>

{{-- GOOD — filled() treats '' and null alike --}}
<h1>{{ filled($page['hero_title'] ?? null) ? $page['hero_title'] : 'Standardtitel' }}</h1>
```

In plain PHP/JS use a truthiness check (`$x !== '' && $x !== null`, or `value || 'default'`), not nullish-coalescing, for any field a human can empty.

**Audit signal:** a view fallback via `??` on a CMS/settings/user-editable field → flag and switch to `filled()`/truthiness. Then verify the seed, fallback, and form-default texts match. Pairs with the seeder stale-key rule in architecture.md XVI.
