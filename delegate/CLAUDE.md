# /delegate internals

Rules bound to `/delegate`'s own pipeline. Cross-cutting rules (background subagents, model
choice) live in the root `CLAUDE.md`.

## Gotchas

- **`/delegate` omits `model:` on purpose.** It inherits the session model so analysis + review run on the strongest model available (currently Opus 5.5); an explicit `model:` pin would fix the skill to that model instead of tracking whatever the session runs on. The executor is always dispatched as sonnet; the orchestrator has no Edit/Write in allowed-tools (advisor-only, enforced by tooling). Large/architectural tasks get an AskUserQuestion gate offering /plan-it first.
