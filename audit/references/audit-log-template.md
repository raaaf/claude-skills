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
- Findings fixed: Critical N / Important N / Minor N
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

## Mandatory Field: Findings Fixed

The `Findings fixed: Critical N / Important N / Minor N` line is mandatory in EVERY audit log, including `/full-audit` batch runs. Trend computation in the learning log reads this line; when a batch run omits it, the trend silently mixes counted and estimated runs and stops being comparable across audit types. Write `0` explicitly rather than leaving a category out.

**Recompute, never hand-tally:** derive every found/fixed number by counting the itemized finding bullets in the log itself (e.g. `grep -c '^\- .*\[Important\]'` per section), immediately before writing the summary. A hand-carried tally goes stale the moment a round adds or discards findings — one run reported 11 Important while its own list held 13.

## Mandatory Tagging Convention

Every finding line — in the round-1 chat output AND in the log — carries BOTH tags: severity (`[Critical]` / `[Important]` / `[Minor]`) and dimension (`[Security]`, `[Architecture]`, ...). A domain tag alone is not enough; trend metrics in the learning log count by severity and turn into estimates when the severity tag is missing.

## Follow-Up Audit Logic

On the next audit run: if commits show up between `{letzter-audit-HEAD}..HEAD` that are **not** contained in the diff of `origin/$DEFAULT_BRANCH...HEAD` (because they were pushed in the meantime), recommend `/full-audit` — the `audit` skill no longer sees pushed commits.
