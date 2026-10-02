# /plan-it internals

Rules bound to `/plan-it`'s own pipeline. Cross-cutting rules (background subagents, model
choice, run ledger) live in the root `CLAUDE.md`.

## Effort levels

| Level | /plan-it (default `high`) |
|---|---|
| low | 3 challenges, no eval |
| medium | 4 challenges, no eval |
| high / xhigh (default) | 5 challenges, full eval |

`/plan-it` carries `effort: high` in its frontmatter, and per the dual-use rule that value is what
`${CLAUDE_EFFORT}` receives.

## Gotchas

- **/plan-it plans are executor-grade handoff artifacts.** Template (`plan-it/references/plan-templates.md`) stamps the planned-at commit for a drift check, requires a verify criterion per step, machine-checkable done criteria, an out-of-scope list, and STOP conditions. `/plan-it execute <plan>` runs an executor subagent in an isolated worktree and reviews with an APPROVE/REVISE/BLOCK verdict (max 2 revision rounds, merging stays with the user); `/plan-it reconcile` refreshes the plan backlog against code drift. Detail: `plan-it/references/execute-review.md`.
