# Audit Log Template

Format for the audit log under `.claude/audits/YYYY-MM-DD_HHMMSS-<branch>.md`, written by the
orchestrator in `audit/SKILL.md` Phase 5. The filename is a contract (`git branch --show-current`
is empty on a detached HEAD, the block falls back to the short SHA); do not rename by hand.

```markdown
# Audit: {DATE}: Branch: {BRANCH}

## Scope
- Base: {BASE_REF} | HEAD at audit time: {git rev-parse HEAD}
- Changed files: {N} (list) | Diff class: {code|prose}
- Reviews run: {code_review, sensitive | code_review | none (prose)}

## Pre-checks
- {script}: {result code}, one line each for every check that is not OK/SKIP

## Result
- Gate: {passed|blocked|partial|not_applicable}
- Findings: Critical {N} / Important {N} / Minor {N} | Fixed {N} | Discarded {N} | Open {N}
- Tests: {command + result | no test command | not run (no code change)}
- Kosten dieses Laufs: {AUDIT_COST_USD} USD (ca. {AUDIT_COST_WEEK_PCT} % der Woche), Woche ca. {WEEK_PCT_EST} % (lokale Schätzung über die Sessions auf diesem Mac; genauer Wert: /usage)

## Findings
- [Critical][code_review] file:line: description

## Fixed
- [Important][sensitive] file:line: what was fixed

## Discarded
- [Important][code_review] file:line: reason (documented tradeoff, not reproducible, ...)

## Minor, not fixed
- [Minor][code_review] file:line: description

## Not completed
- {review}: {reason}

## Open Points
- (open Critical/Important, red tests after the REVISE round, a secret or silenced check from the fix)
```

## Finding-line format is a contract

Every line under `## Findings`, `## Fixed`, `## Discarded` and `## Minor, not fixed` is exactly

    - [Severity][source] file:line: description

on ONE physical line, never wrapped, no numbered list, no table. Severity is `Critical`, `Important`
or `Minor`. Source is `code_review`, `sensitive` or `pre-check`. Humans grep this shape.

Never reproduce a secret value or surrounding file content: logs under `.claude/audits/` may be
committed to a public repo. Name `file:line` and the type.

## Counts

Recompute every number by counting the itemized bullets in the log, immediately before writing the
summary; never hand-tally. Write `0` explicitly.

## Display in chat

After writing, Read the log and output it as a markdown block in chat, preceded by `Audit log: {LOGFILE}`.
