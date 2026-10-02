# /plan-it internals

Rules bound to `/plan-it`'s own pipeline. Cross-cutting rules (background subagents, model
choice, run ledger) live in the root `CLAUDE.md`.

## Effort levels

| Level | /plan-it (default `high`) |
|---|---|
| low | architecture + risk only, no eval |
| medium | architecture + risk always, design/product/simplicity by selection rule, no eval |
| high / xhigh (default) | same selection, full eval |

Selection rule (SKILL.md Phase 3): design only for UI/UX surfaces; product only when the feature is new to users or scope is undecided; simplicity only when scope is still open, its cuts are "zur Diskussion" and never auto-applied. The orchestrator runs the git drift check (challengers have no Bash) and passes `DRIFT_OUTPUT` into each briefing.

`/plan-it` carries `effort: high` in its frontmatter, and per the dual-use rule that value is what
`${CLAUDE_EFFORT}` receives.

## Gotchas

- **/plan-it plans are executor-grade handoff artifacts.** Template (`plan-it/references/plan-templates.md`) stamps the planned-at commit for a drift check, requires a verify criterion per step, machine-checkable done criteria, an out-of-scope list, and STOP conditions, and ends in a `## Delegate spec` section (/delegate mini-spec format) that `/delegate <plan file>` reuses; the body before it stays at about 1,500 words. `/plan-it execute <plan>` runs an executor subagent in an isolated worktree and reviews with an APPROVE/REVISE/BLOCK verdict (max 2 revision rounds, merging stays with the user); `/plan-it reconcile` refreshes the plan backlog against code drift. Detail: `plan-it/references/execute-review.md`.
