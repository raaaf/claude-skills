# /delegate internals

Rules bound to `/delegate`'s own pipeline. Cross-cutting rules (background subagents, model
choice) live in the root `CLAUDE.md`.

## Commands

| Command | Purpose |
|---|---|
| `bash audit/bin/capture-screens.sh --label before\|after [--url URL \| --ios] [--name slug]` | Before/after screenshots for a visual change, no project dependency: headless Chrome for web, `simctl` for a booted simulator. Writes to `<repo>/.claude/screenshots/<label>/` and adds that path to `.gitignore` when nothing covers it yet. Emits `SCREENSHOT <path>` per file plus `CAPTURE_RESULT=OK (N)\|SKIP (reason)\|FAIL (reason)`, and always exits 0. Called by `/delegate` Phase 3.5 and Phase 5; not an MCP call on purpose, so a subagent or a plain shell can run it |

## Gotchas

- **`/delegate` omits `model:` on purpose.** It inherits the session model so analysis + review run on the strongest model available (currently Opus 5.5); an explicit `model:` pin would fix the skill to that model instead of tracking whatever the session runs on. The executor is always dispatched as sonnet; the orchestrator has no Edit/Write in allowed-tools (advisor-only, enforced by tooling). Large/architectural tasks get an AskUserQuestion gate offering /plan-it first.
