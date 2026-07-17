# Audit Log Template

Format for the audit log under `.claude/audits/{datum}_{zeit}-{branch}.md`.

```markdown
# Audit — {DATE} — Branch: {BRANCH}

## Scope
- Commits since origin/{base}: N
- Changed files: list
- HEAD at audit time: {git rev-parse HEAD}

## Result
- Rounds: N/{MAX_RUNDEN}
- Critical found/fixed: A/B
- Important found/fixed: C/D

## Findings per Round
- Runde 1: [Critical][Dimension] file:line — description
- Runde 1: [Important][Dimension] file:line — description
- Runde 2: ...

## Fixed Issues
- [Critical|Important|Minor][Dimension] file:line — what was fixed

## Manual Test Plan
- (test plan steps, if visual files were changed)

## Open Points
- (if any)

## Clean
Dimension1, Dimension2
```

## Mandatory Tagging Convention

Every finding line — in the round-1 chat output AND in the log — carries BOTH tags: severity (`[Critical]` / `[Important]` / `[Minor]`) and dimension (`[Security]`, `[Architecture]`, ...). A domain tag alone is not enough; trend metrics in the learning log count by severity and turn into estimates when the severity tag is missing.

## Follow-Up Audit Logic

On the next audit run: if commits show up between `{letzter-audit-HEAD}..HEAD` that are **not** contained in the diff of `origin/$DEFAULT_BRANCH...HEAD` (because they were pushed in the meantime), recommend `/full-audit` — the `audit` skill no longer sees pushed commits.
