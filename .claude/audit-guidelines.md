# Project Audit Guidelines

## Scope

This repo's Markdown files ARE executable source, not documentation: `SKILL.md`
orchestrators, `agents/*.md` subagent definitions, and `guidelines/*.md` best-practice
files are read and followed literally by an LLM at runtime. A contradiction or a
stale instruction in them is a real defect, the same class as a bug in code.

```
scope-extensions: md
```

This adds `.md` to `/full-audit`'s fixed source-extension glob (see
`full-audit/references/scope-context-batching.md`). `.claude/audits/` and
`.claude/plans/logs/` stay excluded regardless (generated audit/plan logs, never
source). `/audit`'s scope is diff-based and already covers changed Markdown files
without this line.
