# Test gate: one machine-wide slot, parallel events browser suite, named failures

> **Executor instruction:** Follow step by step, check each verify
> criterion before moving on. If a STOP condition occurs: stop and
> report, do not improvise.
>
> **Drift check (first):** `git -C ~/Developer/claude/skills diff --stat 1aaf4f4..HEAD -- audit/bin/test-lock.sh audit/CLAUDE.md CLAUDE.md`,
> `git -C ~/Developer/apps/events status --short` (expected: only `tests/Pest.php` and `tests/CLAUDE.md`, handled in step 0)
> and `git -C ~/Developer/apps/events diff --stat f1ea7b170..HEAD -- composer.json tests/`, and compare
> `~/.local/bin/deploy` (not versioned, 16834 bytes, mtime 2026-10-02 21:29) against the line numbers below.
> Any mismatch at a named location: STOP.

## Meta
- Planned at: skills `1aaf4f4`, events `f1ea7b170` (plus the uncommitted 15 s timeout edit), 2026-10-06
- Challengers: ran architecture + risk (always). Skipped product (scope set by the user), design (no UI),
  simplicity (user fixed the scope in three explicit decisions). Drift check: run by the orchestrator.
- Status: Spec

## Problem
Full test suites of zeit, events and shop run through `deploy <app> test` (`~/.local/bin/deploy`). Its lock
(`deploy:97,123-140`) and `audit/bin/test-lock.sh` are both per project, so two projects' suites run at the
same time. events alone uses all 12 cores for Unit+Feature (`--parallel`, 12 processes), so a second suite
overbooks the Mac and Playwright page visits in events' browser suite hit the timeout (2026-09-30 at 5 s,
2026-10-05 at 10 s, now raised to 15 s; the tests take at most 6 s in isolation). The gate is also slow
(events: 297 s Unit+Feature plus 792 s serial browser suite), and when it fails it names no test: stall
prints the last 5 log lines (`deploy:184-185`), timeout and red print one generic line (`deploy:200,207`).
One run on 2026-10-05 ended with exit 143 that neither the watchdog nor the timeout sent, and the output
did not say so.

## Goal
1. Never more than one full suite started via `deploy <app> test` on the Mac. A second one waits, says
   what it waits for, and starts on its own (or gives up after 900 s with the holder named).
2. events' full gate under 10 min (from about 18 min): Unit+Feature about 300 s plus browser ≤ 240 s.
3. Every non-green end names its cause: the red tests, the last finished test plus running workers on a
   stall, the timeout, or "terminated by signal N (sender unknown)" after ruling out deploy's own kills.
   Browser tests that are red once and green on a single rerun pass the gate, are reported as flaky and
   logged; a test flaky twice within 14 days fails hard.

## Non-Goals
- Gating single-file or filtered runs, `composer test` or `composer test:parallel` started by hand. They
  bypass the slot (documented, not enforced).
- Rerunning Unit/Feature failures. Only `Tests\Browser\…` failures get a rerun.
- Making zeit or shop faster. Versioning `~/.local/bin/deploy` (separate change).
- Identifying a signal's sender (macOS keeps no record).

## Out of Scope (Files)
- `audit/bin/test-lock.sh`: per-repo lock stays as is (it protects the shared test DB of worktrees and agents).
- events app code (`app/`, `resources/`): only test config, one test assertion and docs change.
- `deploy` deploy/rollback paths outside the `# >>> test-gate` block and the app `case` (`deploy:38-40`).

## Solution

### Approach
All new logic lives in one versioned, tested helper `audit/bin/test-gate.sh` next to `test-lock.sh`; `deploy`
only calls it. Two parts:

**Slot** (sequential across projects, user decision): a mkdir slot at a fixed per-user path
`$HOME/.local/state/claude/full-suite.slot` (not `$TMPDIR`: sandboxed Claude Code shells see a different
TMPDIR, the failure `test-lock.sh:17-26` documents; the sandbox can write `~/.local/state/claude`, see the
run ledger). It stores `pid`, `app` and the process start time (`ps -o lstart= -p`); liveness = `ps -p`
plus matching start time (survives PID reuse, no `kill -0` EPERM issue). Wait cap 900 s, below
`test-lock.sh`'s 960 s, because `/audit` wraps `deploy events test` in `test-lock.sh` and holds the repo
lock while waiting. Acquired after `trap cleanup_test_gate EXIT` (`deploy:146`) and before the
`public/hot` parking (`deploy:150`), so a `die` releases it and `public/hot` is not parked while waiting;
waiting happens before gtimeout and the watchdog start, so it counts toward neither.

**Run** (`test-gate.sh run <test-cmd> <file-cmd>`): replaces the bare `--cmd "$TEST_COMMAND"` in
`deploy:170`, so the first pass and the reruns run inside ONE `test-lock.sh` invocation, under the same
gtimeout and watchdog, with all output in `$TEST_LOG` (no window for an agent to refresh `events_test`
between pass and rerun). On red it extracts `FAILED  Tests\Browser\…` names and the Pest summary
"N failed". Rerun only when: extracted count equals N, 1-5 distinct browser files, no non-browser `FAILED`,
no fatal/worker-crash marker. Each file reruns once with the single-file command. All green → exit 0
plus `FLAKY:` lines; any test already flaky once in the last 14 days in
`~/.local/state/claude/test-flakes.jsonl` → hard red. Every flake is appended there with app, test, date,
worker count. Otherwise hard red with up to 20 `FAILED` lines.

**Faster**: events' browser suite with `--parallel --processes=6`. Laravel's `TestDatabases` gives each worker
`events_test_N`; pest-plugin-browser picks free ports (`vendor/pestphp/pest-plugin-browser/src/Support/Port.php`)
and shares one Playwright server via `vendor/.../.temp/playwright-server.json` (`ServerManager.php:58-76`),
safe because `test-lock.sh` allows one run per checkout. A manual browser run during the gate would stop that
server: documented as a rule. Playwright stays pinned at 1.61.1 (pest#1911).

**Reporting in `deploy`**: rc 124 → timeout; stalled flag → stall message with last finished test
(last `✓`/`⨯`/`PASS`/`FAIL` line) and the PHP worker command lines of the test process group; rc 129-159
without either → `Testlauf durch Signal N beendet, Absender unbekannt (nicht Watchdog, nicht Timeout)`.
deploy logs a timestamped line before each own `kill_test_tree` (`deploy:135,186`, cleanup) and installs
its TERM trap (logging the parent chain at receive time) before the slot wait.

### Steps
0. events: commit the pending 15 s timeout edit (`tests/Pest.php`, `tests/CLAUDE.md`) as
   `test(events): raise Playwright timeout to 15s for load-induced flakes`. All later commits: skills and
   events on `main` as usual for both repos, one commit per repo per finished step group, no push (push and
   deploy stay with the user). `deploy.bak-2026-10-06` is kept until step 7 passes.
   → verify: `git -C ~/Developer/apps/events show --stat HEAD` lists exactly those two files.
1. `audit/bin/test-gate.sh` (bash 3.2, `set -u`, header like `test-lock.sh:1-30`): subcommands
   `slot-acquire <app>`, `slot-release <pid>`, `run <test-cmd> <file-cmd>` as in Approach. Slot waiting
   prints `[deploy] Slot belegt: <app> (PID p, seit Ns), warte` every 30 s, exits 75 after
   `SLOT_WAIT_MAX` (default 900). → verify: step 2 green.
2. `audit/bin/test-gate.test.sh` in the style of `test-lock.test.sh`: slot free/taken/handover, dead holder
   reclaimed, PID reuse (live PID, wrong start time) reclaimed, non-owner release is a no-op, wait timeout
   exit 75; `run` with fixture commands: green; browser flake (rerun green) → exit 0 + `FLAKY:`; same test
   already in a temp JSONL → exit 1; count mismatch → exit 1 without rerun; Feature failure → exit 1
   without rerun; 6 files → exit 1. Parse fixtures are captured from a real deliberately red run (step 5a),
   not hand-written. → verify: exit 0; inverting two target lines turns their cases red.
3. `deploy`, backup first (`cp ~/.local/bin/deploy ~/.local/bin/deploy.bak-2026-10-06`): `TEST_FILE_COMMAND`
   per app in the `case` (`deploy:38-40`: zeit/events `php artisan test`, shop `./vendor/bin/pest`);
   TERM trap with parent-chain log before the slot; `slot-acquire` between `deploy:146` and `deploy:150`;
   `slot-release $$` in `cleanup_test_gate` (`deploy:112-121`); `deploy:170` calls `test-gate.sh run`. No new
   env override of the test command. → verify: `bash -n` ok; two `deploy shop test` started 5 s apart:
   the second prints `Slot belegt: shop` and ends green after the first; `deploy events --dry-run` output
   unchanged.
4. `deploy` reporting (`deploy:182-208`) as in Approach, incl. kill log lines, plus one ledger line per gate
   via `audit/bin/run-log.sh --skill deploy-test --outcome <green|red|flaky|stall|timeout|signal>
   --counts "app=…,slot_wait_s=…,duration_s=…,reruns=…"` (existing ledger, no new log for durations). → verify: `deploy shop test`
   with `DEPLOY_TEST_STALL=20` while a shop test sleeps 60 s (temporary test file, deleted after) → stall
   message names the last finished test; `kill -TERM` on the test process group from a second shell →
   "durch Signal 15 beendet, Absender unbekannt".
5. events browser suite parallel:
   a. Capture a red parallel log for step 2 fixtures (temporarily break one assertion, restore after).
   b. `tests/Browser/Event/GuestListCompactTest.php:13` asserts the DB name equals `events_test`: change to a
      prefix match; `grep -rn "events_test" tests/Browser` for other literals and fix the same way.
   c. `composer.json:88` → `… --exclude-group=marketing --parallel --processes=N`, N chosen by d.
   d. ORCHESTRATOR-RUN (global CLAUDE.md §7: the full suite belongs to the orchestrator): three full
      `deploy events test` runs each with 4 and with 6 processes. Pick the N with zero first-pass red
      browser tests across its three runs and browser `Duration` ≤ 240 s; if both qualify, the faster.
      Neither qualifies → STOP (load is the cause, parallel does not help; keep serial).
   → verify: chosen N recorded in the commit message with the six durations; node and chrome processes
   descending from the run's PGID are gone afterwards (`pgrep -g`).
6. Docs: events `tests/CLAUDE.md` (parallel browser suite, per-worker DB, no manual browser run while a gate
   runs), events `CLAUDE.md` deploy section (one suite per Mac via `deploy`, flaky rerun + log), skills
   `CLAUDE.md:40` and `audit/CLAUDE.md` (new script + its test command), `deploy` header (`deploy:1-12`).
   → verify: `bash audit/bin/check-docs-claims.sh .` → `DOCSCLAIM_RESULT=OK`.
7. ORCHESTRATOR-RUN end-to-end: `deploy events test` while `deploy zeit test` runs. → verify: events
   waits, then green within 600 s from slot acquisition, marker written, ledger line present (step 4).

### Affected Files
- `~/Developer/claude/skills/audit/bin/test-gate.sh`, `test-gate.test.sh` — new
- `~/.local/bin/deploy` — header (1-12), app case (38-40), test-gate block (89-210)
- events: `composer.json:88`, `tests/Browser/Event/GuestListCompactTest.php:13` (+ any other `events_test`
  literal under `tests/Browser`), `tests/CLAUDE.md`, `CLAUDE.md`, plus step 0's commit
- skills: `CLAUDE.md`, `audit/CLAUDE.md`

### Conventions
Skills repo: bash 3.2, every `audit/bin/*.sh` has a single-script `*.test.sh` (`audit/CLAUDE.md`), exemplar
`test-lock.sh` + `test-lock.test.sh`. `deploy`: German messages via `say/ok/warn/abort/die` (`deploy:56-60`),
kills only by process group, never by name (`deploy:90-92`). events: Pest 4, `tests/CLAUDE.md`.

## Edge Cases
- Holder crashed or PID reused: reclaimed via start-time mismatch, message says so.
- Same app twice: per-app lock (`deploy:129`) dies before the slot.
- Ctrl-C while waiting: EXIT trap releases nothing it does not own.
- Rerun red: hard red, both runs listed. Parallel-only failure in step 5: STOP.

## Known Costs
- A second deploy waits up to about 10 min; `/audit` running `deploy events test` queues behind it and
  gives up after 900 s.
- A rerun can hide a rare real race; the 14-day rule and the JSONL log limit that.
- Hand-started `composer test` runs still bypass the slot.

## Done Criteria
- [ ] `bash ~/Developer/claude/skills/audit/bin/test-gate.test.sh` → exit 0
- [ ] `bash ~/Developer/claude/skills/audit/bin/test-lock.test.sh` → exit 0
- [ ] Steps 3 and 4 verify output pasted into the report (executor: `deploy shop test` only, 44 s)
- [ ] Steps 5d and 7: run by the orchestrator after the executor's report, not by the executor
- [ ] `bash -n ~/.local/bin/deploy` → exit 0
- [ ] `git status` in skills and events: only the affected files

## STOP Conditions
- Line numbers in `deploy` or events files do not match.
- The parallel browser suite fails where the serial run passes: revert step 5, report the tests, keep 1-4.
- Pest's parallel output has no reliable failed-count summary line (step 5a): stop before step 2's parse cases.
- A verify fails twice after a serious fix attempt. A change would touch `test-lock.sh` or events app code.

## Maintenance Notes
- New app in `deploy`: add `TEST_FILE_COMMAND`.
- Re-check pest-plugin-browser PR #245/#254 and pest#1911 before bumping Playwright past 1.61.1.
- A test in `test-flakes.jsonl` gets fixed, not rerun forever; the 14-day rule enforces it.

## Challenge Result
Consolidation: 16 concerns → 12 after dedupe. Convergent: parse count must match the summary (A+R),
rerun inside the same lock/timeout/watchdog (A+R), signal sender cannot be known (A+R), wrong Port path (A+R),
slot ordering vs traps (A+R).
- **Accepted:** slot path in `~/.local/state/claude` with start-time liveness (R1); no test-command env
  override, fixtures run `test-gate.sh run` directly (R2); 14-day flaky rule + worker count (R3); summary
  count check, real captured fixtures (R4, A5); signal range 129-159, "sender unknown", own-kill log, early
  TERM trap (R5, A8); single-invocation run+rerun under one lock/timeout/watchdog (R6, A2); browser ≤ 240 s,
  three full gate runs, PGID-based orphan check, Port path fixed (R7, A1); commit the timeout edit first (R8);
  `GuestListCompactTest` DB-name assertion (A1); slot wait cap 900 s + Known Cost (A3); slot between
  `deploy:146` and `150` (A6); goal scoped to `deploy` (A7).
- **Accepted as doc rule only:** manual browser run during a gate stops the shared Playwright server (A4).
- **Deferred:** a verify that provokes A4: revisit when a gate fails with a missing `playwright-server.json`.
- **Evaluation (accepted):** 4 vs 6 process comparison with zero first-pass reds (load-masking risk);
  full-suite verifies marked orchestrator-run (§7); gate telemetry via `run-log.sh`; commit plan in step 0.

## Delegate spec

## Task: Test gate with one machine-wide slot, parallel events browser suite, named failures
**Goal:** one full suite per Mac via `deploy` (second waits ≤ 900 s and reports), events gate < 10 min,
every non-green end names red/stalled/flaky tests or "signal N, sender unknown".
**Context:** `~/.local/bin/deploy` test-gate block 89-210 (per-app lock 123-140, traps 146/155, test start
170, watchdog 179-190, results 190-210), app case 38-40; `audit/bin/test-lock.sh` unchanged; events
`composer.json:84-88`, Playwright pinned 1.61.1. Exemplar: `audit/bin/test-lock.sh` + `test-lock.test.sh`.
**Affected files:** see Affected Files.
**Out of Scope:** `test-lock.sh`, events app code, deploy/rollback paths.
**Steps:** 0-5c and 6 above, each with its verify; step 5a before step 2's parse cases. Steps 5d and 7
are run by the orchestrator, never by the executor (no full `deploy events test` in the executor).
**Done criteria (all):** see Done Criteria.
**STOP conditions:** see STOP Conditions.
