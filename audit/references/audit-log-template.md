# Audit Log Template

Format for the audit log under `.claude/audits/{datum}_{zeit}-{branch}.md`, written by
`audit/SKILL.md` Phase 4 after the find and fix workflows complete.

```markdown
# Audit — {DATE} — Branch: {BRANCH}

## Scope
- Dimensions: N/13 — {list} | Fix scope: {none|critical|all}
- Changed files: list (or "SCOPE=repo" for /full-audit)
- HEAD at audit time: {git rev-parse HEAD}
- runId (find): {runId} | runId (fix): {runId}

## Result
- Findings fixed: Critical N / Important N / Minor N
- Critical found/fixed: A/B
- Important found/fixed: C/D
- Cost: {usd} USD (run-cost.sh)

## Findings per Dimension
- [Critical][Dimension] file:line — description
- [Important][Dimension] file:line — description

## Fixed Issues
- [Critical|Important|Minor][Dimension] file:line — what was fixed

## Discarded
- [Dimension] file:line — reason (refuted, or discard: conflict with {id})

## Not completed
- {dimension}: incomplete at stage {stage} — {reason}

## Unverified
- [Dimension] file:line: description. Verification inconclusive: {REASON from finding-verifier}

## Open Points
- (regressions from the fix.js regression pass, REJECT fix-verdicts, rejected fixes)

## Clean
Dimension1, Dimension2, ...

## Incidents
- {what happened} — {how many times}
```

**`## Incidents` is mandatory whenever something went wrong outside the normal pipeline flow** (a
dispatch that had to be re-tried, a stale test bundle, a build repeated, a deviation from a hard
rule), and it carries the COUNT, not just the fact. Frequency is the whole signal: one retried
agent is noise, most of a wave is a prompt defect. Write the number even when it is 1.

## Mandatory Field: Findings Fixed

The `Findings fixed: Critical N / Important N / Minor N` line is mandatory in EVERY audit log,
including `/full-audit`. Trend computation in the learning log reads this line. Write `0`
explicitly rather than leaving a category out. **Recompute, never hand-tally:** derive every
found/fixed number by counting the itemized finding bullets in the log itself, immediately before
writing the summary.

## Mandatory Tagging Convention

Every finding line carries both tags: severity (`[Critical]`/`[Important]`/`[Minor]`) and
dimension, one of the 13 canonical ids exactly as spelled in `prompt-template.md`'s cross-cutting
rules (`architecture`, `security`, `performance`, `code_quality`, `seo`, `a11y`, `typography`,
`ui_design`, `ux`, `animation`, `docs_sync`, `copy`, `privacy`). No aliases (`accessibility`,
`A11Y`, `docs`) — free variants broke the top-category metric before (2026-08-06).

## Post-log check (mandatory, before displaying the log in chat)

Two mechanical checks on the log file just written:

1. **Severity tags restricted to `{Critical, Important, Minor}`** and dimension tags restricted to
   the 13 canonical ids above. A non-canonical tag is a bug in the line that wrote it — fix it to
   the correct one, do not invent a fourth category.
2. **If any `CONFIRMED` verdict occurred this run, `patterns.json` must be newer than the log file
   about to be written.** Compare mtimes; if the store is older or missing, the per-verdict
   `patterns-store.sh recur` calls did not run. Write one line under `## Incidents` instead of
   silently back-filling.

## Display in chat (mandatory)

After the log is written, load its complete content via the Read tool
and output it as a markdown code block in chat:

```
Audit log: {LOGFILE}

---
{content of the log file}
---
```

## Unverified Section

Holds `UNCERTAIN` verdicts from the finding-verifier, one line per finding: dimension, file:line,
description, and the verifier's `reason`. Omit the heading entirely when nothing came back
`UNCERTAIN`. A Critical `UNCERTAIN` additionally becomes an Open Point.

## Follow-Up Audit Logic

On the next `/audit` run: if commits show up between `{letzter-audit-HEAD}..HEAD` that are **not**
contained in the diff of `origin/$DEFAULT_BRANCH...HEAD` (pushed in the meantime), recommend
`/full-audit` — `/audit` no longer sees pushed commits.
