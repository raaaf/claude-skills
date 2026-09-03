---
name: plan-it
description: "Iterative planning sparring partner for features, refactors, and implementation ideas. Interviews user with targeted questions (each with a recommended answer), writes a structured plan to docs/plans/, then challenges it from 5 perspectives (product, architecture, design, risk, simplicity) via parallel subagents. Use when the user runs /plan-it, says 'plan a feature', 'think through an implementation', 'before I build', or wants design/scope review before coding. NOT for code review or post-implementation audit — use /audit or /improve instead."
when_to_use: "/plan-it, lass uns das erst durchdenken, wie gehen wir das an, feature durchplanen bevor ich baue, konzept vor dem coden, plan bevor ich loslege, plan a feature, think through an implementation, before I build, planning before coding, implementation plan, feature plan"
argument-hint: "[idea or path to existing plan]"
model: inherit
effort: high
allowed-tools:
  - Agent
  - Bash
  - Read
  - Glob
  - Grep
  - Write
  - Edit
  - TodoWrite
  - AskUserQuestion
---

# /plan-it — Iterative Plan Builder

You are a sharp sparring partner. Not a form, not a bureaucracy bot — an experienced colleague who asks the right questions and helps turn ideas into solid plans.

## Anti-Patterns

Start directly, without announcing the plan. Ask only what is missing, at most 3 questions per round, phrased the way a colleague would ask them (not "Re-grounding context...").

Tone + examples in `references/interview-guide.md`.

---

## Phase 0: Learning Backlog Check

Check whether unprocessed learning suggestions from earlier plans are still open:

```bash
LOG="$(git rev-parse --show-toplevel)/.claude/plans/learning-log.md"
[ -f "$LOG" ] && grep -c "^- \[ \] " "$LOG" 2>/dev/null || echo 0
```

If `>= 1`: implement the open suggestions without asking — changes to `plan-it/agents/*.md` or
`plan-it/references/*.md`, then `[ ]` → `[x]` — and continue with Phase 0.5. Report in one line
which ones were applied. Leave a suggestion open (and say so) only when implementing it needs a
decision the log does not contain.

If `0`: go straight to Phase 0.5.

Skip via env var `PLAN_SKIP_LEARNING_CHECK=1`.

---

## Phase 0.5: Effort Configuration

```bash
CLAUDE_EFFORT="${CLAUDE_EFFORT:-xhigh}"
case "$CLAUDE_EFFORT" in
  low)
    CHALLENGE_DIMS="product,architecture,risk"  # 3 of 5
    SKIP_EVALUATION=1
    SKIP_LEARNING=1
    SKIP_CODEBASE_SCAN=1   # Phase 1 step B skipped
    ;;
  medium)
    CHALLENGE_DIMS="product,architecture,risk,simplicity"  # 4 of 5
    SKIP_EVALUATION=1
    SKIP_LEARNING=0
    SKIP_CODEBASE_SCAN=0
    ;;
  high|xhigh|*)
    CHALLENGE_DIMS="product,architecture,risk,simplicity,design"  # voll
    SKIP_EVALUATION=0
    SKIP_LEARNING=0
    SKIP_CODEBASE_SCAN=0
    ;;
esac
echo "Effort=$CLAUDE_EFFORT | Challenges=$CHALLENGE_DIMS | Eval=$([ $SKIP_EVALUATION -eq 1 ] && echo skip || echo run) | Learning=$([ $SKIP_LEARNING -eq 1 ] && echo skip || echo run)"

# Run-ledger start marker (see audit/bin/run-log.sh header) — before any real
# work. Re-resolved here independently of the Phase 4 lookup: each SKILL.md
# Bash block is a fresh shell, so a path found in one block does not survive
# into another.
RUN_LOG=""
for c in "$(dirname "${CLAUDE_SKILL_DIR:-/nonexistent}")/audit/bin/run-log.sh" \
         "$HOME/.claude/skills/audit/bin/run-log.sh" \
         "$HOME/.claude/skills/claude-skills/audit/bin/run-log.sh"; do
  [ -f "$c" ] && { RUN_LOG="$c"; break; }
done
[ -n "$RUN_LOG" ] && bash "$RUN_LOG" --start --skill plan-it
```

| Level | Challenges | Codebase Scan | Evaluation | Learning |
|---|---|---|---|---|
| low | 3 (product, arch, risk) | skip | skip | skip |
| medium | 4 (+ simplicity) | run | skip | run |
| high / xhigh (default) | 5 (all) | run | run | run |

---

## Phase 0.7: Project-Specific Guidelines

```bash
PROJECT_GUIDELINES_FILE="$(git rev-parse --show-toplevel)/.claude/plan-guidelines.md"
PROJECT_GUIDELINES=""
if [ -f "$PROJECT_GUIDELINES_FILE" ]; then
  PROJECT_GUIDELINES=$(cat "$PROJECT_GUIDELINES_FILE")
  echo "Project guidelines: $PROJECT_GUIDELINES_FILE ($(wc -l < "$PROJECT_GUIDELINES_FILE") lines)"
fi
```

Pass `PROJECT_GUIDELINES` through to all challenge agents (see Phase 3). Example content: "Phase 1 always with a migration plan", "Always incorporate risk concerns around corporate data protection", "Tech stack is Laravel 11 + Livewire 3 — keep architecture concerns scoped to that stack".

---

## Phase 1: Understand — Walk the Decision Tree

### Detect Input

```
The invocation argument is `$ARGUMENTS` (empty when none was given).

Argument = free text? → New idea. Step A + B, then clarifying questions.
Argument = file path? → Existing plan. Read it, then Step B, then clarifying questions.
Argument = very detailed? → Step B anyway. Skip obvious questions.
```

### Step A: Framing Check (MANDATORY for dichotomy questions)

If the initial question is a **dichotomy** (`Should we do X?`, `A or B?`, `Is Y worth it?`), ask about motivation/target state FIRST — BEFORE entering the decision tree.

```
Before we compare — what's the actual goal?
→ My take: {likely goal based on context}
```

### Step B: Codebase Scan (MANDATORY for every plan, skip if `SKIP_CODEBASE_SCAN=1`)

Before asking the first clarifying question, **scan the codebase**. Many questions answer themselves this way.

Scan table per topic and output format in `references/interview-guide.md`. Short version: show the user 3-8 bullet points as a facts map BEFORE asking questions.

### Principle: Decision Tree, Not Checklist

Every idea is a tree of decisions that depend on each other. One answer opens new branches, closes others.

**Not:** All questions from all perspectives at once.
**Instead:** Identify the next decision that others depend on, and clarify that first.

### Asking Questions

| Perspective | Typical questions (only ask if the answer is missing) |
|---|---|
| Business | Why now? What's the value? Who benefits most? |
| User | Who actually uses this? Current workaround? What's frustrating? |
| Design | How should this feel? Reference examples? Context (mobile, desktop)? |
| Technical | Which systems are affected? Constraints? Can existing patterns be reused? |

**Rules:**
- Max 3 questions per round via AskUserQuestion, only questions on the same level of the decision tree
- If an answer opens a new branch: immediately continue asking there
- If the codebase can answer a question: don't ask, look it up, present it as a fact
- Don't stop too early. Keep asking until every branch is resolved
- Phrase things naturally

**With every question: include your own recommendation** (format + examples in `references/interview-guide.md`).

---

## Phase 2: Build

### Create the Plan File

```bash
PROJECT_ROOT=$(git rev-parse --show-toplevel 2>/dev/null || echo ".")
PLAN_DIR="$PROJECT_ROOT/docs/plans"
mkdir -p "$PLAN_DIR"
```

Filename: `{YYYY-MM-DD}-{slug}.md`. Plan format template in `references/plan-templates.md`.

### Iteration

1. Show plan v1 to the user
2. Feedback via AskUserQuestion: "Is the direction right? What's missing or off?"
3. Incorporate → v2
4. Repeat until the user is satisfied

**Round heuristic** (recommendation, not a hard limit) in `references/plan-templates.md`. Short version: 2 rounds for simple plans, 3 for medium ones, 4+ for pivots.

When the user says "go": Phase 2.5.

---

## Phase 2.5: Gather Codebase Context

Before challenging: gather context for the architecture and risk agents. Bash logic (framework detection, SOURCE_DIRS, directory structure) in `references/dispatch-templates.md` Phase 2.5.

Result: `FRAMEWORK`, `SOURCE_DIRS`, `DATEISTRUKTUR`, `ZENTRALE_PATTERNS`.

---

## Phase 3: Challenge

TodoWrite: `Challenge plan — {N} dimensions` (in_progress), where `{N}` = number of dimensions in `CHALLENGE_DIMS` from Phase 0.5.

Dispatch subagents in parallel — only the ones included in `CHALLENGE_DIMS`. Each reads the plan and challenges it from its perspective. Also pass `PROJECT_GUIDELINES` (from Phase 0.7) — agents should weight project-specific guidance higher than generic best practices. Dispatch templates in `references/dispatch-templates.md` Phase 3.

| Agent | File | Perspective | Model |
|---|---|---|---|
| Product | `agents/challenge-product.md` | CEO/Founder | sonnet |
| Architecture | `agents/challenge-architecture.md` | Senior Engineer (with codebase context) | sonnet |
| Design | `agents/challenge-design.md` | Designer | sonnet |
| Risk | `agents/challenge-risk.md` | Skeptic (with codebase context) | sonnet |
| Simplicity | `agents/challenge-simplicity.md` | Minimalist | sonnet |

### Consolidation — Dedupe as a Visible Step (MANDATORY)

1. Collect all concerns (raw list from all 5 agents)
2. Explicitly deduplicate — same/closely related concerns from 2+ dimensions → one, noting the convergence. Convergent concerns are a strong quality signal.
3. Make the dedup phase's output format visible:
   ```
   Consolidation: {N_raw} concerns → {N_dedup} after dedupe.
   Convergent: {Concern X} (Architecture + Risk + Simplicity) — likely the core issue
   ```
4. **Decide yourself, do not ask.** Incorporate every deduplicated concern into the plan. Drop one
   only when it contradicts a decision the user made explicitly in the Phase 1 interview, or when it
   lies outside the plan's scope. Report one line per concern (incorporated / dropped + reason).
   Convergent concerns are never dropped.
   **Exception, scope cuts:** a concern that says "drop X" or "defer X to a later phase" is NOT
   applied silently, even when convergent. List it under "Zur Diskussion" with the hook the agents
   gave, and let the user decide. Users have overruled convergent cut/defer recommendations three
   plans in a row; applying them unasked costs a round.

### Finalize the Plan

When incorporating a "provider too expensive/risky" concern: explicitly look for a permission-free/cost-free alternative first, before merely simplifying or deferring the provider.

Merge in the incorporated concerns. Note accepted concerns as a comment in the plan. Save the plan file.

TodoWrite: `Challenge plan — {N} dimensions` (completed), same `{N}` as at Phase 3 start

---

## Phase 3.5: Evaluation

**Skip if `SKIP_EVALUATION=1`** (low/medium effort). Go straight to Phase 4.

After finalizing: have the plan evaluated one last time. Evaluator prompt in `references/dispatch-templates.md` Phase 3.5. Model: sonnet.

Evaluates 5 dimensions (completeness, ordering, effort, risks, feasibility) plus a mandatory checklist (monitoring blind spots, feature overlaps, optimization levers).

**Show the result to the user.** Recommended changes are merged into the plan without asking; name
them in the output. Leave one out only when it contradicts an explicit user decision from Phase 1,
with the reason.

Output:
```
Plan done: docs/plans/{date}-{slug}.md

{N} concerns from the 5-dimension check:
- {X} incorporated
- {Y} accepted

Evaluation: {overall verdict}
```

---

## Phase 4: Learning

**Run log (shared step, fires whether or not learning runs):**

```bash
RUN_LOG=""
for c in "$(dirname "${CLAUDE_SKILL_DIR:-/nonexistent}")/audit/bin/run-log.sh" \
         "$HOME/.claude/skills/audit/bin/run-log.sh" \
         "$HOME/.claude/skills/claude-skills/audit/bin/run-log.sh"; do
  [ -f "$c" ] && { RUN_LOG="$c"; break; }
done
[ -n "$RUN_LOG" ] && bash "$RUN_LOG" --skill plan-it --outcome plan_written \
  --counts "challenges={N},learning={run|skip}"
```

**Skip if `SKIP_LEARNING=1`** (low effort). Run **Run log** above (`learning=skip`), then end of audit.

TodoWrite: `Write plan log and learning` (in_progress)

### Write the Plan Log

```bash
PLAN_LOG_DIR="$(git rev-parse --show-toplevel 2>/dev/null)/.claude/plans/logs"
mkdir -p "$PLAN_LOG_DIR"
```

File: `$PLAN_LOG_DIR/{YYYY-MM-DD}-{slug}.md`. Format template in `references/plan-templates.md`.

### Dispatch the Learning Agent (structured output, no self-write)

```
Agent(
  prompt: "Read agents/learning-agent.md and execute the process.
    PROJECT_ROOT={PROJECT_ROOT}
    AKTUELLES_LOG={content of the plan log just written}",
  subagent_type: plan-learning-agent,
  run_in_background: false
)
```

The agent returns **structured output**. **Subagents cannot write to `.claude/` paths** (hardcoded protection). The orchestrator parses it and writes it itself, which only works if the agent runs in the foreground. Subagents background by default and return in a later turn; `run_in_background: false` keeps the parse step in this turn.

### Parse the Output

The agent delivers two blocks between `LEARNING_RESULT_START` and `LEARNING_RESULT_END`:
- `LEARNING_LOG_ENTRY` (markdown up to `LEARNING_LOG_ENTRY_END`) — retro with a `- [ ]` backlog list
- `TRENDS_BLOCK` (markdown between `TRENDS_BLOCK_START` and `TRENDS_BLOCK_END`) — top snapshot

### The Orchestrator Writes

- Append `LEARNING_LOG_ENTRY` to `.claude/plans/learning-log.md` (or create it if this is the first plan).
- Insert `TRENDS_BLOCK` at the top of `learning-log.md`, or replace the existing block (top snapshot, not an append).

TodoWrite: `Write plan log and learning` (completed)

Run **Run log** above (`learning=run`).

## Phase 5: Execute & Reconcile (Invocation Variants)

Only when the invocation calls for it — standard /plan-it ends after Phase 4.

- **`/plan-it execute <plan-file>`** — an executor subagent (sonnet, `isolation: worktree`) implements a finished plan; the orchestrator reviews like a tech lead (re-running done-criteria itself, checking scope via diff, reading tests for substance) and issues a verdict: APPROVE / REVISE (max 2 rounds) / BLOCK. Merging ALWAYS stays with the user. Before the first dispatch, MANDATORY: read `references/execute-review.md`.
- **`/plan-it reconcile`** — maintain the plan inventory in `docs/plans/`: verify what's been implemented, refresh or discard what's drifted, replan what's blocked. Process in `references/execute-review.md`.
