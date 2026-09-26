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
  agents/*.md           subagent definitions (one per worker)
  references/*.md       on-demand details (TOC if >100 lines)
  guidelines/*.md       content best practices loaded by workers
  bin/*.sh              deterministic helpers (audit only)
  evals/                fixture-based recall measurement (audit only)
```

Key invariants:

- **Orchestrator writes, subagents return.** Subagents cannot write under `.claude/` (hardcoded permission protection, also under `bypassPermissions`; a subagent-side `mode: bypassPermissions` still failed the write). Learning, suppression, log files: structured output → parsed by orchestrator → written by orchestrator.
- **Single source of truth.** `/full-audit` references `../audit/agents/` instead of duplicating. Same for `guidelines/`. Edit once.
- **Frontmatter `model: inherit`** on the orchestrator skills (audit, full-audit, design-audit, plan-it) since 2026-09-03: they run on the session model, the same reasoning `/delegate` documented earlier. `ship` pins `model: sonnet`. Never pinned versions; pin only on Bedrock/Vertex/Foundry.
- **Per-dimension pipeline and platform support detail:** `audit/CLAUDE.md`.

## Commands

Cross-cutting commands only. Per-skill commands (audit/bin/*.sh, screens CLI, capture-screens.sh,
validate-locations.sh, ...) live in that skill's nested `CLAUDE.md` (see Wegweiser).

| Command | Purpose |
|---|---|
| `bash ~/.claude/hooks/sync-skills.sh` | Symlink every skill of both repos into `~/.claude/skills/`, never copies; runs on every session Stop |
| `python3 scripts/usage-report.py --days N [--exclude SESSION_ID]` | Weighted token/cost usage report across recent sessions under `~/.claude/projects/` |
| `bash audit/bin/classify-diff.sh [--paths]` | Emit `DIFF_CLASS=prose\|code` for the current diff. Drives `/audit`'s prose gate and `/ship`'s marker-delta check; fails open to `code` |
| `bash audit/bin/test-lock.sh <cmd...>` | Serialize test runs across parallel fix agents/verifiers (mkdir spinlock under `--git-common-dir`; 15min TTL). Used by `/audit`, `/delegate`, `/ship` |
| `. audit/bin/lib-orchestrator.sh` | Orchestrator prologue every skill sources; values cross Bash blocks only via `orch_state_save`/`orch_state_load`. bash 3.2. Function list: `audit/CLAUDE.md` |
| `bash audit/bin/check-fresh-shell.sh [root]` | Finds Bash blocks calling `orch_*` without sourcing the lib, or reading an unset state variable. Detail: `audit/CLAUDE.md` |
| `bash audit/bin/check-docs-claims.sh [root]` | Mechanical doc-drift check: CLAUDE.md/README.md/`*/SKILL.md` claims verified against disk |
| `bash audit/bin/run-log.sh --start --skill <name>` \| `... --outcome <str> [...]` | Appends one terminal-outcome JSON line to `$HOME/.local/state/claude/skill-runs.jsonl`. Used by `/audit`, `/full-audit`, `/plan-it`, `/design-audit`, `/delegate`, `/ship` |
| `bash audit/bin/run-stats.sh` | Reports run-ledger anomalies; read by `/full-audit`'s and `/ship`'s learning phase |

Test commands (full-suite + filtered variant), incl. `audit/workflows/` and `audit/bin/*.sh`: `audit/CLAUDE.md`.

## Conventions

- **SKILL.md under 500 lines.** If approaching, split into `references/*.md` (one level deep, never nested).
- **Reference files >100 lines need a TOC** at top.
- **YAML `name` is lowercase + hyphens**, no `claude`/`anthropic`. Description in third person, includes both *what* and *when*.
- **Everything is written in English** (since 2026-07-08, full migration): SKILL.md bodies, agents, references, guidelines. German ONLY for: `when_to_use` trigger phrases (they mirror the user's prompt language), runtime user-facing strings inside bash blocks, and deliberate German example content (copywriting guideline).
- **Contract identifiers are never renamed casually.** `ALLE_DATEIEN`, `AKTUELLES_LOG`, `DATEISTRUKTUR` and `ZENTRALE_PATTERNS` are German-named cross-file contracts: learning/challenge agents receive the parameters by these exact names. Renaming needs a coordinated pass over every referencing file. Reviewers: these are NOT English-migration violations.
- **No emojis. No em-dashes in new English prose where avoidable.**
- **Frontmatter for skills** sets `model: inherit` (or `sonnet` for the cheap ones), `effort: high|xhigh` for the four orchestrator skills and `medium` for `/ship` and `/delegate` (neither runs a specialist pipeline), `allowed-tools: [...]`, optional `hooks: { PreToolUse: ... }`.
- **Agent files here are orchestrator-dispatched worker specs, NOT Claude Code subagent definitions, and they have no frontmatter.** Every `<skill>/agents/*.md` opens with an `# Subagent N: Name` heading followed by a bullet list (`- **subagent_type:**`, `- **model:**`, `- **maxTurns:**`); the orchestrator reads those and passes them to the Agent tool. A real subagent definition lives in `.claude/agents/`, uses genuine YAML frontmatter, requires `name` + `description`, and has no `subagent_type` field (its `name` IS the type). Field set and distinction: `docs/references/subagents.md`. A guideline that demands evidence must name a worker role with the matching `tools:` grant; audit-specific detail: `audit/CLAUDE.md`.
- **Skill-frontmatter hooks do not reach subagents.** A `hooks:` block in `SKILL.md` applies to the main session's tool calls only. The worktree-wide git guard therefore also lives in the `hooks:` frontmatter of every registered agent that has Bash (`audit-fix-agent.md`, `audit-fix-verifier.md`, `spec-executor.md`).
- **Hook safety:** never `claude` from inside a Stop/PreToolUse hook (infinite loop). Global hooks (`sync-skills.sh`, `pre-compact.sh`, `auto-format.sh`) live in `~/.claude/hooks/` (symlinked into the private repo, wired up in `~/.claude/settings.json`). Skill-scoped hooks ship inside the skill directory (e.g. `audit/hooks/`); the frontmatter registers one dispatcher that invokes the guards as siblings, aggregating results.

## Registered subagents (`agents/`)

The real Claude Code subagent definitions (YAML frontmatter, `name` = the `subagent_type`), one
per dispatched worker type, symlinked to `~/.claude/agents` (so an edit is live immediately; never
put a non-agent `.md` file there, every `*.md` loads as an agent). Roster: `audit-fix-agent`,
`audit-fix-verifier`, `audit-learning-agent`, `plan-challenger`, `plan-learning-agent`,
`spec-executor`, `design-surface-mapper`, `design-reference-verdict`, `screens-view-discoverer`
(points at `screens/agents/view-discoverer.md`), plus generic `code-reviewer`, `security-auditor`,
`performance-auditor`, `ui-ux-reviewer`, `test-writer`. Each definition only points at the worker
spec inside the skill (`audit/agents/fix-agent.md` etc.); the procedure stays in the skill. The
three agents with Bash (`audit-fix-agent`, `audit-fix-verifier`, `spec-executor`) carry the
worktree-wide git guard in their own `hooks:` frontmatter (skill-frontmatter hooks do not reach
subagents, see Conventions).

## Skill roster

| Skill | Model | Purpose |
|---|---|---|
| `/audit` | inherit (session model) | Pre-push diff audit, per-dimension Workflow pipeline (13 dimensions, plus `payments` on a Stripe repo); one start question replaces the old argument form, every finding incl. Minor is fixed or discarded with a reason |
| `/full-audit` | inherit (session model) | Full codebase audit, same pipeline with `SCOPE=repo`, no push marker |
| `/design-audit` | inherit (session model) | 100% visual dissection of the whole frontend: defects + gated elevation opportunities, report first, then fixes every reported item automatically except suspected prompt-injection notes |
| `/ship` | sonnet | Docs sync + commit + audit gate + test gate + push + deploy + verify |
| `/plan-it` | inherit (session model) | Iterative plan builder, parallel challenges |
| `/delegate` | inherits session model (see `delegate/CLAUDE.md`) | Default implementation flow: the expensive model analyzes and reviews, Sonnet implements |
| `/screens` | inherit (session model) | Screenshot catalog of every view in every applicable state plus App-Store marketing renders; `/delegate` reuses it for before/after proof |

## Effort levels

Set on skill frontmatter or via `CLAUDE_EFFORT`; per-skill detail (audit/full-audit fix-scope
behavior and issue policy, plan-it's challenge/eval table, design-audit's elevation table) lives in
that skill's nested `CLAUDE.md` (see Wegweiser).

## Project-specific overrides

Projects can override globals by adding files to their own `.claude/`:

- `.claude/audit-guidelines.md` — read in `audit` Phase 1, precedence over global `guidelines/*.md`. May declare `perf-measure: <cmd>` or `scope-extensions: <ext> [<ext> ...]` (this repo's own file sets `scope-extensions: md`)
- `.claude/plan-guidelines.md` — read in `plan-it` Phase 0.7, threaded to all challenge agents
- `.claude/ship.md` — `/ship`'s per-project config: `deploy-command:`, `test-command:` (also read by `/audit` Phase 3), `health-check:`; a repo-supplied command surface (see Gotchas)
- `.claude/stripe-golive.md` — Stripe repo only: go-live points answerable only in the Stripe dashboard, templated by the `payments` dimension
- `.claude/audits/learning-log.md`, `.claude/audits/suppressions.json`, `.claude/plans/logs/*.md` — auto-generated per-project state

## Gotchas

Cross-cutting only. Per-skill gotchas live in that skill's nested `CLAUDE.md` (see Wegweiser).

- **Subagents (and forked skills, `context: fork`) run in the BACKGROUND by default; foreground must be requested.** A background result only arrives as a completion notification in a *later* turn, and it keeps every MCP tool but only a reduced built-in set (`Read`, `Grep`, `Glob`, `Bash`, `Edit`, `Write`, `NotebookEdit`, `WebFetch`, `WebSearch`, `TodoWrite`, `Skill`, `ToolSearch`, `SendMessage`, `Artifact`, plus task tools). A dispatch the orchestrator must consume in the same turn needs an explicit `run_in_background: false`/`background: false` (plan-it's challenge panel/eval agent, every learning agent, the `/delegate` executor). Workflow-tool-dispatched audit scouts/specialists/verifiers/fixers are unaffected: the whole run returns as one notification. `AskUserQuestion` is stripped from every subagent regardless. No skill here currently uses `context: fork`.
- **Skill descriptions compete for one budget.** `description` + `when_to_use` are capped at 1,536 chars combined per skill; the model-facing skill listing gets ~1% of the context window, and on overflow Claude Code drops the least-invoked skills' descriptions first. All skills here are under the cap (measured 2026-08-26: max 1,016 chars, `/audit`). Check `skillOverrides` in `~/.claude/settings.json` before concluding a skill "does not trigger": it's a local settings choice, not a repo property.
- **Two marker-hash conventions — never mix them.** `orch_hash_passed`/`orch_hash_progress` in `lib-orchestrator.sh`. `/tmp/claude-audit-passed-*` hashes the cwd WITHOUT trailing newline; `/tmp/claude-audit-in-progress-*` hashes WITH newline. Reading one family with the other convention silently produces a different hash. The passed marker stores the audited tree id (`orch_tree_hash`); `/ship`'s gate requires `orch_marker_matches` plus a 30-minute age, so an edit after the audit no longer ships as audited (a delta that is entirely prose by `classify-diff.sh --paths` is still accepted).
- **`sync-skills.sh` runs on every session Stop**, and every skill under `~/.claude/skills/` is a symlink into one of the two repos, like agents, hooks, CLAUDE.md and settings.json. No copies: an edit under the repo is live in the next session. The hook creates missing links, repairs wrong ones, prunes deleted ones, never touches an entry it doesn't own.
- **Plan mode on `model: opus` switches to Sonnet during execution** under global `opusplan`. Skill frontmatter override (`model: opus`) keeps it on Opus end-to-end.
- **`maxTurns` on agents is a hard limit.** A worker that exceeds it returns whatever it has, including partial findings. Fix-agent needs slack (5 turns minimum); fix-verifier is tighter (3-5 is plenty).
- **`disable-model-invocation` is no longer set on any skill.** Every skill is model-invocable, since the destructive steps have their own gates (PreToolUse push guard, worktree-git guard, fix-verifier stage).
- **Hooks are the one place `${CLAUDE_SKILL_DIR}` does NOT exist.** A hook receives exactly `CLAUDE_PROJECT_DIR`, `CLAUDE_PLUGIN_ROOT`, `CLAUDE_PLUGIN_DATA`; `CLAUDE_PROJECT_DIR` is the *audited* project, not the skill. A skill hook must probe its own install location and **fail open** (`exit 0`) on a missing install. `${CLAUDE_SKILL_DIR}` (used outside hooks, e.g. `audit/SKILL.md`) is the non-hook equivalent that DOES expand to the skill's own directory.
- **Four sites run a repo-supplied command string, only the deploy one asks first.** `audit/SKILL.md`'s `TEST_COMMAND`, `.screens/config.json`'s start/stop/seed/migrate fields (hash-checked, `screens.mjs trust` asks once on change), `perf-measure.sh`'s `perf-measure:` command, and `ship/SKILL.md`'s `test-command:`/`deploy-command:` all execute repo-supplied config. Only `deploy-command:` gets an `AskUserQuestion` on every run, since it is irreversible and production-facing.
- **The run ledger (`$HOME/.local/state/claude/skill-runs.jsonl`) records how a run went, deliberately outside any repo and outside `~/.claude`** (the Bash sandbox denies writes to the latter). `run-log.sh` appends one line per terminal outcome from `/audit`, `/full-audit`, `/plan-it`, `/design-audit`, `/delegate`, `/ship`; `run-stats.sh` surfaces `RUNSTAT` anomalies in the audit log. Two calibrated conditions remain (`gate-never-blocked`, `ledger-stale`); three were deleted after 45 real runs showed they never fired. Do not re-add a deleted condition without new evidence.

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
| `audit/CLAUDE.md` | `/audit` pipeline detail, `audit/bin/*.sh` commands, effort/issue policy, self-audit context |
| `full-audit/CLAUDE.md` | `scope-extensions:` escape hatch, run-scoped marker |
| `design-audit/CLAUDE.md` | Effort table, `validate-locations.sh`, marker/hook detail |
| `plan-it/CLAUDE.md` | Effort table, learning phase, plan template contract |
| `ship/CLAUDE.md` | Docs-sync-before-commit phase |
| `delegate/CLAUDE.md` | `capture-screens.sh`, model-inherit rationale |
| `screens/CLAUDE.md` | CLI and test suite |

## Release process

There isn't one. Push to `main`, Stop hook syncs to `~/.claude/skills/`, next Claude Code session picks up the changes.
