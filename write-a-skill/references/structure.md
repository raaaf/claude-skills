# Canonical Skill Structure

```
skill-name/
├── SKILL.md                     # Orchestrator (max 120 lines)
├── agents/                      # Optional: parallel workers
│   ├── 0-triage.md             # Routes scope to relevant workers
│   ├── 1-aspect-a.md           # Worker, single aspect
│   ├── 2-aspect-b.md
│   ├── fix-agent.md            # Optional: applies fixes
│   ├── learning-agent.md       # Optional: pattern detection across runs
│   └── prompt-template.md      # Shared worker prompt with placeholders
├── references/                  # Progressive disclosure
│   ├── checklist.md
│   ├── guidelines/             # Optional sub-folder for grouped refs
│   └── lookup-table.md
├── bin/                         # Optional: deterministic Bash
│   ├── collect-scope.sh
│   └── parse-output.sh
├── guidelines/                  # Optional: domain rules workers load
│   ├── security.md
│   └── performance.md
└── README.md                    # Optional: human-facing doc
```

## What goes where

| Component | Goes in | Reasoning |
|---|---|---|
| Workflow phases | SKILL.md | Read every invocation |
| Phase-specific edge-case lists | references/ | Read on demand |
| Per-aspect rules (security, perf) | guidelines/ | Worker loads only relevant one |
| Worker definitions | agents/ | Each is a separate dispatch |
| Shared worker prompt | agents/prompt-template.md | One source of truth |
| Deterministic logic (parsing, scope detection) | bin/ | Bash, not LLM judgment |
| Setup/teardown for the skill itself | README.md | Human-facing, not LLM-facing |

## Naming conventions

- Worker files: `{number}-{aspect}.md` (e.g. `1-architecture.md`, `2-security.md`). Number gives sort order in dispatch.
- Bash scripts in `bin/`: kebab-case, `.sh` extension, executable.
- References: descriptive name, no numbers (e.g. `security-guidelines.md`, not `ref-1.md`).

## Sharing across skills

If two skills share workers (e.g. `audit` and `full-audit` both use the same 10 workers): the second skill should NOT duplicate. It references the first via a path variable.

Example from full-audit/SKILL.md:
```
Agent definitions: {AUDIT_AGENTS}/*.md
```
Where `AUDIT_AGENTS` resolves to `../audit/agents/` at runtime via Bash detection.
