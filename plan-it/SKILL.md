---
name: plan-it
description: "Iterative planning sparring partner for features, refactors, and implementation ideas. Scans the codebase, interviews the user with targeted questions (each with a recommended answer), writes a structured plan to docs/plans/ that ends in a /delegate-ready spec, then challenges it via parallel subagents (architecture and risk always; product, design, simplicity when the plan calls for them). Use when the user runs /plan-it, says 'plan a feature', 'think through an implementation', 'before I build', or wants design/scope review before coding. NOT for code review or post-implementation audit — use /audit instead."
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
    CHALLENGE_POOL="architecture,risk"   # only the two always-on challengers
    SKIP_EVALUATION=1
    SKIP_CODEBASE_SCAN=1   # Phase 1 step B skipped
    ;;
  medium)
    CHALLENGE_POOL="architecture,risk,product,design,simplicity"   # Phase 3 picks from this pool
    SKIP_EVALUATION=1
    SKIP_CODEBASE_SCAN=0
    ;;
  high|xhigh|*)
    CHALLENGE_POOL="architecture,risk,product,design,simplicity"   # Phase 3 picks from this pool
    SKIP_EVALUATION=0
    SKIP_CODEBASE_SCAN=0
    ;;
esac
echo "Effort=$CLAUDE_EFFORT | Pool=$CHALLENGE_POOL | Eval=$([ $SKIP_EVALUATION -eq 1 ] && echo skip || echo run)"

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

| Level | Challenge pool | Codebase Scan | Evaluation |
|---|---|---|---|
| low | architecture, risk only | skip | skip |
| medium | all 5, selected per plan (Phase 3) | run | skip |
| high / xhigh (default) | all 5, selected per plan (Phase 3) | run | run |

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

Pass `PROJECT_GUIDELINES` through to every challenge agent that runs (see Phase 3). Example content: "Phase 1 always with a migration plan", "Always incorporate risk concerns around corporate data protection", "Tech stack is Laravel 11 + Livewire 3 — keep architecture concerns scoped to that stack".

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

> `Evidence:` notes in this skill and in `references/interview-guide.md` cite counts from a retired
> plan-it retro (removed 2026-10-02) over per-project plan logs that were gitignored in each
> project. They are not reproducible from this repo, which is why a grep here finds nothing behind them.

**Framing symptom check:** when the user's question is a surface or label question (naming, wording, which brand, which label), first check whether a feature gap sits behind it before answering the surface question. Evidence: 4 of 8 plans had a hidden real goal.

### Step B: Codebase Scan (MANDATORY for every plan, skip if `SKIP_CODEBASE_SCAN=1`)

Before asking the **first** clarifying question, **scan the codebase**. Many questions answer themselves
this way: with the scan done first, 15 of 15 zeit plans needed only 1-2 interview rounds.

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
- Max 3 questions per round via AskUserQuestion, each with a recommended default; max 3 rounds in total. Only questions on the same level of the decision tree
- Skip every question the facts map already answers
- If an answer opens a new branch: immediately continue asking there
- If the codebase can answer a question: don't ask, look it up, present it as a fact
- Don't stop too early: keep asking until every branch is resolved, within the 3-round cap (leftovers go to Open Questions, see below)
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
map nor the set of open branches, do not open another round on the same level. Say what is still
unresolved, state the assumption you would proceed on, and ask the user to confirm or correct that
one assumption. Rounds that move nothing mean the question is wrong, not that the answer is
missing, and each further round costs the user a turn for nothing.

Either rule firing, or the third round ending, ends Phase 1. An unresolved branch does not block the plan: it goes into the
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

**Length cap.** The plan body (everything before the `## Delegate spec` section) stays at about 1,500
words. Longer material goes into an `## Appendix` after the Delegate spec, or is cut. Every plan ends
with the `## Delegate spec` section in /delegate's mini-spec format (template in
`references/plan-templates.md`), so /delegate can execute the plan without re-specifying it.

### No review round

The user does not read plan drafts. Do not open the plan file, do not show it, and do not ask for
feedback on it. The challenge panel in Phase 3 takes the role of the review round. User input comes
only from the Phase 1 interview and, after Phase 3, from the "zur Diskussion" scope cuts.

After writing v1, re-verify all cited `file:line` references against HEAD, then go straight to
Phase 2.5. Evidence: stale `billProjectInGroup` reference (Evidence provenance: see the note at the
top of Phase 1).

---

## Phase 2.5: Gather Codebase Context

Before challenging: gather context for the architecture and risk agents, and run the git drift/facts
check yourself (the challengers have no Bash). Bash logic (framework detection, SOURCE_DIRS, directory
structure, drift commands) in `references/dispatch-templates.md` Phase 2.5.

Result: `FRAMEWORK`, `SOURCE_DIRS`, `DATEISTRUKTUR`, `ZENTRALE_PATTERNS`, `DRIFT_OUTPUT`. `DRIFT_OUTPUT`
goes into every challenger briefing in Phase 3.

---

## Phase 3: Challenge

### Select the challengers

Architecture and risk always run (they produce most plan changes). The other three run only when their
condition holds, judged from the plan and the Phase 1 interview:

| Challenger | Runs when |
|---|---|
| Architecture | always |
| Risk | always |
| Design | the plan touches UI/UX surfaces (views, components, flows, copy users see) |
| Product | the feature is new to users, or its scope was not decided by the user |
| Simplicity | the scope is still open: the interview recorded no explicit user scope decision |

Intersect the result with `CHALLENGE_POOL` from Phase 0.5. Record in the plan's Meta section which
challengers ran and why, and which were skipped and why (one line each).

TodoWrite: `Challenge plan — {N} dimensions` (in_progress), where `{N}` = number of selected challengers.

Dispatch the selected subagents in parallel. Each reads the plan and challenges it from its perspective. Also pass `PROJECT_GUIDELINES` (from Phase 0.7) — agents should weight project-specific guidance higher than generic best practices — and the `DRIFT_OUTPUT` from Phase 2.5. Dispatch templates in `references/dispatch-templates.md` Phase 3.

| Agent | File | Perspective | Model |
|---|---|---|---|
| Product | `agents/challenge-product.md` | CEO/Founder | sonnet |
| Architecture | `agents/challenge-architecture.md` | Senior Engineer (with codebase context) | sonnet |
| Design | `agents/challenge-design.md` | Designer | sonnet |
| Risk | `agents/challenge-risk.md` | Skeptic (with codebase context) | sonnet |
| Simplicity | `agents/challenge-simplicity.md` | Minimalist | sonnet |

### Consolidation — Dedupe as a Visible Step (MANDATORY)

1. Collect all concerns (raw list from the agents that ran)
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
   applied silently, even when convergent. Simplicity's cuts are always labelled "zur Diskussion"
   (the `FOR DISCUSSION` marker) and never applied automatically. List them with the hook the agents
   gave, and let the user decide. Users have overruled convergent cut/defer recommendations three
   plans in a row; applying them unasked costs a round.

   **Known costs:** when a simplicity cut or a product objection ("measure usage first") is rejected
   in favour of the fuller solution, record the price it buys in the plan's "Known Costs" section
   (e.g. custom migration stage instead of lightweight, no usage signal before build). The user
   consistently picks the full solution, so the cost has to be visible rather than silently dropped.

### Finalize the Plan

When incorporating a "provider too expensive/risky" concern: explicitly look for a permission-free/cost-free alternative first, before merely simplifying or deferring the provider.

Merge in the incorporated concerns, then record every concern in the plan's challenge-result block
(template in `references/plan-templates.md`) as accepted, rejected, or deferred. A deferred concern
carries a revisit condition ("revisit when ..."). Re-check the 1,500-word body cap and that the
Delegate spec still matches the final steps. Save the plan file.

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

{3-5 lines: what the plan builds, the key decisions, the open scope cuts}

{N} concerns from the {M} challengers that ran ({names}):
- {X} accepted (incorporated)
- {Y} rejected
- {Z} deferred (revisit condition recorded)

Evaluation: {overall verdict}
Next: /delegate docs/plans/{date}-{slug}.md
```

---

## Phase 4: Run log

```bash
for c in "$(dirname "${CLAUDE_SKILL_DIR:-/nonexistent}")/audit/bin/lib-orchestrator.sh" "$HOME/.claude/skills/audit/bin/lib-orchestrator.sh"; do [ -f "$c" ] && { . "$c"; break; }; done   # fresh shell per block: source the lib again
orch_run_log --skill plan-it --outcome plan_written \
  --counts "challenges={M}"   # M = number of challengers that ran
```

## Phase 5: Execute & Reconcile (Invocation Variants)

Only when the invocation calls for it — standard /plan-it ends after Phase 4.

- **`/plan-it execute <plan-file>`** — an executor subagent (sonnet, `isolation: worktree`) implements a finished plan; the orchestrator reviews like a tech lead (re-running done-criteria itself, checking scope via diff, reading tests for substance) and issues a verdict: APPROVE / REVISE (max 2 rounds) / BLOCK. Merging ALWAYS stays with the user. Before the first dispatch, MANDATORY: read `references/execute-review.md`.
- **`/plan-it reconcile`** — maintain the plan inventory in `docs/plans/`: verify what's been implemented, refresh or discard what's drifted, replan what's blocked. Process in `references/execute-review.md`.
