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
  - ToolSearch
  - mcp__ccd_view__show_pane
---

# /plan-it — Iterative Plan Builder

You are a sharp sparring partner. Not a form, not a bureaucracy bot — an experienced colleague who asks the right questions and helps turn ideas into solid plans.

## Anti-Patterns

Start directly, without announcing the plan. Ask only what is missing, at most 3 questions per round, phrased the way a colleague would ask them (not "Re-grounding context...").

Tone + examples in `references/interview-guide.md`.

---

## Phase 0.5: Effort Configuration

```bash
CLAUDE_EFFORT="${CLAUDE_EFFORT:-high}"   # matches the frontmatter effort, which is what this variable receives at runtime
case "$CLAUDE_EFFORT" in
  low)
    CHALLENGE_DIMS="product,architecture,risk"  # 3 of 5
    SKIP_EVALUATION=1
    SKIP_CODEBASE_SCAN=1   # Phase 1 step B skipped
    ;;
  medium)
    CHALLENGE_DIMS="product,architecture,risk,simplicity"  # 4 of 5
    SKIP_EVALUATION=1
    SKIP_CODEBASE_SCAN=0
    ;;
  high|xhigh|*)
    CHALLENGE_DIMS="product,architecture,risk,simplicity,design"  # voll
    SKIP_EVALUATION=0
    SKIP_CODEBASE_SCAN=0
    ;;
esac
echo "Effort=$CLAUDE_EFFORT | Challenges=$CHALLENGE_DIMS | Eval=$([ $SKIP_EVALUATION -eq 1 ] && echo skip || echo run)"

# Run-ledger start marker (see audit/bin/run-log.sh header) — before any real
# work. Each SKILL.md Bash block is a fresh shell, so every block that calls an
# orch_ function sources the lib again (Phase 4 does too).
for c in "$(dirname "${CLAUDE_SKILL_DIR:-/nonexistent}")/audit/bin/lib-orchestrator.sh" \
         "$HOME/.claude/skills/audit/bin/lib-orchestrator.sh"; do
  [ -f "$c" ] && { . "$c"; break; }
done
type orch_run_log >/dev/null 2>&1 || echo "lib-orchestrator.sh not found; run log and helpers unavailable (skill continues)"
orch_run_log --start --skill plan-it
```

| Level | Challenges | Codebase Scan | Evaluation |
|---|---|---|---|
| low | 3 (product, arch, risk) | skip | skip |
| medium | 4 (+ simplicity) | run | skip |
| high / xhigh (default) | 5 (all) | run | run |

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

> `Evidence:` notes in this skill and in `references/interview-guide.md` cite counts from the retired
> plan-it learning retro (removed 2026-10-02) over per-project plan logs that were gitignored in each
> project. They are not reproducible from this repo, which is why a grep here finds nothing behind them.

**Framing symptom check:** when the user's question is a surface or label question (naming, wording, which brand, which label), first check whether a feature gap sits behind it before answering the surface question. Evidence: 4 of 8 plans had a hidden real goal.

### Step B: Codebase Scan (MANDATORY for every plan, skip if `SKIP_CODEBASE_SCAN=1`)

Before asking the first clarifying question, **scan the codebase**. Many questions answer themselves this way.

Scan table per topic and output format in `references/interview-guide.md`. Short version: show the user 3-8 bullet points as a facts map BEFORE asking questions.

**Scan dispatched to subagents: wait, do not re-scan.** Once scan agents are out, the main thread does
not grep the same questions itself. If an agent shows as idle without having delivered, send it one
`SendMessage` asking for its report and wait for the reply. Only an agent that stays silent after that
follow-up gets its questions scanned in the main thread, and only those questions. Evidence: in the
2026-09-17 plan all four agents delivered after one follow-up, while the main thread had already
repeated most of their greps.

**Provenance check.** For every file the plan intends to change, read its first 10 lines for a
generator marker (`auto-generated`, `DO NOT EDIT`, `@generated`) before drafting anything against it.
A found marker is a mandatory question to the user (what generates it, can the plan touch it at all),
never a side note. Evidence: 2026-08-10, `tokens.css` carried "DO NOT EDIT THIS FILE DIRECTLY" and the
scan missed it because it was counting tokens, not checking origin.

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
- For open "think this through" requests without a spec: after each framing round ask explicitly whether the current framing is the anchor or still moving. Prevents endless drift. Evidence: 5 of 11 plans pivoted.

**With every question: include your own recommendation** (format + examples in `references/interview-guide.md`).

### When the interview is done

"Keep asking until every branch is resolved" has no counterweight on its own, and an interview with
no stopping rule either stops arbitrarily or grinds. Two rules, both checkable, no confidence
percentage: a number nobody calibrates is theatre, and the plan template already states what the
interview owes.

**Completeness test (the reason to stop).** The interview is finished when you can fill every
required section of `references/plan-templates.md` from what you now know, without writing a
placeholder: steps each with a verify criterion, machine-checkable done criteria, affected files,
edge cases, out of scope, STOP conditions. Name the section that is still empty and ask about THAT.
When none is empty, stop asking and write the plan, even if further questions are imaginable.

**No-progress rule (the reason to stop anyway).** If a round of questions changed neither the facts
map nor the set of open branches, do not open a fourth round on the same level. Say what is still
unresolved, state the assumption you would proceed on, and ask the user to confirm or correct that
one assumption. Three rounds that move nothing mean the question is wrong, not that the answer is
missing, and each further round costs the user a turn for nothing.

Either rule firing ends Phase 1. An unresolved branch does not block the plan: it goes into the
plan's `## Open Questions` section with the assumption you chose, where the challenge panel can
attack it, which is cheaper than another interview round.

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

1. Show plan v1 to the user before asking anything. The AskUserQuestion dialog covers the chat, so a plan that exists only on disk is unreadable at question time. Open the written file: in the Claude desktop app call `mcp__ccd_view__show_pane` with `pane: "file"` and the plan's absolute path (load it via ToolSearch if deferred); if that tool is absent or reports no open window, run `open "<plan path>"` (macOS default Markdown viewer). Repeat after every revision so the user always reads the current version.
2. Feedback via AskUserQuestion: "Is the direction right? What's missing or off?"
3. Incorporate → v2
4. Repeat until the user is satisfied

After **every** incorporation round (not only round 1), re-verify all cited `file:line` references against HEAD — a reference can go stale between rounds. Evidence: stale `billProjectInGroup` reference, seen a second time (Evidence provenance: see the note at the top of Phase 1).

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
   applied silently, even when convergent. List it under "For discussion" (the `FOR DISCUSSION` marker the simplicity agent uses) with the hook the agents
   gave, and let the user decide. Users have overruled convergent cut/defer recommendations three
   plans in a row; applying them unasked costs a round.

   **Known costs:** when a simplicity cut or a product objection ("measure usage first") is rejected
   in favour of the fuller solution, record the price it buys in the plan's "Known Costs" section
   (e.g. custom migration stage instead of lightweight, no usage signal before build). The user
   consistently picks the full solution, so the cost has to be visible rather than silently dropped.

### Finalize the Plan

When incorporating a "provider too expensive/risky" concern: explicitly look for a permission-free/cost-free alternative first, before merely simplifying or deferring the provider.

Merge in the incorporated concerns. Note accepted concerns as a comment in the plan. Save the plan file.

TodoWrite: `Challenge plan — {N} dimensions` (completed), same `{N}` as at Phase 3 start

---

## Phase 3.5: Evaluation

**Skip if `SKIP_EVALUATION=1`** (low/medium effort). Go straight to Phase 4.

After finalizing: have the plan evaluated one last time. Evaluator prompt in `references/dispatch-templates.md` Phase 3.5. Model: sonnet.

Evaluates 4 dimensions (completeness, ordering, risks, feasibility) plus a mandatory checklist (monitoring blind spots, feature overlaps, optimization levers).

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

## Phase 4: Run log

```bash
for c in "$(dirname "${CLAUDE_SKILL_DIR:-/nonexistent}")/audit/bin/lib-orchestrator.sh" "$HOME/.claude/skills/audit/bin/lib-orchestrator.sh"; do [ -f "$c" ] && { . "$c"; break; }; done   # fresh shell per block: source the lib again
orch_run_log --skill plan-it --outcome plan_written \
  --counts "challenges={N}"
```

## Phase 5: Execute & Reconcile (Invocation Variants)

Only when the invocation calls for it — standard /plan-it ends after Phase 4.

- **`/plan-it execute <plan-file>`** — an executor subagent (sonnet, `isolation: worktree`) implements a finished plan; the orchestrator reviews like a tech lead (re-running done-criteria itself, checking scope via diff, reading tests for substance) and issues a verdict: APPROVE / REVISE (max 2 rounds) / BLOCK. Merging ALWAYS stays with the user. Before the first dispatch, MANDATORY: read `references/execute-review.md`.
- **`/plan-it reconcile`** — maintain the plan inventory in `docs/plans/`: verify what's been implemented, refresh or discard what's drifted, replan what's blocked. Process in `references/execute-review.md`.
