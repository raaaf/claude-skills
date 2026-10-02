# Audit Log Template

Format for the audit log under `.claude/audits/{datum}_{zeit}-{branch}.md`, written by
`audit/SKILL.md` Phase 4 after the find and fix workflows complete.

```markdown
# Audit: {DATE}: Branch: {BRANCH}

## Scope
- Dimensions: N/13: {list} | Fix scope: {all|none}
- Changed files: list
- HEAD at audit time: {git rev-parse HEAD}
- runId (find): {runId} | runId (fix): {runId}

## Result
- Status: {complete|incomplete} | Gate: {passed|blocked|partial|not_applicable}
- Dimensions completed: {N}/{selected} | Agents dispatched/completed/failed: {A}/{B}/{C}
- Findings verified/unverified: {V}/{U} | Fix verification: {complete|incomplete|not_requested}
- Findings fixed: Critical N / Important N / Minor N
- Critical found/fixed: A/B
- Important found/fixed: C/D
- Cost: {usd|null} USD | Accounting: {complete|unavailable} | Source: {actual source or reason unavailable}
- API turns/tokens: {actual values or unavailable}; never substitute zero for missing accounting

## Pipeline Telemetry
- {dimension}: status {complete|incomplete|skipped} | wall {ms|null} ms | scout {ms|null} ms / {dispatches} dispatch(es) | specialist {ms|null} ms / {dispatches} dispatch(es) | verifier {ms|null} ms / {dispatches} dispatch(es) | refuter {ms|null} ms / {dispatches} dispatch(es)
- A stage that did not run: `not run / 0 dispatches`; a missing clock measurement: `unavailable`, not zero.
- Dimension wall times and stage times overlap because dimensions execute concurrently. Do not sum them as total audit wall time. These counters do not attribute cost, tokens, or provider-internal retries.

## Findings per Dimension
- [Critical][Dimension] file:line: description
- [Important][Dimension] file:line: description

## Fixed Issues
- [Critical|Important|Minor][Dimension] file:line: what was fixed

### Backlog (Minor)
- Added this run: {N} | Removed this run (FIXED or DISCARDED ride-alongs): {N} | Total open: {N}
- (list of added Minors: `- [Minor][Dimension] file:line: description`; write the section even when all counts are 0)

## Discarded
- [Dimension] file:line: reason (refuted, or discard: conflict with {id})
- [Severity][Dimension] file:line: discarded by fixer: {reason}

## Not completed
- {dimension}: incomplete at stage {stage}: {reason}

## Unverified
- [Dimension] file:line: description. Verification inconclusive: {REASON from finding-verifier}

## Open Points
- (regressions from the fix.js regression pass, REJECT fix-verdicts, rejected fixes)

## Clean
Dimension1, Dimension2, ...

## Incidents
- {what happened}: {how many times}
```

**`## Incidents` is mandatory whenever something went wrong outside the normal pipeline flow** (a
dispatch that had to be re-tried, a stale test bundle, a build repeated, a deviation from a hard
rule), and it carries the COUNT, not just the fact. Frequency is the whole signal: one retried
agent is noise, most of a wave is a prompt defect. Write the number even when it is 1.

## Mandatory Field: Findings Fixed

The `Findings fixed: Critical N / Important N / Minor N` line is mandatory in EVERY audit log. The cost and backlog tooling reads this line. Write `0`
explicitly rather than leaving a category out. **Recompute, never hand-tally:** derive every
found/fixed number by counting the itemized finding bullets in the log itself, immediately before
writing the summary.

## Finding-Line Format Is a Parsed Contract, Not a Style Suggestion

Every line under `## Findings per Dimension`, `## Fixed Issues`, `## Discarded` and `## Unverified`
MUST be exactly:

    - [Severity][Dimension] file:line: description

on ONE physical line: severity tag, dimension tag, `file:line`, and the description, in that order,
never wrapped onto a continuation line. The shape is a contract for humans and the minor backlog (one
grep-able line per finding); numbered lists, bold-bullet headers with the description on the next
line and tables are not allowed.

A duplicate (`duplicateOf` from `find.js`) keeps this shape and ends its description with `(duplicate of <dim>/<id>)`.

## Mandatory Tagging Convention

Every finding line carries both tags: severity (`[Critical]`/`[Important]`/`[Minor]`) and
dimension, one of the 14 canonical ids exactly as spelled in `prompt-template.md`'s cross-cutting
rules (`architecture`, `security`, `performance`, `code_quality`, `seo`, `a11y`, `typography`,
`ui_design`, `ux`, `animation`, `docs_sync`, `copy`, `privacy`, `payments`). No aliases (`accessibility`,
`A11Y`, `docs`): free variants broke the top-category metric before (2026-08-06).

## Post-log check (mandatory, before displaying the log in chat)

One mechanical check on the log file just written: **severity tags restricted to
`{Critical, Important, Minor}`** and dimension tags restricted to the 14 canonical ids above. A
non-canonical tag is a bug in the line that wrote it: fix it to the correct one, do not invent a
fourth category.

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
contained in the diff of `origin/$DEFAULT_BRANCH...HEAD` (pushed in the meantime), note in the
log that `/audit` no longer sees pushed commits.
