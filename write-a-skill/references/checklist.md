# Skill Review Checklist (Detailed)

Run this before declaring a skill done. Each item is a hard gate, not a suggestion.

## Frontmatter

- [ ] `name` matches the directory name (e.g. dir `audit/` -> `name: audit`)
- [ ] `description` + `when_to_use` under 1,536 chars combined (hard cap), key use case in the first sentence
- [ ] Every declared `argument-hint` is actually bound in the body. Without `$ARGUMENTS` (or a declared named argument) in the content, Claude Code only appends `ARGUMENTS: <value>` at the very end and the body never refers to it
- [ ] Free-text arguments (commit message, task description, focus area) use `$ARGUMENTS`, not named or indexed arguments: those bind shell-quoted positions, so an unquoted multi-word value loses everything after the first token
- [ ] No shell positionals (`$1`, `${1:-default}`) standing in for the skill argument inside bash blocks. `$1` is the *second* skill argument, and under the Bash tool it is empty
- [ ] `description` follows pattern: "What it does. Use when [trigger]. [Optional: NOT when X]."
- [ ] `when_to_use` lists slash command + 2-4 natural-language phrases (German + English if relevant)
- [ ] `argument-hint` filled if the skill takes args, otherwise omit
- [ ] `disable-model-invocation` omitted (the default: skills are model-invocable). Set it only when an auto-trigger would spend money or be unrecoverable; never on a scheduled skill
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
- [ ] `model` set per task (Sonnet for anything producing findings, Opus only for genuine reasoning hardness like security; Haiku only for mechanically consumed output, never for findings — see `references/subagents.md`, "Model routing")
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

- [ ] Foreground dispatch, spelled out as `run_in_background: false`: omitting it backgrounds the agent (default since Claude Code v2.1.198), and a background agent both can't write to `.claude/` and returns too late for the orchestrator to write for it
- [ ] Writes to `.claude/<skill>/learning-log.md`
- [ ] Suggestions, not auto-apply
- [ ] Reads recent N runs, not entire history each time

## Final Smoke Test

- [ ] Run the skill on a tiny realistic input
- [ ] Check that all phases execute, no missing variables, no broken references
- [ ] Check that the output format is what the orchestrator promises
- [ ] If the skill modifies files: verify modifications and clean up the test
