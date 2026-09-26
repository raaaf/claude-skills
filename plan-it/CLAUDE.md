# /plan-it internals

Rules bound to `/plan-it`'s own pipeline. Cross-cutting rules (background subagents, model
choice, run ledger) live in the root `CLAUDE.md`.

## Effort levels

| Level | /plan-it (default `high`) |
|---|---|
| low | 3 challenges, no eval, no learning |
| medium | 4 challenges, no eval |
| high / xhigh (default) | 5 challenges, full eval |

`/plan-it` carries `effort: high` in its frontmatter, and per the dual-use rule that value is what
`${CLAUDE_EFFORT}` receives.

## Gotchas

- **`/plan-it`'s learning phase is deliberately its own, not a reuse of `audit/references/learning-phase.md`.** Five audit runs (2026-09-16) reported the duplication. What they share is only the reply wire contract (`LEARNING_RESULT_START/END`, `LEARNING_LOG_ENTRY`, `TRENDS_BLOCK`); everything else differs on purpose: a different agent (`plan-learning-agent`), a different log (`.claude/plans/learning-log.md`), and none of the audit-specific steps (the run-ledger check and the recurrence-feed check read `skill-runs.jsonl` and `patterns.json`, which plans do not write). Merging the two would put audit's Step 0/0.5 in front of a plan retro that has nothing to check. Suppressed in `.claude/audits/suppressions.json` as a decision; revisit only if plan-it gains a recurrence store.
- **/plan-it plans are executor-grade handoff artifacts.** Template (`plan-it/references/plan-templates.md`) stamps the planned-at commit for a drift check, requires a verify criterion per step, machine-checkable done criteria, an out-of-scope list, and STOP conditions. `/plan-it execute <plan>` runs an executor subagent in an isolated worktree and reviews with an APPROVE/REVISE/BLOCK verdict (max 2 revision rounds, merging stays with the user); `/plan-it reconcile` refreshes the plan backlog against code drift. Detail: `plan-it/references/execute-review.md`.
