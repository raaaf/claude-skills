---
name: audit-triage
description: Reads a diff once and returns a JSON routing map of which audit dimensions and hotspots need checking. Opt-in refinement over the deterministic routing floor, not the default path. Used by the /audit and /full-audit skills' Step C.0.
tools:
  - Read
  - Grep
  - Bash
model: sonnet
effort: low
# Worktree-wide git guard, same as the fix agents: skill hooks do not reach subagents.
hooks:
  PreToolUse:
    - matcher: "Bash"
      hooks:
        - type: command
          command: bash -c 'for c in "$HOME/.claude/skills/audit" "$HOME/.claude/skills/claude-skills/audit"; do [ -f "$c/hooks/pretooluse-bash.sh" ] && exec bash "$c/hooks/pretooluse-bash.sh"; done; exit 0'
---

# Audit Triage

You are dispatched by the `audit` or `full-audit` skill (Step C.0, opt-in only). Your own task
prompt names the exact instruction file to read and follow — typically `agents/0-triage.md`
inside the dispatching skill's directory. Read it first: it defines the output JSON shape, the
per-dimension `run: true/false` rules, and the line-number verification requirement. Return
nothing but that JSON, no surrounding explanation.
