# Self-Learning Pattern

A learning agent runs after the main flow, reads recent run logs, detects patterns, writes suggestions to a learning-log.md. The user reads suggestions at their own pace. Suggestions never auto-apply.

## When to add a learning agent

- Run logs accumulate (≥5 logs is enough to detect patterns)
- Same false positive recurs across runs and could be added to suppressions
- User overrides a finding repeatedly with the same correction
- Subagent consistently misses or hallucinates the same kind of issue

## Foreground, NOT background

Earlier we tried `run_in_background: true`. It silently fails because background subagents cannot write to `.claude/` (no permission prompt available). Always foreground:

```
Agent(
  subagent_type: general-purpose,
  description: "Learning pass — detect patterns across recent {skill} runs",
  prompt: "Read agents/learning-agent.md and execute."
)
```

The skill blocks for ~30s while learning runs. Worth it for the persistent improvement.

## Standard agents/learning-agent.md outline

```md
# Learning Agent

- **subagent_type:** `general-purpose`
- **model:** `sonnet`
- **maxTurns:** `15`

## Aufgabe

Liest die letzten N Run-Logs aus `.claude/{skill}/` und sucht nach:
1. Recurring False Positives (3+ runs with same finding the user dismissed)
2. Persistent Issues (3+ runs with same finding that recurred)
3. User Overrides (patterns where user kept correcting in the same direction)

## Output

Schreibe Vorschlaege nach `.claude/{skill}/learning-log.md`:

### Suppression-Vorschlag
- Pattern: ...
- Recurrences: 4
- Vorschlag: zu suppressions hinzufuegen

### Guideline-Update-Vorschlag
- Issue: ...
- Recurrences: 3
- Vorschlag: neue Regel in references/X.md

### Prompt-Tweak-Vorschlag
- Worker: 2-security
- Beobachtung: hallucniert oft Y
- Vorschlag: Prompt um "..." ergaenzen

## Verbote

- Nicht selber Files aendern (nur learning-log.md schreiben)
- Nichts auto-applien
- Keine Aenderungen am skill selbst
```

## learning-log.md location

Always per-skill, per-project:
```
{project}/.claude/{skill}/learning-log.md
```

Example:
```
/Users/rafael/Local Sites/events-app/.claude/audit/learning-log.md
```

## Read N recent runs, not all

Logs grow forever. Read only the last 10-20 runs to detect patterns. Older runs are stable; new patterns emerge in recent activity.

## Why suggestions, not auto-apply

Skill rules affect every future run. Silent auto-updates drift the skill away from user intent without review. Always require explicit user approval to apply a suggestion.
