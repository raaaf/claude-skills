# Oracle step and targeted mutation run

Detail for `/delegate` Phase 3.5 and the Phase 5 oracle checks. Why: tests written by the same agent
that writes the code inherit its wrong assumptions (14% vs 25% injected-fault detection; 80% of agent
test patches carry weak or no oracle, arXiv 2606.18168). Nothing else in the pipeline measures
whether a new test can fail.

## Contract (Phase 3.5)

Built from the mini-spec, the user's request and public signatures/docblocks only, never from an
implementation body read in Phase 1. Every line carries its source tag `(spec)`, `(request)` or
`(docblock)` so independence is checkable in review. Contents: goal, inputs/outputs, invariants,
error cases, public signatures, and the real setup the project uses (factory states, exemplar test
file, helpers) so the agent does not guess wiring. Bugfix: the bug report and the repro scenario.

Dispatch: `test-writer` with "oracle mode" in the briefing (its own section lists the rules). Output
format and cap in the briefing: files written plus assumptions, under 150 words.

## Red check

Run each oracle file through `bash "$AUDIT_BIN/test-lock.sh" --cmd "<single-file test command>"`.
Accepted: an assertion failure, or for a not-yet-existing unit a missing-symbol error. Parse error or
green: one retry with the error text. Still wrong: fallback to today's flow (the executor writes the
tests, Phase 5 step 4 line-inversion check) and say so in the report. Never BLOCK on the oracle step.

## Locked tests

`oracle-lock.sh snapshot` also hashes `tests/Pest.php`, `tests/TestCase.php`, `phpunit.xml`,
`phpunit.xml.dist` when present. Factories stay editable (residual risk). A locked test that looks
wrong: contract gap, then test-writer amends and the orchestrator re-snapshots; executor error, then
REVISE. A CHANGED report for a setup file another session may have edited: check `git log` for that
file before failing.

## Mutation run (Phase 5, conditional)

Only when `.claude/mutation-targets` (one glob per line, `#` comments) matches a changed file.
`bash "$AUDIT_BIN/mutate.sh" "$PWD" "$BASE_REF" --oracle-files "<oracle files>"` prints
`MUTATE_RESULT=OK|SKIP|TIMEOUT`, `MUTATE_REASON`, `MUTATE_SCORE`, `SURVIVOR=<file>:<line>:<mutator>`
(changed lines +-3, at most 15) and `SURVIVORS_TRUNCATED`. SKIP and TIMEOUT never block. The score is
a finding source, never a target.

Triage each survivor, drop with a one-line reason:
- equivalent (e.g. `true` to `false` on a value only read by `isset`)
- performance-only (retry counts, step budgets)
- log context

Behavior-changing survivors become **behavior statements** ("a second booking overwrites the first
total"), never file:line. Send them to `test-writer` in oracle mode for ONE round. Those tests are
labelled "informed" in the report and snapshotted like the rest (`oracle-lock.sh snapshot` again with
all oracle files). A red informed test on the executor's code: REVISE to the executor (counts against
the 2 rounds); after the fix run `mutate.sh` once more for confirmation.

## Telemetry values

`oracle=used|fallback|skipped`, `mutate=OK|SKIP|TIMEOUT|none`, `survivors=<N after triage>`.
