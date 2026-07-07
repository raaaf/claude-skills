---
name: write-a-skill
disable-model-invocation: true
description: "Create a new Claude Code skill with proper frontmatter, scoped trigger description, progressive disclosure into references/, optional subagent dispatch, and self-learning loop. Use when user wants to write, build, or scaffold a new skill, when adding a workflow that should run via slash command, or when refactoring an existing skill into the canonical structure."
when_to_use: "/write-a-skill, build a new skill, neuen skill schreiben, scaffold skill, refactor skill"
argument-hint: "[skill-name or short description]"
model: opus
effort: high
allowed-tools:
  - Read
  - Write
  - Edit
  - Glob
  - Grep
  - Agent
---

# Write a Skill

Inspired by Matt Pocock's [write-a-skill](https://github.com/mattpocock/skills/blob/main/skills/productivity/write-a-skill/SKILL.md), adapted for our subagent + hooks + self-learning patterns.

## Process

1. **Interview the user** (1-2 rounds, max 3 questions per round, each with a recommended answer):
   - What task/domain does the skill cover?
   - When should the skill trigger? (slash command, natural-language phrases, file types)
   - Does the work split into specialised aspects (security, performance, etc) that should run in parallel? Then we need subagents.
   - Should this skill auto-fix or just report?
   - Is there state across runs (logs, learning, suppressions)? Then we need a learning agent.

2. **Draft the skill** (canonical structure in `references/structure.md`):
   - `SKILL.md` orchestrator, under 500 lines
   - `agents/*.md` per worker if subagents are needed
   - `agents/prompt-template.md` if multiple workers share a prompt
   - `references/*.md` for guidelines, lookup tables, edge-case lists
   - `bin/*.sh` for deterministic logic (parsing, scope detection)

3. **Review with the user**:
   - Description triggers correct?
   - Workflow phases clear?
   - Right subagents, right models per worker?
   - Anything missing or oversized?

4. **Run the checklist** in `references/checklist.md` before declaring done.

## SKILL.md Template

```md
---
name: skill-name
description: "What it does. Use when [specific user triggers]. NOT when [adjacent skill territory]."
when_to_use: "/slash-command, natural language phrase 1, phrase 2"
argument-hint: "[optional context]"
model: opus   # or sonnet, haiku
effort: high             # low, medium, high, xhigh
allowed-tools:
  - Read
  - Edit
  - Bash
  - Agent
---

# Skill Name

## Phase 1: [name]
[Steps with verifications]

## Phase 2: [name]
...
```

## Description Requirements (most important block)

The description is **the only thing the model sees** when picking which skill to load. Get this right or your skill stays cold.

- Max 1024 chars
- Third person, present tense
- First sentence: what it does
- Second sentence: "Use when [specific user triggers]"
- Optional third: "NOT when [adjacent territory]" if confusion likely

**Good:**
> Pre-push code audit. Triage-Agent routes diff to relevant subagents (security, performance, a11y, ...), auto-fixes findings, loops until clean. Use when user runs /audit, says "before pushing", or asks to review changes.

**Bad:**
> Helps with code quality.

## When to Add Subagents

Add a subagent when at least one applies:
- Aspect is independent of others (security vs performance vs a11y) and benefits from parallel dispatch
- Worker needs a different model than orchestrator (e.g. Haiku for pattern-matching, Opus for security reasoning)
- Worker needs an isolated context (no conversation pollution, no parent-context bias)

See `references/subagents.md` for the agents/-folder pattern, prompt-template, model routing.

## When to Split into references/

Split if any applies:
- SKILL.md exceeds 500 lines
- Content has distinct domains (e.g. WordPress-specific vs generic checks)
- Lookup tables or edge-case lists that the orchestrator doesn't always need

Pattern: orchestrator stays small, references/ holds detail. Worker reads `references/X.md` only when needed.

## When to Add Hooks

Add a hook (in user's `~/.claude/settings.json`) when:
- Behavior must run automatically before/after a tool call (PreToolUse / PostToolUse)
- Skill needs to gate `git push` until it has run (PreToolUse on Bash + marker file)
- Skill emits a result that should trigger follow-up automatically (Stop hook)

Hooks must NEVER spawn `claude` subprocesses (recursion + RAM, see `references/hooks-pitfalls.md`).

## When to Add Self-Learning

Add a learning agent (foreground after main flow, never background — silent write failures) when:
- Same false-positive recurs across runs and could be added to suppressions
- Patterns emerge in user overrides that suggest prompt tweaks
- Run logs accumulate and need pattern detection

See `references/self-learning.md` for the standard pattern.

## Review Checklist

Run before declaring done:

- [ ] Description has "Use when..." trigger phrases
- [ ] SKILL.md under 500 lines
- [ ] No time-sensitive info ("as of 2024"...) in the orchestrator
- [ ] Consistent terminology (one name per concept)
- [ ] Concrete examples included
- [ ] References max one level deep (no `references/sub/sub/`)
- [ ] Frontmatter complete: name, description, when_to_use, model, effort, allowed-tools
- [ ] If subagents: each has subagent_type, model, maxTurns, output format
- [ ] If hooks: documented in skill's README section, no `claude` subprocesses
- [ ] If self-learning: foreground dispatch, writes to `.claude/<skill>/learning-log.md`
- [ ] Tested via dry run on a small input

Full checklist with explanations in `references/checklist.md`.
