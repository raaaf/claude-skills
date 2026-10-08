# /delegate internals

Rules bound to `/delegate`'s own pipeline. Cross-cutting rules (background subagents, model
choice) live in the root `CLAUDE.md`.

## Gotchas

- **`/delegate` omits `model:` on purpose.** It inherits the session model so analysis + review run on the strongest model available (currently Opus 5.5); an explicit `model:` pin would fix the skill to that model instead of tracking whatever the session runs on. The executor is always dispatched as sonnet; the orchestrator has no Edit/Write in allowed-tools (advisor-only, enforced by tooling). Large/architectural tasks get an AskUserQuestion gate offering /plan-it first.
- **test-writer owns the oracle, the executor never edits locked files (Phase 3.5, 2026-10-08).** For a `[logic test]` step the tests come from `test-writer` in oracle mode, written from a contract and red before the executor starts. Their files plus `tests/Pest.php`, `tests/TestCase.php`, `phpunit.xml(.dist)` are hash-locked (`audit/bin/oracle-lock.sh`); Phase 5 fails on `CHANGED`, and on `NONE` while `ORACLE_EXPECTED=1`. Worktree mode (`--worktree`) has no oracle in v1: a worktree only holds committed files. Detail: `references/oracle.md`.
