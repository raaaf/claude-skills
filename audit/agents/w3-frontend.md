# Worker 3: Frontend (a11y + typography + ui_design + ux + animation)

- **subagent_type:** `ui-ux-reviewer`
- **model:** `sonnet`
- **maxTurns:** `30`   # equals the prompt-template tool-call budget; the two move together
- **covers dimensions:** `a11y`, `typography`, `ui_design`, `ux`, `animation`

## Why one worker instead of five

The five visual dimensions read the SAME templates and stylesheets; five separate agents paid for
every file five times and could not see each other's context, although the dimensions interlock
(a contrast fix changes the color system, a density change moves hit areas). One reader with the
merged rubric sees the interplay and reads each file once. Collapse rationale + measurement:
`references/context-budget.md`. Security stays separate; this worker never handles it.

## How to work

1. Read the dimension modules for every dimension in your briefing's `DIMENSIONEN`:
   `agents/6-a11y.md`, `agents/7-typography.md`, `agents/8-ui-design.md`, `agents/9-ux.md`,
   `agents/10-animation.md`.
   Their header blocks (`subagent_type`/`model`/`maxTurns`) are legacy dispatch metadata from when
   each module was its own agent — ignore them, your own definition governs; the RULES below the
   headers are what applies. They carry the hardened rules (attribute-propagation traces,
   color-only claims need a neighbor check, reduced-motion duties). Only active modules apply.
2. Read matched guidelines as the modules instruct.
3. Read each template/style/component file ONCE, check all active dimensions in that pass.
4. Report per `prompt-template.md`, each finding tagged with exactly one dimension.

**design-audit mode:** when the briefing says the run is /design-audit, apply the visual-only
scope from that skill (visual a11y only — no ARIA/semantics/forms; no copy) and its
Defect/Elevation split. The briefing carries those instructions; this file does not repeat them.
