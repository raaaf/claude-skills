---
name: feature-audit
disable-model-invocation: true
description: |
  Goal-driven loop that builds and maintains FEATURE_AUDIT.md, a canonical table of every
  user-facing feature with one automated test per row, and drives it to all-green. Detects the
  stack, ensures a test runner, derives coverage from source, writes and runs tests per feature,
  fixes until the suite exits 0 without weakening assertions, then writes a holistic
  FEATURE_REVIEW.md. Prints a machine-checkable status line every turn so a loop can resume and
  judge completion. Use for test-coverage bring-up, pre-release feature verification, or auditing
  what a repo actually does. Long-horizon; pair with /loop for unattended grind.
when_to_use: "/feature-audit, build a feature test matrix, verify every feature has a test, test coverage bring-up, what does this repo actually do, feature audit"
argument-hint: "[optional: scope dir or feature filter]"
arguments: [scope]
model: opus
effort: xhigh
allowed-tools:
  - Read
  - Write
  - Edit
  - Bash
  - Glob
  - Grep
  - TodoWrite
  - AskUserQuestion
  - Agent
---

# Feature-Audit

Goal: **`FEATURE_AUDIT.md` is the single canonical feature table for this repo, every row has a
test, and the suite is all-green**, proven by re-running the tests in the current turn, not claimed
from an earlier one.

This is a long-horizon loop, designed to run across many turns and survive interruptions: state
lives in `FEATURE_AUDIT.md` (committed), and every turn ends with a status line a loop can read.
Invoke directly for one pass, or `/loop /feature-audit` for the unattended grind.

**Completion is judged from the current turn only:** the printed status line plus the final
artifacts (full table + test output). Never report done from memory of a prior turn; re-run and
re-print.

Two more rules for the unattended mode: don't end a turn on an intention (if the last paragraph is
a plan, a next step, or "I'll now write the test for X", do it with tool calls instead. End the
turn only on completion or on input only the user can give), and don't treat session length as a
reason to stop, summarize, or propose a fresh session. The state lives in `FEATURE_AUDIT.md` and
survives interruption; that is what makes stopping early unnecessary.

## Phase 0: Setup (first turn)

### 0.1 Scope

`$scope` set (a directory or feature filter): restrict coverage to it. No `$scope`: whole repo.

Count candidate source files. If the repo is large (rough heuristic: > 150 source files and no
`$scope`), AskUserQuestion before starting: **whole repo** vs **name a subdir/area**. A full matrix
over a large repo will not finish inside the turn budget, so scope it or accept a partial, resumable
run. State which you are doing.

### 0.2 FEATURE_AUDIT.md

- **Missing:** CREATE it, a header block then a table:
  `| ID | Feature | User story | Expected behaviour | Status | Test | Notes |`
  Status values: `todo`, `tested`, `passing`, `failing`. `ID` is a short stable slug (e.g.
  `auth-login`); tests reference it so per-row status is derivable (see Phase 2). `Test` holds the
  test name/path covering the row.
- **Exists:** REUSE it, keep header and rows, continue from current status. Never reset rows.

### 0.3 Stack + test command (record in header)

Detect the stack from config files (`package.json`, `composer.json`, `pyproject.toml`,
`Cargo.toml`, `go.mod`, `Gemfile`, `*.csproj`, etc.). Record in the header:
- a machine-readable line `test-command: <cmd>` (e.g. `test-command: npm test`,
  `composer test`, `pytest -q`, `go test ./...`), or `test-command: none`. `bin/run-tests.sh`
  reads this exact key; without it the status line cannot prove `test_exit`.
- the **source directory layout**,
- a `## Needs human review` section (starts with `none found`).

The status line is computed by script (see below), so the table must stay parseable: keep the
exact column order, and escape any literal `|` inside a cell as `\|`.

### 0.4 Ensure a test runner

If a runner already exists: use it.

If none exists: do **not** fall back to docs-only, and do **not** install silently. AskUserQuestion
first, because installing a runner adds dependencies and edits config (a repo mutation the user
should approve):
- **Install minimal runner:** for the stack (Vite/JS: Vitest + jsdom; else the standard runner),
  wire it into config, record the test command in the header.
- **Skip, no runner:** set `test_exit=none` and note in the header why a runner was not added.

`test_exit=none` is an escape hatch, not a shortcut: only acceptable when a runner is genuinely
impossible or the user declined, with the reason documented in the header.

## Work order

Do these in order. Optionally dispatch `Explore` subagents for the Phase 1 enumeration sweep on
large repos; everything else runs in the main loop.

**(1) Coverage.** Every user-facing feature, route, command, or exported entry point in the scoped
source dirs has exactly one row, with expected behaviour derived from the code (not guessed).
Nothing in scope missing. An entry point with several distinct behaviours may warrant several rows;
use judgement, one row per testable behaviour.

**(2) Tested.** Every row has at least one automated test exercising its expected behaviour. The
test references the row `ID` (in the describe/test name or a tag) so results map back to rows. The
test command **ran this turn**; per-row Status updated to `tested`/`passing`/`failing`; failures
logged in Notes.

**(3) Fixed.** Drive the suite to exit `0` with zero `failing` rows, **without skipping, deleting,
or weakening any assertion**. Fixing means fixing the code or correcting a genuinely wrong test, not
neutering the check. If a test is wrong, say so in Notes and correct it; never silently relax it.

**(4) Re-verified.** After the final fix, run the test command **once more this turn** and confirm
it still exits `0`.

**(5) Holistic review (does not gate code, required as an artifact).** Once all rows pass, re-read
`FEATURE_AUDIT.md` from disk and assess the stories together as one product. Write `FEATURE_REVIEW.md`
as an **actionable checklist** under three headings. Every finding is one line so you can triage and
tick it off afterwards:
`- [ ] [high|med|low] <finding> (rows: <ID>, <ID>): <one-line rationale or fix>`
- **Inconsistencies:** contradictory or duplicated behaviours, divergent naming/patterns, DE/EN or
  cross-page mismatches.
- **Gaps:** implied features without a story, missing error states, edge cases, empty/loading states.
- **Potentials:** concrete improvement, simplification, or UX opportunity.

Empty heading: write `- none found` (plain, no checkbox). Do **not** change code or tests in this
phase; it does not affect completion beyond the file existing with the three headings.

## Needs human review

Anything no automated check can decide (subjective behaviour, product intent, ambiguous spec) goes
into a `## Needs human review` section in `FEATURE_AUDIT.md`, as a tickable checklist:
`- [ ] [high|med|low] <question or item> (rows: <ID>)`. It does not block completion. Empty section:
`none found` (plain). `status-line.sh` counts these bullets as `needs_review`; a plain `none found`
line is not counted.

## Commit policy

After each feature reaches `passing`, commit so progress survives interruption and the loop resumes
cleanly. Respect the repo's git guardrails:
- **On the default branch (`main`/`master`), branch first:** `git checkout -b chore/feature-audit`
  (once) before the first commit. Never accumulate audit commits directly on the default branch.
- **Scoped staging only:** `git add` exactly the touched code/test files plus `FEATURE_AUDIT.md`.
  Never `git add -A`; do not sweep unrelated working-tree changes into an audit commit.
- One-line message, e.g. `test(feature-audit): cover auth-login, fix session expiry`.
- Commit, do not push. Pushing stays a separate, explicit user decision.

## Status line (END OF EVERY TURN)

The status line is **computed by script, never by hand** (Bash decides, not the model). End every
turn with these two helpers; print the second's output verbatim as the last line:

```bash
AUDIT_BIN="${CLAUDE_SKILL_DIR}/bin"
bash "$AUDIT_BIN/run-tests.sh"  FEATURE_AUDIT.md           # runs tests, streams output, ends with TEST_EXIT=<code|none>
bash "$AUDIT_BIN/status-line.sh" FEATURE_AUDIT.md <TEST_EXIT>   # <TEST_EXIT> = the value just printed
```

`run-tests.sh` runs the `test-command:` from the header and reports the **real process exit code**,
so `test_exit` cannot be claimed from memory. `status-line.sh` parses the table + the needs-review
section and prints exactly:

```
AUDIT_STATUS total=<N> with_story=<N> tested=<N> passing=<N> failing=<N> needs_review=<N> test_exit=<code|none>
```

Always run `run-tests.sh` in the current turn before printing. Never hand-edit the counts: if they
look wrong, the table is wrong, fix the table.

**Format is load-bearing:** the line MUST stay `AUDIT_STATUS total=...` with NO colon after
`AUDIT_STATUS`. The /audit Stop hook (`~/.claude/hooks/audit-loop.sh`) greps for `AUDIT_STATUS:`
(with colon) — adding a colon here would hand this skill's turns to the /audit loop controller.

## Completion

Achieved ONLY when, **in the current turn**:
- the `status-line.sh` output shows `with_story=total`, `tested=total`, `failing=0`, `test_exit=0`; AND
- the final full `FEATURE_AUDIT.md` table and the final test output were printed this same turn; AND
- `FEATURE_REVIEW.md` exists with the three headings populated or marked `none found`.

`test_exit=none` is acceptable for completion only if the header documents why a runner was
impossible (or the user declined one).

## Final digest (print on completion AND on every stop)

In addition to the machine `AUDIT_STATUS` line, end the run with a short human wrap-up so the result
is usable without opening files:

```
Feature-Audit: <complete | stopped: reason>
  Matrix:  FEATURE_AUDIT.md (<total> features, <passing> passing, <failing> failing)
  Review:  FEATURE_REVIEW.md (<N> findings: <H> high, <M> med, <L> low)
  Human:   <N> needs-human-review items
  Top:     up to 3 highest-severity review/human items, one line each, with row IDs
  Branch:  <branch>, <N> commits this run
```

## Optional: file findings as issues

After the digest, if a GitHub remote exists (`gh repo view` succeeds), offer **once** via
AskUserQuestion to file the open Gaps / Potentials / needs-human-review items as GitHub issues, so they
enter your tracker instead of resting in a file:
- one issue per selected finding, label `feature-audit`, title = the finding, body = rationale +
  affected rows + a pointer to `FEATURE_AUDIT.md`.
- **Dedup:** skip a finding whose title already matches an open `feature-audit`-labelled issue
  (`gh issue list --label feature-audit --state open`).
- skip silently if no remote, the user declines, or running unattended. Inconsistencies that are
  really bugs should be fixed in-loop, not filed.

## Stop conditions

Stop (do not loop forever):
- the **same failure** persists 3 consecutive turns: report the failure, the row, and what you tried.
- **50 turns** total.

On either stop, before handing back, still run the holistic review on whatever is done so far
(Phase 5, Gaps especially), write/update `FEATURE_REVIEW.md`, then print the Final digest. A stopped
run must still leave you the matrix, a partial review, and the digest, not a dead loop.
