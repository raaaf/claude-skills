# Plan + Log Templates

Templates for Phase 2 (plan file) and Phase 4 (plan log).

Content: plan format (executor-grade, with drift check/STOP/done criteria) · plan log format · round heuristic

## Plan Format (Phase 2)

File: `docs/plans/{YYYY-MM-DD}-{slug}.md`

**Executor rule:** The plan is written for an executor WITHOUT session context (a different model, a different session, or a human). Everything needed is in the file: exact paths, current state, conventions with an exemplar file, commands. "As discussed" is a violation.

```markdown
# {Title}

> **Executor instruction:** Follow step by step, check each verify
> criterion before moving on. If a STOP condition occurs: stop and
> report, do not improvise.
>
> **Drift check (first):** `git diff --stat {PLANNED_AT_SHA}..HEAD -- {in-scope paths}`
> If an in-scope file has changed since the plan was created: reconcile the
> current state against the live code; on a mismatch, that is a STOP condition.

## Meta
- Planned at: commit `{git rev-parse --short HEAD}`, {DATE}

## Problem
{What is the problem — in 1-3 sentences. The PROBLEM, not the solution.}

## Goal
{How do you know it's solved? Measurable if possible.}

## Non-Goals
{What is explicitly NOT part of this.}

## Out of Scope (Files)
{Files/areas that look related but must NOT be touched — with a 1-sentence reason (e.g. "legacy-api.ts: deprecated, v1 clients still depend on it").}

## Solution

### Approach
{Description of the solution approach — why this way and not another.}

### Steps
1. {Concrete — which file, which component, what changes} → verify: {checkable criterion, e.g. "Test X green", "Route Y returns 200", "Grep for Z empty"}
2. ... → verify: ...

Every step gets a verify criterion. A step without a checkable outcome is not a step, it's an intention.

### Effort
{Rough estimate: S (<0.5 day) / M (0.5-2 days) / L (3-5 days) / XL (>1 week) — plus the single biggest item in 1 sentence.}

### Affected Files
- `path/to/file` — {what changes}

### Conventions
{Which repo patterns apply, with an exemplar file: "Error handling follows the Result pattern — see src/lib/result.ts and its usage in src/users/api.ts:40-60. Exactly like that."}

## Edge Cases
- {Case}: {Handling}

## Done Criteria
Machine-checkable, ALL must hold — commands with expected result, no prose like "works correctly":
- [ ] `{test command}` → exit 0, incl. {N} new tests
- [ ] `{lint/typecheck command}` → exit 0
- [ ] `grep -rn "{old pattern}" src/` → no matches
- [ ] No files outside the affected-files list changed (`git status`)

## STOP Conditions
Stop and report (do not improvise) when:
- The current state at the named locations does not match the descriptions (codebase has drifted).
- A verify criterion fails twice after a serious fix attempt.
- The fix would need to touch an out-of-scope file.
- {plan-specific core assumption} turns out to be false.

## Validation of the Bet
{MANDATORY whenever the plan changes product identity (core loop, main surface, positioning) rather than just adding a feature. Two criteria, both concrete and dated:}
- **Works when:** {observable signal that the bet is paying off, with a deadline — "after 3 weeks, at least 10 days with an entry", not "feels better"}
- **Rollback when:** {observable signal that it failed, plus what exactly gets reverted}

## Maintenance Notes
{What future changes to this code will need to consider; what a reviewer should check in the PR; explicitly deferred items with a reason.}

## Open Questions
- {If any remain — otherwise omit}
```

**Optional sections** (only when they add value):
- Data flow diagram (ASCII or Mermaid)
- Migration strategy
- Rollback plan

## Plan Log Format (Phase 4)

File: `.claude/plans/logs/{YYYY-MM-DD}-{slug}.md`

```markdown
# Plan Log — {Title}

## Meta
- Date: {DATE}
- Rounds Phase 1 (understanding): {N}
- Plan file: docs/plans/{date}-{slug}.md

## Questions & Answers
- {Question} → {user's answer or "assessment confirmed"}

## Challenge Result
- Concerns total: {N}
- Incorporated: {X}
- Accepted: {Y}
- Rejected: {Z}

## Notable
- {Pattern or surprise, e.g. "user rejected all design concerns"}
```

## Round Heuristic (Recommendation, Not a Hard Limit)

| Complexity | Rounds | When |
|---|---|---|
| Simple | 2 | Clear requirement, isolated feature, no data model overhaul |
| Medium | 3 | Data model overhaul, multi-channel feature, complex policy question |
| High | 4+ | Framing needs clarification, initial pivot (e.g. "Should we do X?" → actually Y) |

Backed by the learning log (8 plans, avg. 2.86 rounds): Plan 1 (2 rounds, simple), Plan 7 (4 rounds, pivot). For data model overhauls, the third pass almost always pays off.
