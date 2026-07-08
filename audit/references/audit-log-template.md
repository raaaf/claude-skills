# Audit Log Template

Format for the audit log under `.claude/audits/{datum}_{zeit}-{branch}.md`.

```markdown
# Audit — {DATE} — Branch: {BRANCH}

## Scope
- Commits since origin/{base}: N
- Changed files: list
- HEAD at audit time: {git rev-parse HEAD}

## Result
- Rounds: N/2
- Critical found/fixed: A/B
- Important found/fixed: C/D

## Fixed Issues
- [Type] file:line — what was fixed

## Manual Test Plan
- (test plan steps, if visual files were changed)

## Open Points
- (if any)

## Clean
Dimension1, Dimension2
```

## Follow-Up Audit Logic

On the next audit run: if commits show up between `{letzter-audit-HEAD}..HEAD` that are **not** contained in the diff of `origin/$DEFAULT_BRANCH...HEAD` (because they were pushed in the meantime), recommend `/full-audit` — the `audit` skill no longer sees pushed commits.
