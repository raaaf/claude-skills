# Dispatch Templates

Bash logic and prompt templates for Phase 2.5 (codebase context), Phase 3 (challenging), Phase 3.5 (evaluation).

## Contents
- Phase 2.5 — Gather codebase context (framework detection, source dirs)
- Phase 3 — Dispatch plan challengers (5 parallel reviewers)
- Phase 3.5 — Parse evaluation (consensus score, change proposals)

## Phase 2.5: Gather Codebase Context

```bash
PROJECT_ROOT=$(git rev-parse --show-toplevel 2>/dev/null || echo ".")

# Detect framework and source dirs. SOURCE_DIRS_ARR is a bash array built
# directly (never by re-splitting a joined string), so a space inside
# PROJECT_ROOT — this repo's own root, "Local Sites/claude-skills", is one —
# can't fracture a single directory into two find arguments. SOURCE_DIRS
# keeps the same space-joined string for anything that still reads it as text.
if [ -f "$PROJECT_ROOT/artisan" ]; then
  FRAMEWORK="laravel"
  SOURCE_DIRS_ARR=("$PROJECT_ROOT/app/" "$PROJECT_ROOT/resources/" "$PROJECT_ROOT/database/" "$PROJECT_ROOT/routes/" "$PROJECT_ROOT/config/")
elif [ -f "$PROJECT_ROOT/package.json" ] && grep -q '"next"' "$PROJECT_ROOT/package.json" 2>/dev/null; then
  FRAMEWORK="nextjs"
  SOURCE_DIRS_ARR=("$PROJECT_ROOT/src/" "$PROJECT_ROOT/app/" "$PROJECT_ROOT/pages/" "$PROJECT_ROOT/components/" "$PROJECT_ROOT/lib/")
elif [ -f "$PROJECT_ROOT/nuxt.config.ts" ] || [ -f "$PROJECT_ROOT/nuxt.config.js" ]; then
  FRAMEWORK="nuxt"
  SOURCE_DIRS_ARR=("$PROJECT_ROOT/components/" "$PROJECT_ROOT/composables/" "$PROJECT_ROOT/pages/" "$PROJECT_ROOT/layouts/" "$PROJECT_ROOT/server/")
elif [ -f "$PROJECT_ROOT/project.yml" ] || ls "$PROJECT_ROOT"/*.xcodeproj >/dev/null 2>&1 || ls "$PROJECT_ROOT"/Package.swift >/dev/null 2>&1; then
  # Swift/iOS: the source root is a target directory named after the module, not src/.
  # Without this branch the generic fallback probes src|lib|app, finds nothing, and the
  # architecture and risk challengers review the plan with an empty file structure.
  FRAMEWORK="swift-ios"
  SOURCE_DIRS_ARR=()
  while IFS= read -r dir; do
    SOURCE_DIRS_ARR+=("$dir")
  done < <(find "$PROJECT_ROOT" -maxdepth 2 -name '*.swift' -not -path '*/.build/*' -exec dirname {} \; 2>/dev/null | sort -u | head -20)
elif [ -f "$PROJECT_ROOT/manage.py" ]; then
  FRAMEWORK="django"
  SOURCE_DIRS_ARR=()
  while IFS= read -r dir; do
    SOURCE_DIRS_ARR+=("$dir")
  done < <(find "$PROJECT_ROOT" -name 'apps.py' -exec dirname {} \; 2>/dev/null | head -20)
else
  FRAMEWORK="generic"
  SOURCE_DIRS_ARR=("$PROJECT_ROOT/src/" "$PROJECT_ROOT/lib/" "$PROJECT_ROOT/app/")
fi
SOURCE_DIRS="${SOURCE_DIRS_ARR[*]}"

find "${SOURCE_DIRS_ARR[@]}" -maxdepth 2 -type d 2>/dev/null | head -50
```

Determine ZENTRALE_PATTERNS:
- Read CLAUDE.md and extract architecture conventions (if present)
- If no CLAUDE.md: analyze the directory structure for patterns (services, repositories, traits, mixins, composables)
- Summarize compactly in max 10 lines

## Phase 3: Challenge Dispatch

Subagents in parallel, only the dimensions included in `CHALLENGE_DIMS` (Phase 0.5) (low=3, medium=4, high/xhigh=5).

**Dispatch them with `run_in_background: false`.** Subagents background by
default, and a background subagent returns its result as a completion notification in a *later*
turn. The consolidation step right after this one has to see all challenger outputs at once in order
to deduplicate convergent concerns, which is where the value of the panel sits. A backgrounded
challenge round turns that into a partial read of whichever agents happened to have reported.

`{PROJECT_GUIDELINES}` comes from Phase 0.7 (`.claude/plan-guidelines.md`); if empty, omit the block.

**Product, Design, Simplicity** receive the plan + project guidelines:
```
Agent(
  prompt: "Read agents/challenge-{dimension}.md and review this plan:
    {PLAN_INHALT}

    PROJECT GUIDELINES (take precedence over generic best practices):
    {PROJECT_GUIDELINES}",
  subagent_type: plan-challenger,
  run_in_background: false
)
```

**Architecture, Risk** additionally receive the codebase context and the drift-check rule:
```
Agent(
  prompt: "Read agents/challenge-{dimension}.md and review this plan:
    {PLAN_INHALT}

    PROJECT GUIDELINES (take precedence over generic best practices):
    {PROJECT_GUIDELINES}

    Codebase context:
    FILE STRUCTURE: {DATEISTRUKTUR}
    CORE PATTERNS: {ZENTRALE_PATTERNS}
    FRAMEWORK: {FRAMEWORK}

    DRIFT CHECK: compare the plan's claims against the WORKING TREE, not only
    committed history. Run `git status --short` and `git diff --stat` (uncommitted)
    in addition to `git diff --stat {PLANNED_AT_SHA}..HEAD`. Report 'no drift'
    only when all three are empty for in-scope paths.",
  subagent_type: plan-challenger,
  run_in_background: false
)
```

| Agent | File | Perspective |
|---|---|---|
| Product | `agents/challenge-product.md` | CEO/founder — does this actually solve the problem? |
| Architecture | `agents/challenge-architecture.md` | Senior engineer — technically sound? |
| Design | `agents/challenge-design.md` | Designer — how does this feel? |
| Risk | `agents/challenge-risk.md` | Skeptic — what could go wrong? |
| Simplicity | `agents/challenge-simplicity.md` | Minimalist — what can be cut? |

## Phase 3.5: Evaluation Prompt

```
Agent(
  prompt: "You are an experienced tech lead. Read this plan and evaluate it honestly.

    {PLAN_INHALT}

    [When the plan changes the semantics of an existing function, paste the relevant function
    bodies into this brief instead of describing them abstractly.]

    PROJECT GUIDELINES (take precedence over generic best practices):
    {PROJECT_GUIDELINES}

    Codebase context:
    FILE STRUCTURE: {DATEISTRUKTUR}
    CORE PATTERNS: {ZENTRALE_PATTERNS}
    FRAMEWORK: {FRAMEWORK}

    Evaluate the plan on these dimensions (1-2 sentences each, no filler):

    1. Completeness — Are steps missing? Gaps between 'what the plan says' and 'what actually needs to be done'?
    2. Ordering — Is the sequence right? Dependencies wrong or not considered at all?
    3. Effort — Re-estimate the effort yourself from the step list, independently; do NOT just sanity-check the author's number. Name the biggest item and say where your estimate differs from the plan's. If the plan introduces a view or interaction pattern with no precedent in the repo (chat thread, story engine, masonry grid, custom drawer), require its own line item and reject an estimate that folds it into the overall block: the first build of a pattern costs more than an edit to an existing view, because states, gestures, focus, Dynamic Type and both appearances all start from zero.
    4. Risks — What is the biggest risk the plan doesn't address?
    5. Actionability — Can a developer take the plan and start right away? Does every step have a checkable verify criterion?

    MANDATORY checklist (check briefly):
    - Monitoring/alerting blind spots: failure modes the plan doesn't make observable?
    - Existing feature overlap: similar features in the codebase that should be reused?
    - Optimization levers: parallelization, caching, batch processing — where can effort be reduced?
    - Were user decisions that overruled a challenge recommendation carried through consistently, or does a conflict remain in the plan?
    - For AI/ML features: capability matrix checked (language x region x model availability x device class)?
    - PR consolidation: can the planned PRs be merged into fewer, or should one be split?
    - Preview/mockup resolutions: when a round was decided by picking a preview or mockup, diff the details it implies against every earlier separate answer. A chosen mockup silently overrides answers it contradicts.
    - Non-functional requirements checked: logging strategy, telemetry, accessibility, simulator vs production differences?

    At the end: an overall verdict in ONE sentence.
    If changes are recommended: at most 3 concrete suggestions.",
  subagent_type: general-purpose,
  model: sonnet,
  run_in_background: false
)
```
