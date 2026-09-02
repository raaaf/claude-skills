# Subagents Pattern

When the work splits into independent aspects that benefit from parallel dispatch.

## Decision: when to add subagents

Add a subagent for an aspect when at least one applies:
- The aspect is independent and runs in parallel with other aspects
- The aspect needs a different model than the orchestrator
- The aspect needs an isolated context (no parent-conversation pollution)

Do NOT add a subagent for sequential single-purpose work that is small. Direct execution in the orchestrator is cheaper and clearer.

## Two different things are both called "an agent file"

Know which one you are writing before you copy a template. They are not interchangeable.

| | Orchestrator-dispatched worker spec | Claude Code subagent definition |
|---|---|---|
| Lives in | `<skill>/agents/*.md` | `.claude/agents/*.md` |
| Read by | the skill orchestrator, as plain Markdown | Claude Code itself, as YAML frontmatter |
| Header format | Markdown bullet list (below) | `---` YAML frontmatter |
| Who dispatches | the orchestrator, passing these values to the Agent tool | Claude Code, on `subagent_type: <name>` |
| `subagent_type` | a field you write, naming which built-in agent to dispatch | NOT a field; the file's `name` IS the type |

Everything in this repo is the first kind. That is deliberate: the orchestrator stays in control of
dispatch, and a worker spec can carry prose the Agent tool has no field for. But do not describe it
as "frontmatter" and do not expect Claude Code to auto-register it.

### Claude Code subagent definition (`.claude/agents/*.md`)

Real YAML frontmatter, `name` and `description` required. Full supported field set:
`name`, `description`, `tools`, `disallowedTools`, `model`, `permissionMode`, `maxTurns`, `skills`,
`mcpServers`, `hooks`, `memory`, `background`, `effort`, `isolation`, `color`, `initialPrompt`.

Two worth knowing about, both easy to miss:
- `skills:` preloads a skill's FULL content into the subagent at startup, not just its description.
  An alternative to instructing a worker to read guideline files itself.
- `memory:` (`user` | `project` | `local`) gives the subagent persistent memory across sessions,
  under `.claude/agent-memory/<agent>/` for `project`. Note this cuts against the
  "orchestrator writes, subagents return" rule this repo follows, so it is a real architectural
  choice, not a free upgrade.

Field list verified against `code.claude.com/docs/en/sub-agents`, August 2026.

### Orchestrator-dispatched worker spec (`<skill>/agents/*.md`)

```md
# Subagent N: Name

- **subagent_type:** `general-purpose`     # or specific: code-reviewer, security-auditor, etc.
- **model:** `sonnet`                       # haiku | sonnet | opus
- **maxTurns:** `10`

## Focus
[One paragraph: what this worker checks]

## Full Guidelines
[Optional: link to guidelines/X.md]

## Checklist
[Optional: short bullet list of what to check]

## Skip When
[Optional: when this worker should be skipped]
```

Section headers are English (matches the migrated audit/plan-it agents: Focus, Skip When, Project-Specific Context). The literal reply sentinel "Keine Findings." is a cross-file contract and stays as-is.

## Triage pattern

If you have 5+ workers, add a triage agent (`0-triage.md`) that runs once before the workers. Triage decides which workers actually run for this input. Saves dispatching irrelevant workers.

Triage output format (JSON):
```json
{
  "summary": "1-2 line description of input",
  "relevance": {
    "aspect_a": {"run": true, "hotspots": ["file.ts:10-25"], "reason": "..."},
    "aspect_b": {"run": false, "reason": "no relevant changes"}
  }
}
```

## Worker dispatch pattern

In the SKILL.md orchestrator phase that dispatches workers:
- Pass ONLY: triage summary, hotspots for that worker, file list (for orientation)
- Do NOT pass the full diff / full codebase to every worker (token waste)
- Workers read additional context via Read-tool on demand (max 5 files per run)

## Prompt template

If 3+ workers share the same prompt structure, extract a single `agents/prompt-template.md` with placeholders. Each worker dispatch fills the placeholders.

## Foreground or background

Dispatched subagents run in the **background by default**. That is the
right default for a parallel worker fan-out, but it changes two things a skill can depend on:

- A background subagent's result arrives as a completion notification in a **later turn**. Any step
  whose output the orchestrator must parse and act on within the same turn (learning pass, status
  line, push marker) has to dispatch with `run_in_background: false`.
- A background subagent keeps every MCP tool but only a reduced set of built-ins: `Read`, `Grep`,
  `Glob`, `Bash`, `Edit`, `Write`, `NotebookEdit`, `WebFetch`, `WebSearch`, `TodoWrite`, `Skill`,
  `ToolSearch`, `SendMessage`, `Artifact`, plus a few task tools. Everything else is stripped even
  when the agent definition lists it, so the same worker can resolve to different tools in the
  foreground and the background.

`AskUserQuestion` is removed from **every** subagent, foreground or background. A worker that needs
a decision returns it as structured output and lets the orchestrator ask.

## Model routing

- Everything that reports findings someone will act on: `sonnet` (default)
- OWASP / security with deep reasoning: `opus`
- Always: orchestrator on `opus` if it dispatches multiple workers and needs to consolidate

**Do not route a finding-producing worker to `haiku` without measuring first.** The obvious split
(cheap model for "pattern-matching" dimensions like typography, SEO, code quality) is what this repo
ran until 2026-08-11, and it lost money rather than saving it: in the full-audit of 2026-08-06 a
`haiku` code-quality batch produced five findings the hallucination validator discarded as
impossible (a parameter that does not exist, an unreachable control-flow state, a misread language
idiom), while `sonnet` workers in the same run produced zero. A wrong finding is not free. It costs
a verifier round, and one that survives verification costs a whole fix wave, which is far more than
the token difference. `haiku` is still reasonable for work whose output is consumed mechanically
rather than acted on, such as classification into a fixed set of labels.

## Output format discipline

Every worker output must be strict, not free prose:
- Cap length per finding ("max 50 words per item")
- Structured format (table, fixed line format, or JSON)
- Confidence label per finding (high | medium | low)
- "No findings? Reply exactly 'Keine Findings.'" — avoids parsing edge cases

For finder-style workers, split coverage from filtering: tell the worker its job is to report
everything it has evidence for, including low-severity and uncertain items, and let a separate
verification stage rank and discard. Current models follow a "only report what really matters"
instruction faithfully enough that the finder silently drops real findings, and a dropped finding
can't be recovered downstream. The severity and confidence labels are what carry the doubt.
