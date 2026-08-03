# Dispatch Templates

Bash logic and prompt templates for Phase 2.5 (codebase context), Phase 3 (challenging), Phase 3.5 (evaluation).

## Contents
- Phase 2.5 — Gather codebase context (framework detection, source dirs)
- Phase 3 — Dispatch plan challengers (5 parallel reviewers)
- Phase 3.5 — Parse evaluation (consensus score, change proposals)

## Phase 2.5: Gather Codebase Context

```bash
PROJECT_ROOT=$(git rev-parse --show-toplevel 2>/dev/null || echo ".")

# Detect framework and source dirs
if [ -f "$PROJECT_ROOT/artisan" ]; then
  FRAMEWORK="laravel"
  SOURCE_DIRS="$PROJECT_ROOT/app/ $PROJECT_ROOT/resources/ $PROJECT_ROOT/database/ $PROJECT_ROOT/routes/ $PROJECT_ROOT/config/"
elif [ -f "$PROJECT_ROOT/package.json" ] && grep -q '"next"' "$PROJECT_ROOT/package.json" 2>/dev/null; then
  FRAMEWORK="nextjs"
  SOURCE_DIRS="$PROJECT_ROOT/src/ $PROJECT_ROOT/app/ $PROJECT_ROOT/pages/ $PROJECT_ROOT/components/ $PROJECT_ROOT/lib/"
elif [ -f "$PROJECT_ROOT/nuxt.config.ts" ] || [ -f "$PROJECT_ROOT/nuxt.config.js" ]; then
  FRAMEWORK="nuxt"
  SOURCE_DIRS="$PROJECT_ROOT/components/ $PROJECT_ROOT/composables/ $PROJECT_ROOT/pages/ $PROJECT_ROOT/layouts/ $PROJECT_ROOT/server/"
elif [ -f "$PROJECT_ROOT/manage.py" ]; then
  FRAMEWORK="django"
  SOURCE_DIRS="$(find "$PROJECT_ROOT" -name 'apps.py' -exec dirname {} \; | head -20 | tr '\n' ' ')"
else
  FRAMEWORK="generic"
  SOURCE_DIRS="$PROJECT_ROOT/src/ $PROJECT_ROOT/lib/ $PROJECT_ROOT/app/"
fi

find $SOURCE_DIRS -maxdepth 2 -type d 2>/dev/null | head -50
```

Determine ZENTRALE_PATTERNS:
- Read CLAUDE.md and extract architecture conventions (if present)
- If no CLAUDE.md: analyze the directory structure for patterns (services, repositories, traits, mixins, composables)
- Summarize compactly in max 10 lines

## Phase 3: Challenge Dispatch

Subagents in parallel — only the dimensions included in `CHALLENGE_DIMS` (Phase 0.5) (low=3, medium=4, high/xhigh=5).

`{PROJECT_GUIDELINES}` comes from Phase 0.7 (`.claude/plan-guidelines.md`); if empty, omit the block.

**Product, Design, Simplicity** receive the plan + project guidelines:
```
Agent(
  prompt: "Read agents/challenge-{dimension}.md and review this plan:
    {PLAN_INHALT}

    PROJECT GUIDELINES (take precedence over generic best practices):
    {PROJECT_GUIDELINES}",
  subagent_type: general-purpose,
  model: haiku
)
```

**Architecture, Risk** additionally receive the codebase context:
```
Agent(
  prompt: "Read agents/challenge-{dimension}.md and review this plan:
    {PLAN_INHALT}

    PROJECT GUIDELINES (take precedence over generic best practices):
    {PROJECT_GUIDELINES}

    Codebase context:
    FILE STRUCTURE: {DATEISTRUKTUR}
    CORE PATTERNS: {ZENTRALE_PATTERNS}
    FRAMEWORK: {FRAMEWORK}",
  subagent_type: general-purpose,
  model: sonnet
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

    PROJECT GUIDELINES (take precedence over generic best practices):
    {PROJECT_GUIDELINES}

    Codebase context:
    FILE STRUCTURE: {DATEISTRUKTUR}
    CORE PATTERNS: {ZENTRALE_PATTERNS}
    FRAMEWORK: {FRAMEWORK}

    Evaluate the plan on these dimensions (1-2 sentences each, no filler):

    1. Completeness — Are steps missing? Gaps between 'what the plan says' and 'what actually needs to be done'?
    2. Ordering — Is the sequence right? Dependencies wrong or not considered at all?
    3. Effort — Re-estimate the effort yourself from the step list, independently; do NOT just sanity-check the author's number (3 of 4 past plans had to revise the initial estimate upward). Name the biggest item and say where your estimate differs from the plan's.
    4. Risks — What is the biggest risk the plan doesn't address?
    5. Actionability — Can a developer take the plan and start right away? Does every step have a checkable verify criterion?

    MANDATORY checklist (check briefly):
    - Monitoring/alerting blind spots: failure modes the plan doesn't make observable?
    - Existing feature overlap: similar features in the codebase that should be reused?
    - Optimization levers: parallelization, caching, batch processing — where can effort be reduced?

    At the end: an overall verdict in ONE sentence.
    If changes are recommended: at most 3 concrete suggestions.",
  subagent_type: general-purpose,
  model: sonnet
)
```
