# claude-skills

Repo of Claude Code skills. Each skill is a slash command implemented in Markdown + Bash, no runtime.

## Stack

- Markdown + YAML frontmatter (skill orchestrator)
- Bash for deterministic logic (`audit/bin/`, `~/.claude/hooks/`)
- Claude Code 2.1.150+ frontmatter features: `model`, `effort`, `allowed-tools`, `maxTurns`
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

- **Orchestrator writes, subagents return.** Subagents cannot write under `.claude/` (hardcoded permission protection, also under `bypassPermissions`). Learning, suppression, log files: structured output → parsed by orchestrator → written by orchestrator.
- **Single source of truth.** `/full-audit` references `../audit/agents/` instead of duplicating. Same for `guidelines/`. Edit once.
- **Frontmatter `model: opus`**, not pinned versions. Resolves to latest Opus on Anthropic API. Pin only on Bedrock/Vertex/Foundry.
- **Worker model routing.** Haiku for pattern-matching (0-triage, 4-code-quality, 5-seo, 7-typography, 8-ui-design, 10-animation). Sonnet for reasoning (1-arch, 3-performance, 6-a11y, 9-ux, 11-docs-sync, 12-copy, fix-agent, fix-verifier, learning-agent). Opus for 2-security (exploit reasoning).
- **Platform support.** `detect-framework.sh` emits `PLATFORM=web|native|cross` (laravel/nextjs/nuxt/django vs ios/android vs react-native/flutter). Native projects: workers 2/3/6/7/8/9 additionally read `guidelines/native-mobile.md`; Swift/Kotlin/Dart count as frontend files; `check-i18n-keys.sh` handles `.lproj` and `values-*/strings.xml`.

## Commands

| Command | Purpose |
|---|---|
| `bash ~/.claude/hooks/sync-skills.sh` | Copy + zip skills to `~/.claude/skills/` after edits |
| `bash audit/bin/verify-agents.sh audit/agents` | Verify all 17 required agent files present |
| `bash audit/bin/check-i18n-keys.sh [root]` | Deterministic i18n key-set diff across locales |
| `bash audit/evals/run-evals.sh` | Run eval suite against fixtures (recall + false-positive count) |
| `echo "..." \| bash audit/bin/normalize-suppression.sh` | Test the semantic dedup key for a suppression |

## Conventions

- **SKILL.md under 500 lines.** If approaching, split into `references/*.md` (one level deep, never nested).
- **Reference files >100 lines need a TOC** at top.
- **YAML `name` is lowercase + hyphens**, no `claude`/`anthropic`. Description in third person, includes both *what* and *when*.
- **No emojis. No em-dashes.** German prose uses real umlauts (ä, ö, ü, ß) only in user-facing content; agent definitions use ae/oe/ue/ss to avoid encoding edge cases.
- **Frontmatter for skills** sets `model: opus`, `effort: high|xhigh`, `allowed-tools: [...]`, optional `hooks: { PreToolUse: ... }`.
- **Frontmatter for agents** sets `subagent_type`, `model`, `maxTurns`. No system instructions in frontmatter — those live in the body.
- **Finding output cap** is 50 words, only `file:line` refs, no code snippets. Enforced in `audit/agents/prompt-template.md`.
- **Hook safety:** never `claude` from inside a Stop/PreToolUse hook (would spawn an infinite loop). All hooks live in `~/.claude/hooks/`, not the repo.

## Effort levels (set on skill frontmatter or via `CLAUDE_EFFORT`)

| Level | /audit | /full-audit | /plan-it |
|---|---|---|---|
| low | 1 round | 1 round/batch, no Cross-Ref | 3 challenges, no eval, no learning |
| medium | 2 rounds | 2 rounds/batch | 4 challenges, no eval |
| high / xhigh (default) | 3 rounds, fix Minor | 3 rounds/batch, Cross-Ref always | 5 challenges, full eval |

## Project-specific overrides

Projects can override globals by adding files to their own `.claude/`:

- `.claude/audit-guidelines.md` — read in `audit` Phase 1, takes precedence over global `guidelines/*.md`
- `.claude/plan-guidelines.md` — read in `plan-it` Phase 0.7, threaded to all challenge agents
- `.claude/audits/learning-log.md` — auto-generated per-project audit history
- `.claude/audits/suppressions.json` — auto-generated dismissed-finding list
- `.claude/plans/logs/*.md` — auto-generated per-plan logs

## Gotchas

- **`.claude/` write block applies in foreground too.** Earlier learning agents tried `mode: bypassPermissions` and still failed. The fix is always: subagent returns structured output, orchestrator parses + writes.
- **Pre-push marker and `git push` must be separate Bash calls.** The PreToolUse hook scans the command string for `git push` and blocks before any marker write in the same call would execute. See `audit/SKILL.md` Phase 4.
- **`sync-skills.sh` only runs in the claude-skills working directory.** Edits to `~/.claude/skills/audit/SKILL.md` directly are not synced anywhere — always edit in this repo and let the Stop hook copy.
- **Plan mode on `model: opus` switches to Sonnet during execution** if you use `opusplan` globally. Skill frontmatter override (`model: opus`) keeps it on Opus end-to-end.
- **`maxTurns` on agents is a hard limit.** A worker that exceeds it returns whatever it has, including partial findings. Triage and fix-agent need slack (5 turns minimum); fix-verifier is tighter (3-5 is plenty).
- **Worker output never includes code snippets.** Findings reference `file:line` only. This is by design — keeps consolidation cheap and prevents the worker from being a code generator.
- **Stop-hook `additionalContext` does NOT block.** Verified against the hooks docs (June 2026): `hookSpecificOutput.additionalContext` on Stop/SubagentStop lets the stop proceed and only injects context. The audit loop needs blocking to force the next round — `exit 2` in `~/.claude/hooks/audit-loop.sh` stays. Don't "modernize" this.

## Adding a new skill

Use `/write-a-skill` if available, or follow this minimum:

1. Create `new-skill/SKILL.md` with frontmatter (`name`, `description`, `model`, `effort`, `allowed-tools`).
2. Add `agents/` for any subagents you dispatch.
3. Add `references/` for content over 100 lines.
4. Add `guidelines/` for opinionated best practices the agents should follow.
5. Run `bash ~/.claude/hooks/sync-skills.sh` to deploy locally.
6. Update root `README.md` to list the new skill.

## Adding a 2026 best-practice section to an existing guideline

Edit `audit/guidelines/{name}.md`. Append a new Roman-numeral section (e.g. `## XVI. New Topic (2026)`). Keep the file under 500 lines. Don't rewrite existing content — additive only unless something is genuinely wrong.

## Release process

There isn't one. Push to `main`, Stop hook syncs to `~/.claude/skills/`, next Claude Code session picks up the changes.
