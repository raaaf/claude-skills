# /delegate: tests from an independent oracle

> **Executor instruction:** Follow step by step, check each verify
> criterion before moving on. If a STOP condition occurs: stop and
> report, do not improvise.
>
> **Drift check (first):** `git diff --stat e2e8009..HEAD -- delegate/ agents/test-writer.md agents/spec-executor.md plan-it/references/execute-review.md audit/bin/ audit/CLAUDE.md CLAUDE.md audit/bin/fixtures/mutate/`
> If an in-scope file has changed since the plan was created: reconcile the
> current state against the live code; on a mismatch, that is a STOP condition.

## Meta
- Planned at: commit `e2e8009`, 2026-10-08
- Challengers: ran architecture + risk (always-on). Skipped design (no UI surface), product (internal tooling, scope set by the user in three interview answers), simplicity (scope decided explicitly in the interview). Drift check: ran by the orchestrator, no drift.

## Problem
`/delegate` lets one Sonnet executor write the code and the tests for it in the same context. Tests
written after seeing the implementation inherit its wrong assumptions (14% vs 25% injected-fault
detection; 80% of agent test patches carry weak or no oracle, arXiv 2606.18168). Measured on
2026-10-08: zeit tax splitters 42-81% mutation score; events SecretSantaMatchService 65% before and
72% after property tests (the fixture log is the 72% run); an events test asserted a nonexistent
attribute (`giver_guest_id`) and could never fail. Nothing in the pipeline measures whether a new
test can fail.

## Goal
1. In working-tree mode, every /delegate run whose mini-spec asks for a logic test gets that test
   from a separate agent that sees the contract, not the implementation, and the test is red before
   the executor starts. If that fails twice, the run falls back to today's flow and says so.
2. The executor cannot change those tests or the shared test setup unnoticed: Phase 5 fails on it.
3. When the diff touches a file listed in the project's `.claude/mutation-targets`, Phase 5 runs one
   targeted mutation run and turns behavior-changing survivors on changed lines into one extra test
   round. The score is a finding source, never a target.
4. Bounded cost: one extra Sonnet agent per test-bearing run; mutation only on listed targets with
   one total time budget; at most 15 survivors triaged.

## Decisions (interview)
- Oracle step runs when the mini-spec has a logic test step (bugfix repro or new logic).
- Mutation targets: explicit per-project file `.claude/mutation-targets` (one glob per line, `#`
  comments). No heuristic.
- Mutation stacks v1: Pest and PHPUnit via Infection. TS and Swift get the oracle step only.

## Solution

### A. Oracle step (new /delegate Phase 3.5, working-tree mode only)
Skipped with a one-line note when: no logic test step, `--no-oracle` given, or `--worktree` mode
(a worktree only holds committed files; v1 does not transfer uncommitted oracle files, see Known
Costs). `/plan-it execute` keeps its current flow.
A "logic test step" is a mini-spec step whose verify names a new or changed test for a calculation,
parsing, validation, date, status or matching rule, or a bugfix repro (test-writer's own "What to
Test" list). Rendering, wiring and mock-call tests never qualify.
The orchestrator writes a **contract** into the briefing from the mini-spec, the user's request and
public signatures/docblocks only, never from the implementation body it read in Phase 1: goal,
inputs/outputs, invariants, error cases, public signatures, and the real setup the project uses
(factory states, exemplar test file, helpers), so the agent does not guess wiring. Every contract
line carries its source (`spec`, `request`, `docblock`) so independence is checkable in review.
For a bugfix: the bug report and the repro scenario.
It dispatches `test-writer` in **oracle mode**: do not read the target unit's body (signatures and
docblocks only), write the tests, run the project formatter on them, report assumptions. When the
contract states invariants: seeded property loops, seed in every failure message, RNG reset in
`afterEach`/teardown, a comment on what a seed reproduces (lesson from the 2026-10-08 audit, a fixed
`mt_srand` leaked into later tests). Oracle mode suspends the agent's line-inversion verify step
(there is no implementation to invert yet).
The orchestrator runs the test file through `test-lock.sh` and checks: red by an assertion failure,
or for a not-yet-existing unit by a missing-symbol error. Parse error or green → one retry with the
error; still wrong → fall back to today's flow (executor writes tests, Phase 5 step 4 line-inversion
check) and note it in the report. Never BLOCK on the oracle step.
On success: `oracle-lock.sh snapshot --run <RUN_ID> <files...>` and `orch_state_save ORACLE_RUN_ID ORACLE_EXPECTED=1`.

### B. Locked tests
The snapshot covers the oracle files plus shared test setup when present: `tests/Pest.php`,
`tests/TestCase.php`, `phpunit.xml`, `phpunit.xml.dist`. The executor briefing lists the oracle
files as read-only and adds a STOP condition: "a locked test looks wrong: stop and report why". The
orchestrator decides: contract gap → test-writer amends and re-snapshots; executor error → REVISE.
Phase 5 runs `oracle-lock.sh check --run <RUN_ID>`: `CHANGED` → review fail; `NONE` while
`ORACLE_EXPECTED=1` → review fail (lost snapshot is not a pass). Phase 5 also runs the existing
`check-silencing.sh` (catches `skip`/`markTestSkipped` workarounds). Content hashes catch edits made
through Bash too, so no PreToolUse hook. Factories stay editable (residual risk, Known Costs).
State lives under `git rev-parse --git-common-dir` keyed by run id (two sessions in one tree do not
collide); `oracle-lock.sh clear --run <RUN_ID>` runs at every terminal verdict.

### C. Targeted mutation run (Phase 5, conditional)
`audit/bin/mutate.sh <root> <base-ref>` takes the changed files from `git diff <base-ref>` and
intersects them with `.claude/mutation-targets`. No file or no match → `MUTATE_RESULT=SKIP`.
- Runner per PHP file: Pest when `vendor/bin/pest` exists and `composer.json` requires
  `pestphp/pest`; else Infection when `phpunit.xml(.dist)` exists and `$INFECTION_PHAR` (default
  `~/.local/share/claude/infection.phar`) is present; else `SKIP reason=no-runner`. Coverage driver
  required (`php -m` lists pcov or xdebug), else `SKIP reason=no-coverage`.
- Pest: `pest --mutate --covered-only --class=<FQCN> <test files>` (verified 2026-10-08: covered-only
  still reports UNTESTED mutants on covered code; `--everything` hangs). FQCN from the `namespace`
  line plus basename. Test files: oracle files plus `tests/` files that grep the class basename;
  empty list → SKIP (an empty filter runs the whole suite).
- Infection: temp config in `$TMPDIR`, `--filter=<file>`, `--only-covering-test-cases`,
  `--order-by=default`, `--threads=1`, text log.
- Time: ONE total budget `MUTATE_BUDGET` (default 600 s) across all files. `mutate.sh` resolves
  `timeout` or `gtimeout` itself (same preference order as `check-outdated.sh:23-26`, but NOT its
  fail-open behavior): neither present → `SKIP reason=no-timeout`, never an unbounded run. The
  timeout sits inside the `test-lock.sh` command and kills the whole process group, so no orphaned
  CPU-bound child keeps the lock (deploy-gate waiters give up after 960 s). Budget hit →
  `MUTATE_RESULT=TIMEOUT` plus the survivors printed so far.
- Output: `MUTATE_RESULT=OK|SKIP|TIMEOUT`, `MUTATE_SCORE=<relpath>:<pct>`,
  `SURVIVOR=<relpath>:<line>:<mutator>` only for lines changed in the diff ±3, at most 15, then
  `SURVIVORS_TRUNCATED=<n>`. Both parsers take a `--root <prefix>` to turn absolute log paths into
  repo-relative ones; pinned against real logs.
Triage (orchestrator): equivalent (e.g. `true→false` on a value only read by `isset`),
performance-only (retry counts, step budgets), log context → drop with a one-line reason.
Behavior-changing survivors are rewritten as **behavior statements** ("a second booking overwrites
the first total"), never as file:line, and go to the test-writer in oracle mode for ONE round. Those
tests are labelled "informed" in the report and snapshotted like the rest. A red informed test on
the executor's code → REVISE to the executor (counts against the 2 REVISE rounds); after the fix,
`mutate.sh` runs once more for confirmation. TIMEOUT or SKIP never blocks.

### D. Telemetry
The terminal `orch_run_log` call in delegate Phase 5 gets
`--counts "revision_rounds=N,oracle=used|fallback|skipped,mutate=OK|SKIP|TIMEOUT|none,survivors=N"`,
so later runs show how often the fallback fires and whether mutation finds anything.

### E. Docs
`delegate/CLAUDE.md` gotcha (test-writer owns the oracle; executor never edits locked files;
worktree mode has no oracle in v1). `audit/CLAUDE.md` command rows for both scripts and tests, plus
the one-time verified Infection install. Root `CLAUDE.md` "Project-specific overrides" lists
`.claude/mutation-targets`. `plan-it/references/execute-review.md` gets one line: oracle step not
applied in worktree execution (v1).

## Affected files
- `delegate/SKILL.md:63-129` (Phase 3 marks logic test steps, new Phase 3.5, Phase 4 briefing, Phase 5 checks; `--no-oracle` in Phase 0)
- `agents/test-writer.md:18-79` (new "Oracle mode" section)
- `agents/spec-executor.md:20-41` (locked-files rule)
- `plan-it/references/execute-review.md:63-73` (one-line note)
- NEW `audit/bin/oracle-lock.sh`, `audit/bin/oracle-lock.test.sh`
- NEW `audit/bin/mutate.sh`, `audit/bin/mutate.test.sh`
- NEW `audit/bin/fixtures/mutate/` (moved from `audit/bin/fixtures/mutate/`)
- `audit/CLAUDE.md`, `delegate/CLAUDE.md`, root `CLAUDE.md` (overrides list)

## Out of scope
- Project repos (`.claude/mutation-targets` in events, shop, zeit): follow-up, one commit per repo.
- `/audit`: no mutation run there (cost).
- Oracle in worktree mode, Stryker, Swift mutation, PreToolUse hooks, automatic Infection download.

## Edge cases
- Contract too vague for a red test: test-writer reports missing facts; orchestrator fills them or
  asks the user (Phase 2 style); fallback otherwise.
- Executor needs fixtures/factories: allowed; shared setup files are hashed.
- Diff touches a target but changes no mutated line: survivors filtered to zero → OK, nothing to do.
- Another session edits a hashed setup file mid-run: reported as CHANGED with the file; orchestrator
  checks `git log`/author before failing (documented in Phase 5).

## Known Costs
- One extra Sonnet agent and one red-test run per test-bearing run.
- No oracle in `--worktree` and `/plan-it execute` (v1). Revisit when worktree runs are frequent.
- Factory edits can still weaken a locked test (residual).
- Feature-level mutation can hit the budget (events ExpenseService baseline 106 s): partial survivors.

## Open Questions
- Should `/ship` warn when `.claude/mutation-targets` lists files no test covers? Assumption: no (v1).

## Next steps (after merge)
1. `.claude/mutation-targets` in events (ExpenseService, SecretSantaMatchService,
   EventRecurrenceService, Helpers/Money), shop (Support/ShopMetrics, Services/Cart,
   Checkout/DraftOrderFactory), zeit (Services/Tax/*, Support/TaxDateParser).
2. Install infection.phar once (verified) for zeit.

## Challenge result
Consolidation: 10 raw concerns → 8 after dedupe.
Convergent: oracle-lock lifecycle (architecture 2 + risk 2); mutation round scope/independence (architecture 4 + risk 5).
- Accepted: worktree transfer gap (A1) → oracle limited to working-tree mode, Known Cost.
- Accepted: NONE ambiguity (A2) + lifecycle (R2) → run-id key, ORACLE_EXPECTED flag, clear, formatter run by test-writer.
- Accepted in part: fixture/parser (A3) → `--root` for both parsers. Rejected: "covered-only drops UNTESTED", the fixture was produced with `--covered-only` and lists 46 UNTESTED.
- Accepted: round-2 independence (A4) + survivor scope (R5) → behavior statements, changed lines ±3, cap 15, informed label, snapshot, REVISE accounting, one confirm run.
- Accepted: red-check BLOCK (R1) → fallback to today's flow, `--no-oracle`, contract carries setup.
- Accepted: bypass via shared setup (R3) → hash Pest.php/TestCase/phpunit.xml, run check-silencing.
- Accepted: timeout/lock (R4) → portable wrapper, one total budget, timeout inside lock, kill process group.
- Accepted: figure mismatch (R6) → Problem names both runs.
- Evaluation (sonnet): "solid, needs a real timeout and run-ledger fields". Incorporated: own timeout resolution with SKIP instead of fail-open, run-log counts (Solution D), contract sourced from spec/docblocks with per-line source, "logic test step" definition, assets path in the drift check. Not acted on: test-writer lacks Edit (whole-file rewrites on amend are acceptable for new test files).

## Delegate spec

## Task: /delegate oracle step, locked tests, targeted mutation run
**Goal:** `bash audit/bin/oracle-lock.test.sh` and `bash audit/bin/mutate.test.sh` exit 0; delegate/SKILL.md implements Phase 3.5 and the Phase 5 checks per this plan; test-writer has an oracle mode; spec-executor has the locked-files rule.
**Context:** skills repo `/Users/rafael/Developer/claude/skills`. Bash helpers follow `audit/bin/test-lock.sh` (state under `--git-common-dir`) and its test `audit/bin/test-lock.test.sh` (plain bash, temp git repo). `KEY=value` output like `pre-checks.sh`. Portable timeout wrapper: `audit/bin/check-outdated.sh`. Real fixtures in `audit/bin/fixtures/mutate/`. bash 3.2 compatible.
**Affected files:** see Affected files above.
**Out of Scope:** project repos, `audit/SKILL.md`, hooks, `store-assets/*` (another session's uncommitted work, never stage it).
**Steps:**
1. `audit/bin/oracle-lock.sh snapshot|check|clear --run <id> [files...]` (snapshot adds Pest.php/TestCase.php/phpunit.xml(.dist) when present; check prints `ORACLE_CHANGED=<file>` per changed/missing file and `ORACLE_RESULT=OK|CHANGED|NONE`; exit 0) + test: unchanged OK, sed edit detected, deletion detected, shared setup edit detected, unknown run NONE, two run ids isolated, clear removes state → verify: `bash audit/bin/oracle-lock.test.sh` → exit 0
2. Move fixtures to `audit/bin/fixtures/mutate/`; `audit/bin/mutate.sh <root> <base-ref>` per Solution C, plus `--parse-pest <log> --root <p>` / `--parse-infection <log> --root <p>` and `--changed-lines <spec>` for the filter; test: target intersection (match, no match, file absent), FQCN from namespace, empty test list SKIP, no coverage driver SKIP (stub `php` on PATH), Pest fixture parses line 112 TrueToFalse and reports 46 before filtering, Infection fixture yields `app/Services/Tax/BewirtungSplit.php:36` relative, ±3 filter and cap 15 with `SURVIVORS_TRUNCATED`, neither `timeout` nor `gtimeout` on PATH → `SKIP reason=no-timeout` → verify: `bash audit/bin/mutate.test.sh` → exit 0
3. `agents/test-writer.md`: "Oracle mode" section per Solution A (no target body, contract only, property loop rules, formatter, red expected, line-inversion suspended, assumptions reported; informed round via behavior statements) → verify: `grep -c "Oracle mode" agents/test-writer.md` ≥ 1
4. `agents/spec-executor.md`: locked files read-only + STOP rule → verify: `grep -n "locked" agents/spec-executor.md` → hit
5. `delegate/SKILL.md`: `--no-oracle` in Phase 0; Phase 3 marks logic test steps; Phase 3.5 with the "logic test step" definition, contract from spec/request/docblocks with a source per line, dispatch, red check, fallback, snapshot, state save; Phase 4 briefing lists locked files; Phase 5 adds oracle check (NONE+expected = fail), check-silencing, conditional mutate.sh with triage and one informed round, clear at terminal verdict; run-log counts `oracle=`, `mutate=`, `survivors=` per Solution D; under 500 lines → verify: `wc -l < delegate/SKILL.md` < 500; `grep -c "Phase 3.5" delegate/SKILL.md` ≥ 1
6. Docs per Solution E → verify: `grep -n "mutation-targets" CLAUDE.md audit/CLAUDE.md` → hits; `bash audit/bin/check-docs-claims.sh .` → no new failures
**Done criteria (all):** steps' verifies green; `bash audit/bin/test-lock.test.sh` exit 0; `bash audit/bin/check-fresh-shell.sh .` clean for delegate/SKILL.md; `git status --short` shows only affected files plus the pre-existing store-assets changes (unstaged).
**STOP conditions:** drift on in-scope files; a fixture lacks the expected lines; delegate/SKILL.md would exceed 500 lines; a step needs a project repo change.
