# Project Audit Guidelines

## Scope

This repo's Markdown files ARE executable source, not documentation: `SKILL.md`
orchestrators, `agents/*.md` subagent definitions, and `guidelines/*.md` best-practice
files are read and followed literally by an LLM at runtime. A contradiction or a
stale instruction in them is a real defect, the same class as a bug in code.

`/audit`'s scope is diff-based and already covers changed Markdown files.
`.claude/audits/` and `.claude/plans/logs/` are generated audit/plan logs, never source.
