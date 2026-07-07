# Skill Review Checklist (Detailed)

Run this before declaring a skill done. Each item is a hard gate, not a suggestion.

## Frontmatter

- [ ] `name` matches the directory name (e.g. dir `audit/` -> `name: audit`)
- [ ] `description` under 1024 chars
- [ ] `description` follows pattern: "What it does. Use when [trigger]. [Optional: NOT when X]."
- [ ] `when_to_use` lists slash command + 2-4 natural-language phrases (German + English if relevant)
- [ ] `argument-hint` filled if the skill takes args, otherwise omit
- [ ] `disable-model-invocation: true` set (required for destructive/long-running skills; omit only if auto-triggering is explicitly wanted)
- [ ] `model` explicit: `opus`, `sonnet`, or `haiku` (aliases resolve to latest on Anthropic API; pin full IDs only on Bedrock/Vertex/Foundry). Never inherit silently.
- [ ] `effort` explicit: `low` | `medium` | `high` | `xhigh`
- [ ] `allowed-tools` minimal: only what the skill genuinely needs

## SKILL.md Body

- [ ] Under 500 lines (split into `references/` if approaching)
- [ ] Phases numbered and named (Phase 0/1/2/...)
- [ ] Each phase has a single clear goal
- [ ] No time-sensitive claims ("as of 2024", "currently...", version numbers without context)
- [ ] One concept = one name. No synonyms drifting through the file.
- [ ] Concrete examples included where they help (good vs bad pattern)
- [ ] No prose walls. Use lists, tables, code blocks.

## Description Quality (Smoke Test)

Read the description aloud. Can you tell:
- [ ] What this skill does (1-sentence answer)?
- [ ] When you would invoke it vs adjacent skills?
- [ ] What kind of input/output to expect?

If any answer is "no" or "maybe", rewrite.

## Subagents (if used)

Per agents/*.md file:
- [ ] `subagent_type` named (general-purpose or specific)
- [ ] `model` set per task (Haiku for pattern-matching, Sonnet for reasoning, Opus only for genuine reasoning hardness like security)
- [ ] `maxTurns` realistic
- [ ] Focus is one aspect, not "do everything"
- [ ] Output format is strict (table, JSON-schema, or fixed-line-format), not free prose
- [ ] Length-cap enforced ("max 50 words per finding" or similar)
- [ ] No `UNIFIED_DIFF` or full-codebase-dump in prompt; pass only relevant slices

## References (if split into references/)

- [ ] Max one level deep (`references/X.md`, never `references/sub/X.md`)
- [ ] Each file is self-contained (worker can read it without re-reading SKILL.md)
- [ ] Filename describes content (`security-guidelines.md`, not `notes-2.md`)

## Hooks (if registered)

- [ ] Documented in skill README section
- [ ] Hook script is in repo, not anonymous in settings.json
- [ ] Hook NEVER spawns `claude` as a subprocess (recursion + RAM crash, see hooks-pitfalls.md)
- [ ] Anti-recursion guard if PreToolUse/Stop (`stop_hook_active` check)
- [ ] Disable-switch via env var (e.g. `SKILL_X_DISABLE=1`)

## Self-Learning (if learning agent)

- [ ] Foreground dispatch (`run_in_background: false` or omit) — background can't write to `.claude/`
- [ ] Writes to `.claude/<skill>/learning-log.md`
- [ ] Suggestions, not auto-apply
- [ ] Reads recent N runs, not entire history each time

## Final Smoke Test

- [ ] Run the skill on a tiny realistic input
- [ ] Check that all phases execute, no missing variables, no broken references
- [ ] Check that the output format is what the orchestrator promises
- [ ] If the skill modifies files: verify modifications and clean up the test
