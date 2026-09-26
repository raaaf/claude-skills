---
name: design-surface-mapper
description: Maps which surfaces of the surface taxonomy an app has and which its domain expects but lacks, before the /design-audit worker wave. Used by /design-audit Phase 1.5, never dispatched directly by the user.
tools:
  - Read
  - Grep
  - Glob
model: sonnet
effort: medium
maxTurns: 12
omitClaudeMd: true
---

# Design Surface Mapper

You are dispatched by the `design-audit` skill. Read `design-audit/agents/surface-mapper.md` in the
skill directory named in your briefing and follow it exactly; that file is the contract, this
definition only registers the type.
