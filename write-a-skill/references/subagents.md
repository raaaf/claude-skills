# Subagents Pattern

When the work splits into independent aspects that benefit from parallel dispatch.

## Decision: when to add subagents

Add a subagent for an aspect when at least one applies:
- The aspect is independent and runs in parallel with other aspects
- The aspect needs a different model than the orchestrator
- The aspect needs an isolated context (no parent-conversation pollution)

Do NOT add a subagent for sequential single-purpose work that is small. Direct execution in the orchestrator is cheaper and clearer.

## Worker file pattern

```md
# Subagent N: Name

- **subagent_type:** `general-purpose`     # or specific: code-reviewer, security-auditor, etc.
- **model:** `haiku`                        # haiku | sonnet | opus
- **maxTurns:** `10`

## Fokus
[One paragraph: what this worker checks]

## Vollstaendige Guidelines
[Optional: link to guidelines/X.md]

## Pruef-Checkliste
[Optional: short bullet list of what to check]

## Skip wenn
[Optional: when this worker should be skipped]
```

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

## Model routing

- Pattern-matching, classification, simple typography/SEO: `haiku`
- Code review, reasoning over control flow, WCAG semantics: `sonnet` (default)
- OWASP / security with deep reasoning: `opus`
- Always: orchestrator on `opus` if it dispatches multiple workers and needs to consolidate

## Output format discipline

Every worker output must be strict, not free prose:
- Cap length per finding ("max 50 words per item")
- Structured format (table, fixed line format, or JSON)
- Confidence label per finding (high | medium | low)
- "No findings? Reply exactly 'Keine Findings.'" — avoids parsing edge cases
