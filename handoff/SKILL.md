---
name: handoff
disable-model-invocation: true
disallowed-tools:
  - AskUserQuestion
description: |
  Compacts the current session into a handoff document for a fresh agent or a new session.
  Use when context is running out, before switching to a different branch, or when passing
  ongoing work to another session. Saves to /tmp (not committed). Redacts secrets.
when_to_use: "/handoff, context running out, new session, pass to fresh agent, compact session, running out of context"
argument-hint: "[optional: focus area for the handoff]"
model: sonnet
effort: low
allowed-tools:
  - Read
  - Write
  - Bash
  - Glob
---

# Handoff

Compact the current session into a self-contained handoff document.

## Phase 0: Gather Context

Collect state from the environment:

```bash
# Repo + branch
git rev-parse --show-toplevel 2>/dev/null
git branch --show-current 2>/dev/null
git log --oneline -10 2>/dev/null
git status --short 2>/dev/null
git diff --stat HEAD 2>/dev/null
```

Check for skill run logs:
```bash
ls .claude/audits/ 2>/dev/null | tail -3
ls .claude/plans/ 2>/dev/null | tail -3
```

## Phase 1: Write Handoff Document

Output path:
```
/tmp/handoff-{repo-name}-{branch}-{YYYYMMDD-HHMMSS}.md
```

Document structure:

```markdown
# Handoff: {repo-name} / {branch}

Generated: {timestamp}

## What Was Being Worked On

{1-3 sentence summary of the current task or feature}

## Done This Session

{bullet list of what was actually completed, with file:line refs for key changes}

## Commits Made

{git log --oneline output from Phase 0}

## Current State

{git status --short output}
{Any uncommitted changes and why}

## What Comes Next

{bullet list of next steps, in order}

## Open Questions / Blockers

{anything unresolved that the next agent needs to know}

## Key Files

{up to 10 most relevant files for the current task, with one-line context each}

## Suggested Skills

{which /skills to use for the next steps, e.g. /audit before pushing, /plan-it if scope is unclear}

## Project Context

- Framework: {detected from package.json / composer.json / etc.}
- Branch: {branch}
- HEAD: {short SHA}
- Working directory: {repo root}
```

**Redaction rules:**
- API keys, tokens, passwords: replace with `[REDACTED]`
- Patterns to redact: strings matching `sk-`, `Bearer `, `password=`, `secret=`, `token=`,
  `API_KEY`, `PRIVATE_KEY`, anything resembling a 32+ char hex or base64 string
- File paths to `.env` files: mention them by name, do not copy their contents

## Phase 2: Display

Read the written file and print its full contents in a code block.

Then print:
```
Handoff saved: /tmp/handoff-{filename}.md

To resume in a fresh session:
  claude --resume /tmp/handoff-{filename}.md
  (or paste the file contents as the opening message)
```
