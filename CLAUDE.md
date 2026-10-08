# claude-skills

Repo of Claude Code skills. Each skill is a slash command implemented in Markdown + Bash, no runtime.

## Stack

- Markdown + YAML frontmatter (skill orchestrator)
- Bash for deterministic logic (`audit/bin/`, `~/.claude/hooks/`)
- Claude Code 2.1.218+ frontmatter features: `model`, `effort`, `allowed-tools`, `disallowed-tools`, `maxTurns`, `context: fork` + `agent` + `background`. Full field reference (verified against the official docs, August 2026): `docs/references/frontmatter.md`
- No dependencies — no npm, no composer, no venv

## Architecture

Each skill follows the same shape:

```
skill-name/
  SKILL.md              orchestrator (under 500 lines)
  agents/*.md           worker specs (plan-it, screens)
  references/*.md       on-demand details (TOC if >100 lines)
  guidelines/*.md       content best practices loaded by workers (not audit)
  bin/*.sh              deterministic helpers (audit only)
```

Key invariants:

- **Orchestrator writes, subagents return.** Subagents cannot write under `.claude/` (hardcoded permission protection, also under `bypassPermissions`; a subagent-side `mode: bypassPermissions` still failed the write). Suppression and log files: structured output → parsed by orchestrator → written by orchestrator.
- **Frontmatter `model: inherit`** on the orchestrator skills (audit, plan-it) since 2026-09-03: they run on the session model, the same reasoning `/delegate` documented earlier. `ship` pins `model: sonnet`. Never pinned versions; pin only on Bedrock/Vertex/Foundry.
- **`/audit` architecture (PR review on the built-in `/code-review`) and platform support detail:** `audit/CLAUDE.md`.

## Commands

Cross-cutting commands only. Per-skill commands (audit/bin/*.sh, screens CLI, ...) live in that skill's nested `CLAUDE.md` (see Wegweiser).

| Command | Purpose |
|---|---|
| `bash ~/.claude/hooks/sync-skills.sh` | Symlink every skill of both repos into `~/.claude/skills/`, never copies; runs on every session Stop |
| `python3 scripts/usage-report.py --days N [--exclude SESSION_ID]` | Weighted token/cost usage report across recent sessions under `~/.claude/projects/` |
| `bash audit/bin/classify-diff.sh [--paths]` | Emit `DIFF_CLASS=prose\|code` for the current diff. Drives `/audit`'s prose gate and `/ship`'s marker-delta check; fails open to `code` |
| `bash audit/bin/test-lock.sh <cmd...>` | Serialize test runs across parallel fix agents/verifiers (mkdir spinlock under `--git-common-dir`; 15min TTL). Used by `/audit`, `/delegate`, `/ship` and the `deploy <app> test` gate (`~/.local/bin/deploy`), so worktrees and agents sharing a test DB serialize with it |
| `bash audit/bin/test-gate.sh slot-acquire <app> \| slot-release <pid> \| run <test-cmd> <file-cmd>` | Helper of `deploy <app> test`: one machine-wide slot for full suites (`~/.local/state/claude/full-suite.slot`, waiters give up after 900 s) and a run wrapper that reruns red browser files once, logging flakes to `~/.local/state/claude/test-flakes.jsonl`. Detail: `audit/CLAUDE.md` |
| `. audit/bin/lib-orchestrator.sh` | Orchestrator prologue every skill sources; values cross Bash blocks only via `orch_state_save`/`orch_state_load`. bash 3.2. Function list: `audit/CLAUDE.md` |
| `bash audit/bin/check-fresh-shell.sh [root]` | Finds Bash blocks calling `orch_*` without sourcing the lib, or reading an unset state variable. Detail: `audit/CLAUDE.md` |
| `bash audit/bin/check-docs-claims.sh [root]` | Mechanical doc-drift check: CLAUDE.md/README.md/`*/SKILL.md` claims verified against disk |
| `bash audit/bin/run-log.sh --start --skill <name>` \| `... --outcome <str> [...]` | Appends one terminal-outcome JSON line to `$HOME/.local/state/claude/skill-runs.jsonl`. Used by `/audit`, `/plan-it`, `/delegate`, `/ship` |

Test commands (every `audit/bin/*.test.sh` and `audit/hooks/*.test.sh` is a single script, no wrapper): `audit/CLAUDE.md`.

## Conventions

- **SKILL.md under 500 lines.** If approaching, split into `references/*.md` (one level deep, never nested).
- **Reference files >100 lines need a TOC** at top.
- **YAML `name` is lowercase + hyphens**, no `claude`/`anthropic`. Description in third person, includes both *what* and *when*.
- **Everything is written in English** (since 2026-07-08, full migration): SKILL.md bodies, agents, references, guidelines. German ONLY for: `when_to_use` trigger phrases (they mirror the user's prompt language), runtime user-facing strings inside bash blocks, and deliberate German example content (copywriting guideline).
- **Contract identifiers are never renamed casually.** `ALLE_DATEIEN`, `AKTUELLES_LOG`, `DATEISTRUKTUR` and `ZENTRALE_PATTERNS` are German-named cross-file contracts: challenge agents receive the parameters by these exact names. Renaming needs a coordinated pass over every referencing file. Reviewers: these are NOT English-migration violations.
- **No emojis. No em-dashes in new English prose where avoidable.**
- **Frontmatter for skills** sets `model: inherit` (or `sonnet` for the cheap ones), `effort: high|xhigh` for `/plan-it` and `medium` for `/audit`, `/ship`, `/delegate` and `/screens` (none runs a specialist pipeline), `allowed-tools: [...]`, optional `hooks: { PreToolUse: ... }`.
- **Agent files here are orchestrator-dispatched worker specs, NOT Claude Code subagent definitions, and they have no frontmatter.** Every `<skill>/agents/*.md` opens with an `# Subagent N: Name` heading followed by a bullet list (`- **subagent_type:**`, `- **model:**`, `- **maxTurns:**`); the orchestrator reads those and passes them to the Agent tool. A real subagent definition lives in `.claude/agents/`, uses genuine YAML frontmatter, requires `name` + `description`, and has no `subagent_type` field (its `name` IS the type). Field set and distinction: `docs/references/subagents.md`. A guideline that demands evidence must name a worker role with the matching `tools:` grant; audit-specific detail: `audit/CLAUDE.md`.
- **Skill-frontmatter hooks do not reach subagents.** A `hooks:` block in `SKILL.md` applies to the main session's tool calls only. The worktree-wide git guard therefore also lives in the `hooks:` frontmatter of every registered agent that has Bash (`spec-executor.md`).
- **Hook safety:** never `claude` from inside a Stop/PreToolUse hook (infinite loop). Global hooks (`sync-skills.sh`, `pre-compact.sh`, `auto-format.sh`) live in `~/.claude/hooks/` (symlinked into the private repo, wired up in `~/.claude/settings.json`). Skill-scoped hooks ship inside the skill directory (e.g. `audit/hooks/`); the frontmatter registers one dispatcher that invokes the guards as siblings, aggregating results.

## Registered subagents (`agents/`)

The real Claude Code subagent definitions (YAML frontmatter, `name` = the `subagent_type`), one
per dispatched worker type, symlinked to `~/.claude/agents` (so an edit is live immediately; never
put a non-agent `.md` file there, every `*.md` loads as an agent). Roster: `plan-challenger`,
`spec-executor`, `screens-view-discoverer`
(points at `screens/agents/view-discoverer.md`), plus generic `code-reviewer`, `security-auditor`,
`fact-checker`, `ui-ux-reviewer`, `test-writer`. Where a definition points at a worker
spec inside a skill, the procedure stays in the skill. The
agent with Bash (`spec-executor`) carries the
worktree-wide git guard in its own `hooks:` frontmatter (skill-frontmatter hooks do not reach
subagents, see Conventions).

## Skill roster

| Skill | Model | Purpose |
|---|---|---|
| `/audit` | inherit (session model) | Pre-push PR review: deterministic pre-checks, the built-in `/code-review high` in a review worktree, a checklist agent on sensitive paths, orchestrator triage, one fix executor, tests, push marker |
| `/ship` | sonnet | Docs sync + commit + audit gate + test gate + push + deploy + verify |
| `/plan-it` | inherit (session model) | Iterative plan builder, parallel challenges |
| `/delegate` | inherits session model (see `delegate/CLAUDE.md`) | Default implementation flow: the expensive model analyzes and reviews, Sonnet implements |
| `/screens` | inherit (session model) | Screenshot catalog of every view in every applicable state plus App-Store marketing renders |
| `/store-assets` | inherit (session model) | App Store / Play Store screenshot stills from a project's own app screens + config: real device bezels, fixed headline/device grid, two-phone hero composition |

## Effort levels

Set on skill frontmatter or via `CLAUDE_EFFORT`; per-skill detail (plan-it's challenge/eval table) lives in
that skill's nested `CLAUDE.md` (see Wegweiser).

## Project-specific overrides

Projects can override globals by adding files to their own `.claude/`:

- `.claude/audit-guidelines.md` — project rules `audit` reads during triage (Phase 3)
- `.claude/plan-guidelines.md` — read in `plan-it` Phase 0.7, threaded to all challenge agents
- `.claude/ship.md` — `/ship`'s per-project config: `deploy-command:`, `test-command:` (also read by `/audit` Phase 3), `health-check:`; a repo-supplied command surface (see Gotchas)
- `.claude/mutation-targets`: one glob per line (`#` comments) of files `/delegate` Phase 5 mutation-tests when a diff touches them (`audit/bin/mutate.sh`); no file, no mutation run
- `.claude/audits/suppressions.json` — per-project accepted tradeoffs, maintained by hand

## Gotchas

Cross-cutting only. Per-skill gotchas live in that skill's nested `CLAUDE.md` (see Wegweiser).

- **Subagents (and forked skills, `context: fork`) run in the BACKGROUND by default; foreground must be requested.** A background result only arrives as a completion notification in a *later* turn, and it keeps every MCP tool but only a reduced built-in set (`Read`, `Grep`, `Glob`, `Bash`, `Edit`, `Write`, `NotebookEdit`, `WebFetch`, `WebSearch`, `TodoWrite`, `Skill`, `ToolSearch`, `SendMessage`, `Artifact`, plus task tools). A dispatch the orchestrator must consume in the same turn needs an explicit `run_in_background: false`/`background: false` (plan-it's challenge panel/eval agent, the `/delegate` executor). Workflow-tool-dispatched audit scouts/specialists/verifiers/fixers are unaffected: the whole run returns as one notification. `AskUserQuestion` is stripped from every subagent regardless. No skill here currently uses `context: fork`.
- **Skill descriptions compete for one budget.** `description` + `when_to_use` are capped at 1,536 chars combined per skill; the model-facing skill listing gets ~1% of the context window, and on overflow Claude Code drops the least-invoked skills' descriptions first. `/audit` measured 851 chars on 2026-10-03. Check `skillOverrides` in `~/.claude/settings.json` before concluding a skill "does not trigger": it's a local settings choice, not a repo property.
- **Two marker-hash conventions — never mix them.** `orch_hash_passed`/`orch_hash_progress` in `lib-orchestrator.sh`. `/tmp/claude-audit-passed-*` hashes the cwd WITHOUT trailing newline; `/tmp/claude-audit-in-progress-*` hashes WITH newline. Reading one family with the other convention silently produces a different hash. The passed marker stores the audited tree id (`orch_tree_hash`); `/ship`'s gate requires `orch_marker_matches` plus a 30-minute age, so an edit after the audit no longer ships as audited (a delta that is entirely prose by `classify-diff.sh --paths` is still accepted).
- **`sync-skills.sh` runs on every session Stop**, and every skill under `~/.claude/skills/` is a symlink into one of the two repos, like agents, hooks, CLAUDE.md and settings.json. No copies: an edit under the repo is live in the next session. The hook creates missing links, repairs wrong ones, prunes deleted ones, never touches an entry it doesn't own.
- **Plan mode on `model: opus` switches to Sonnet during execution** under global `opusplan`. Skill frontmatter override (`model: opus`) keeps it on Opus end-to-end.
- **`maxTurns` on agents is a hard limit.** A worker that exceeds it returns whatever it has, including partial findings. Give a fixing worker slack (5 turns minimum); a reviewer needs 3-5.
- **`disable-model-invocation` is no longer set on any skill.** Every skill is model-invocable, since the destructive steps have their own gates (PreToolUse push guard, worktree-git guard, orchestrator triage).
- **Hooks are the one place `${CLAUDE_SKILL_DIR}` does NOT exist.** A hook receives exactly `CLAUDE_PROJECT_DIR`, `CLAUDE_PLUGIN_ROOT`, `CLAUDE_PLUGIN_DATA`; `CLAUDE_PROJECT_DIR` is the *audited* project, not the skill. A skill hook must probe its own install location and **fail open** (`exit 0`) on a missing install. `${CLAUDE_SKILL_DIR}` (used outside hooks, e.g. `audit/SKILL.md`) is the non-hook equivalent that DOES expand to the skill's own directory.
- **Three sites run a repo-supplied command string, only the deploy one asks first.** `audit/SKILL.md`'s `TEST_COMMAND`, `.screens/config.json`'s start/stop/seed/migrate fields (hash-checked, `screens.mjs trust` asks once on change), and `ship/SKILL.md`'s `test-command:`/`deploy-command:` all execute repo-supplied config. Only `deploy-command:` gets an `AskUserQuestion` on every run, since it is irreversible and production-facing.
- **The run ledger (`$HOME/.local/state/claude/skill-runs.jsonl`) records how a run went, deliberately outside any repo and outside `~/.claude`** (the Bash sandbox denies writes to the latter). `run-log.sh` appends one line per terminal outcome from `/audit`, `/plan-it`, `/delegate`, `/ship`; the ledger is read for cost measurement. The anomaly report (`run-stats.sh`) was removed 2026-10-02 together with the learning phase that read it.

## Adding a new skill

Follow this minimum:

1. Create `new-skill/SKILL.md` with frontmatter (`name`, `description`, `model`, `effort`, `allowed-tools`).
2. Add `agents/` for any subagents you dispatch.
3. Add `references/` for content over 100 lines.
4. Add `guidelines/` for opinionated best practices the agents should follow.
5. Run `bash ~/.claude/hooks/sync-skills.sh` to deploy locally.
6. Update root `README.md` to list the new skill.

## Wegweiser (nested context files)

Rules bound to one skill's own directory live in that skill's `CLAUDE.md`, loaded when a file
there is read; everything else stays here.

| File | Covers |
|---|---|
| `audit/CLAUDE.md` | `/audit` architecture and evidence, `audit/bin/*.sh` commands, gotchas, self-audit context |
| `plan-it/CLAUDE.md` | Effort table, plan template contract |
| `ship/CLAUDE.md` | Docs-sync-before-commit phase |
| `delegate/CLAUDE.md` | model-inherit rationale |
| `screens/CLAUDE.md` | CLI and test suite |
| `store-assets/CLAUDE.md` | Render/validate commands, bezel/status-bar cache rebuild, reviewed-hash and no-hardcoded-brand-value gotchas |

## Release process

There isn't one. Push to `main`, Stop hook syncs to `~/.claude/skills/`, next Claude Code session picks up the changes.
