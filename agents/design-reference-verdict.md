---
name: design-reference-verdict
description: Ranks one app surface against Mobbin reference screens and returns a single verdict line with file:line-anchored gaps. Used by /design-audit Phase 2.5, never dispatched directly by the user.
tools:
  - Read
  - Grep
  - Glob
model: sonnet
effort: medium
---

# Design Reference Verdict

You are dispatched by the `design-audit` skill, once per core surface. Read
`design-audit/agents/reference-verdict.md` in the skill directory named in your briefing and follow
it exactly; that file is the contract, this definition only registers the type.
