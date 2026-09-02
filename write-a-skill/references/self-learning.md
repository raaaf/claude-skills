# Self-Learning Pattern

A learning agent runs after the main flow, reads recent run logs, detects patterns, writes suggestions to a learning-log.md. The user reads suggestions at their own pace. Suggestions never auto-apply.

## When to add a learning agent

- Run logs accumulate (≥5 logs is enough to detect patterns)
- Same false positive recurs across runs and could be added to suppressions
- User overrides a finding repeatedly with the same correction
- Subagent consistently misses or hallucinates the same kind of issue

## Foreground, NOT background

`run_in_background: true` silently fails because background subagents cannot write to `.claude/` (no permission prompt available), and their result only arrives as a completion notification in a later turn, by which time the orchestrator that was supposed to write for them is done.

Background is the *default* when the dispatch doesn't say otherwise, so foreground has to be requested explicitly; omitting the flag backgrounds the agent:

```
Agent(
  subagent_type: general-purpose,
  description: "Learning pass — detect patterns across recent {skill} runs",
  prompt: "Read agents/learning-agent.md and execute.",
  run_in_background: false
)
```

The skill blocks for ~30s while learning runs. Worth it for the persistent improvement.

## Standard agents/learning-agent.md outline

```md
# Learning Agent

- **subagent_type:** `general-purpose`
- **model:** `sonnet`
- **maxTurns:** `15`

## Task

Read the last N run logs from `.claude/{skill}/` and look for:
1. Recurring false positives (3+ runs with the same finding the user dismissed)
2. Persistent issues (3+ runs with the same finding that recurred)
3. User overrides (patterns where the user kept correcting in the same direction)

## Output

Write suggestions to `.claude/{skill}/learning-log.md`:

### Suppression suggestion
- Pattern: ...
- Recurrences: 4
- Suggestion: add to suppressions

### Guideline-update suggestion
- Issue: ...
- Recurrences: 3
- Suggestion: new rule in references/X.md

### Prompt-tweak suggestion
- Worker: 2-security
- Observation: often hallucinates Y
- Suggestion: extend the prompt with "..."

## Prohibitions

- Never edit files yourself (only write learning-log.md)
- Never auto-apply anything
- No changes to the skill itself
```

## learning-log.md location

Always per-skill, per-project:
```
{project}/.claude/{skill}/learning-log.md
```

Example:
```
/Users/rafael/Local Sites/events-app/.claude/audits/learning-log.md
```

## Read N recent runs, not all

Logs grow forever. Read only the last 10-20 runs to detect patterns. Older runs are stable; new patterns emerge in recent activity.

## Why suggestions, not auto-apply

Skill rules affect every future run. Silent auto-updates drift the skill away from user intent without review. Always require explicit user approval to apply a suggestion.
