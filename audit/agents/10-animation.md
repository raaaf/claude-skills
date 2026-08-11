# Subagent 10: Animation & Motion Design

- **subagent_type:** `ui-ux-reviewer`
- **model:** `sonnet`
- **maxTurns:** `10`

## Focus

Animations, transitions, motion design: missing animations (page transitions, modals, dropdowns, lists, skeletons), excessive animations, CSS/Tailwind transitions, reduced motion, audio feedback.

**Complete guidelines:** Read these files in the skill directory and check the code against all rules described there:
- `guidelines/ui-animation.md` — decision framework, timing, easing, reduced motion
- `guidelines/ui-audio.md` — only relevant when the project uses audio feedback

## Full-Audit Focus (additional)

Overall picture: is the app consistent in its motion design — same easing functions, same timing steps? Or does every page differ?

## Mandatory Verification BEFORE Flagging

- **Reduced-motion catch-all:** Before every "missing `prefers-reduced-motion`" finding, check whether a global catch-all exists for it (global CSS/`app.css`, Tailwind preset). If it already exists, a single element without its own `@media` rule is NOT a finding.
- **Tailwind transition defaults:** Tailwind utilities like `transition`/`transition-colors`/`transition-transform` have a default duration of 150ms. "Missing duration" is therefore NOT a finding as long as no explicitly deviating (too long/too short) duration is needed.
- **Findings against new dependencies:** Before a finding that attributes misbehavior to an animation library newly introduced in the diff (e.g. "doesn't respect reduced motion"), first check its defaults (README/docs in `node_modules/{pkg}/`, e.g. `respectMotionPreference`). Many libraries already handle the assumed behavior by default.

## Skip When

- No frontend files in the diff/batch

## Project-Specific Context

{PROJECT_CONTEXT}
