# Dimension: Animation & Motion Design

## Look for

Animations, transitions, motion design: missing animations (page transitions, modals, dropdowns,
lists, skeletons), excessive animations, CSS/Tailwind transitions, reduced motion, audio feedback.
Read `guidelines/ui-animation.md` (decision framework, timing, easing, reduced motion) and
`guidelines/ui-audio.md` (projects with audio feedback) in full.

- **Reduced-motion catch-all:** check for a global catch-all (global CSS/`app.css`, Tailwind
  preset) before flagging a single element for missing its own `@media` rule.
- **Tailwind transition defaults:** default duration is 150ms; "missing duration" is not a finding
  unless an explicitly deviating duration is actually needed.
- **New dependencies:** check the animation library's own defaults (e.g. `respectMotionPreference`)
  before attributing misbehavior to it.

**Defect class calibrated against a real finding (2026-08-27 audit):** a drag/gesture settle-back
or reset animation (e.g. a panel snapping back after an incomplete swipe) fired unconditionally in
its own reset closure, ignoring an existing `prefers-reduced-motion`/Reduce Motion setting even
though a global catch-all exists for other animations in the same file.

Skip when no frontend files are in scope.

## Severity

No `Critical`. Missing `prefers-reduced-motion` support with no catch-all, or an animation that
actively breaks interaction (blocks input, causes motion sickness triggers) is `Important`;
everything else `Minor`.

Examples (2026-08-27 audit): `Important` — a drag/gesture settle-back animation fired unconditionally
in its own reset closure, ignoring an existing Reduce Motion setting despite a global catch-all
existing for other animations in the same file (the defect class above). `Minor` — a phase-crossfade
timing tweak on the photo-import sheet was a polish adjustment with no interaction breakage.

## Output

Reply with the specialist schema: `findings[{id, severity, confidence, files, issue, impact}]`
plus `coverage`. Every ID is prefixed `animation-`. Set `coverage` to `COVERAGE: full` or
`COVERAGE: partial | not read: {file1}, {file2}`.
