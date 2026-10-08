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
tests, Phase 5 step 4 line-inversion check) and say so in the report. A failed `oracle-lock.sh snapshot`
(exit 1, `ORACLE_SNAPSHOT_MISSING=<file>`: an oracle file does not exist) is the same fallback
(`oracle=fallback`). Never BLOCK on the oracle step.

## Pin mode

A task is in pin mode when the mini-spec adds tests for existing behavior and plans no production change. The red check inverts:
the oracle tests are expected GREEN, because the behavior already exists. A red invariant is a suspected
bug in existing code: STOP and report it to the user with the inputs that fail, never weaken or delete
the test. Phase 4 (executor) is skipped since nothing in production changes. Phase 5 runs
`mutate.sh "$PWD" HEAD --files "<target files>" --oracle-files "<test files>"`: `--files` measures
exactly the pinned production files regardless of the diff (only tests changed, so the diff-based
selection would always SKIP `no-match`) and keeps survivors on any line, not just changed ones. A file
outside `.claude/mutation-targets` is still measured, with `MUTATE_NOTE=not-a-target:<file>`.

## Locked tests

The Bash tool runs zsh, which does not word-split an unquoted variable: pass `oracle-lock.sh snapshot`
the paths written out literally, one argument each. `mutate.sh --oracle-files` and `--files` take one
quoted string and split it themselves.

`oracle-lock.sh snapshot` also hashes `tests/Pest.php`, `tests/TestCase.php`, `phpunit.xml`,
`phpunit.xml.dist` when present. Factories stay editable (residual risk). A locked test that looks
wrong: contract gap, then test-writer amends and the orchestrator re-snapshots; executor error, then
REVISE. A CHANGED report for a setup file another session may have edited: check `git log` for that
file before failing.

## Mutation run (Phase 5, conditional)

Only when `.claude/mutation-targets` (one glob per line, `#` comments, optional `<glob> :: TestA|TestB` test hint) matches a changed file.
`bash "$AUDIT_BIN/mutate.sh" "$PWD" HEAD --oracle-files "<oracle files>"` prints
`MUTATE_RESULT=OK|SKIP|TIMEOUT|ERROR`, `MUTATE_REASON`, `MUTATE_ERROR`, `MUTATE_SCORE`, `SURVIVOR=<file>:<line>:<mutator>`
(changed lines +-3, at most 15) and `SURVIVORS_TRUNCATED`. SKIP, TIMEOUT and ERROR never block: ERROR (`runner-failed`, the runner died without a result) is reported in the result and the run log (`mutate=ERROR`), not retried. Test selection: oracle files plus `tests/` files whose basename starts with the class basename (`MoneyTest.php` for `Money`). Only when that set is empty, files that merely mention the class (Unit first, at most `MUTATE_MAX_TEST_FILES`, default 5) and `MUTATE_NOTE=fallback-test-selection:<n>`; mention that in the report, the selection was heuristic. Mentioning-only discovery picked 15 DB-backed Feature tests once and timed out. Browser test directories are excluded from the test list; `no-mutations` is a SKIP. The score is
a finding source, never a target.

Reasons and notes the orchestrator handles (none blocks):
- ERROR `runner-failed`: the runner died without a result; report it, do not retry.
- ERROR `initial-tests-failed`: the project suite is red; report the failing test named in `MUTATE_ERROR`.
- SKIP `no-tests`, `no-mutations`, `all-mutants-skipped`: report it; for `no-tests` or `all-mutants-skipped` suggest a `::` test hint or a higher `MUTATE_INFECTION_TIMEOUT`.
- NOTE `fallback-test-selection`, `hint-missing`, `skipped-mutants`, `invalid-infection-timeout`: mention in the result report.

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

`oracle=used|fallback|skipped`, `mutate=OK|SKIP|TIMEOUT|ERROR|none`, `survivors=<N after triage>`.
