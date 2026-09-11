# Audit Eval Suite

Measure how well `/audit` actually finds the bugs it should find.

## Why

We have no way today to answer "did the audit get better or worse this month".
Anthropic's "4x fewer flaws missed" claim is from their internal evals on their
models. It doesn't tell us anything about our specific prompt + worker setup on
the kinds of code we audit.

This directory contains fixtures with known-bad code and the findings the audit
SHOULD produce. The runner scores precision/recall.

## Status: growing eval suite

As of 2026-09-10: 88 scorable fixtures (matched against `expected/<base>.json`)
across 13 categories (a11y, animation, architecture, copy, correctness, docs,
payments, performance, quality, reliability, security, ui, ux) ship with the repo. Not yet a stable
benchmark: add a new fixture every time you discover a class of bug the audit missed.

**The harness produced no valid measurement between 2026-09-05 and 2026-09-10.** The per-dimension
rebuild rewrote the invocation as `... ${dim_env:-AUDIT_FIX_SCOPE=none} claude -p`, and an
assignment arriving from a parameter expansion is a command name to the shell, not an assignment.
No fixture started a session in that window; every run reported 0 recall and exited 0. Any number
recorded from this harness in that period is void. The calibration figures in the root `CLAUDE.md`
are NOT from this harness and stand unaffected.

### Baseline, 2026-09-10 (first valid measurement after the repair)

Both runs `--scoped`, so they measure worker recall for one dimension, never routing. Do not compare
them against unscoped numbers.

| Dimension | Fixtures | Recall | False positives | Unmeasured |
|---|---|---|---|---|
| payments | 4 | 3/4 | 0 | 1 (no audit log written) |
| security | 20 | 19/24 expected findings | 8 as measured, 5 after correcting the harness | 1 (timeout at 901s) |
| architecture | 17 | 17/18 | 0 | 0 |

`architecture` is the cleanest picture so far and the only dimension measured after every harness
repair of 2026-09-10: no false positives, no timeouts, no unmeasured fixtures, and `--recheck`
reports no scorer gap. The single miss is a dead write
(`job-payload-overwritten-before-consumption.php:31`, a flag assigned and never read) in a fixture
whose larger Critical was found. Treat its 94 percent as the current ceiling reference, not as a
target: it is one dimension on 17 fixtures, and `security` at 79 percent was measured against
expectations that have since been shown to under-report by at least one hit.

**The security false-positive count was mostly the harness, not the dimension.** The run reported 8;
analysing each against the artifacts gave a different picture. Three came from `must_not_find`
entries with no `line`, which degrades the check to "any finding in this dimension is a false
positive", so those specialists were penalised for their own correct hit. Those three expectations
now carry a line and the runner hard-errors on the combination. Two more were the specialist
correctly following the coverage-not-filtering rule in `agents/prompt-template.md` and reporting a
genuine secondary weakness the fixture treats as scenery, which is arguably the fixture's problem,
not the prompt's. Two were not reproducible from the artifacts at all. That leaves at most one to
two real false positives, all of the same narrow shape: an adjacent, correct guard pulled into the
fix alongside the real defect.

The lesson is the one this whole suite exists to catch, applied to itself: a false-positive number
is a claim about the measuring tool until each case has been read against the artifacts. Do not act
on an aggregate here without doing that.

`hash-verified-earlier-in-file.php` is a pure trap with `expected: 0` and it passes, which is worth
knowing: what separates it from the failures is that its rule (`guidelines/security.md:26-28`) names
the exact failure shape and its bar is a single binary outcome.

The remaining 11 dimensions are unmeasured since the break. Roughly five minutes per fixture
scoped, so budget accordingly before starting a category.

## Layout

```
evals/
  README.md              this file
  run-evals.sh           runner: runs /audit on each fixture, scores against expected
  fixtures/              known-bad code organized by category
    security/sqli-laravel.php
    a11y/missing-aria.blade.php
    performance/n-plus-one.php
  expected/              expected findings per fixture, flat (no category subdirs)
    sqli-laravel.json
    missing-aria.json
    n-plus-one.json
```

## Fixture format

A fixture is just a real file with intentional bugs. Keep them minimal so the
expected findings are unambiguous. Reference real frameworks (Laravel, Blade,
React) since that's what /audit is tuned for.

**`.eval-root` marker (directory fixtures only).** A directory fixture that
contains a top-level `.eval-root` file is copied to the throwaway repo's ROOT
instead of under `<category>/<name>/`; the marker file itself is never
staged. This exists for fixtures whose scenario depends on repo-level
detection rather than the diff — a manifest a dimension gates on
(`composer.json`/`package.json`), a config file only read from the repo
root, and so on. Without it, a plain directory-fixture copy lands the
manifest at `<category>/<name>/composer.json`, which the detector never
sees (it only looks at the repo root and one level into each source
directory), so the gated dimension never runs and the fixture scores zero
recall for a reason indistinguishable from the dimension actually failing.
Used by the `payments` fixtures, which need `composer.json` at the repo
root for `bin/detect-stripe.sh` to report `STRIPE=yes`.

## Expected format

```json
{
  "fixture": "security/sqli-laravel.php",
  "must_find": [
    {
      "dimension": "security",
      "line": 12,
      "matches": ["sql injection", "raw query", "concatenation"],
      "severity": "critical"
    }
  ],
  "must_not_find": [
    {
      "dimension": "performance",
      "reason": "no perf issue exists in this fixture"
    }
  ]
}
```

`matches` is a list of substrings; any one matching the finding description
counts as a hit. Matching tolerates ordinary word-form variation: keywords of
9+ characters are trimmed by their trailing 3 characters before matching (e.g.
`idempotent` also matches `idempotency`), so keywords shorter than that are
matched verbatim and phrasing you actually expect the audit to use, not a
mash of synonyms, is still the right way to write `matches`. `must_not_find`
catches false positives.

A `must_not_find` entry needs a `line` whenever its `dimension` also appears
in `must_find` for the same fixture: without it, the check degrades to "any
finding in this dimension is a false positive", so the fixture's own
legitimate `must_find` hit counts as the false positive it was penalized for,
and 0 FPs becomes arithmetically impossible. `run-evals.sh` hard-errors on
this before running anything. A `must_not_find` entry whose dimension is
*not* in `must_find` (the `performance` example above, against a `security`
must_find) may omit `line`; the runner only warns, since dimension-wide is
occasionally the intended claim there. Point `line` at the specific line the
`reason` is actually about, not at the finding you want to suppress in
general — see the security fixtures for examples of picking the line that
anchors a "this specific spot is correct, don't flag it" claim.

## Validating expected/*.json without running anything

`--validate-only` runs every check `run-evals.sh` does on `expected/*.json`
before a normal run, prints a summary by class, and exits — no fixtures run,
no model calls, no cost. Seconds instead of hours. Always run this after
touching `expected/`, and periodically on the whole set to catch drift early
instead of discovering it after an expensive run.

```bash
bash audit/evals/run-evals.sh --validate-only
```

Checks (see `validate_expected()` in `run-evals.sh` for the exact matching
mechanism each one is grounded in):

| Check | Severity | What it catches |
|---|---|---|
| `must_not_find` missing `line`, same dimension as a `must_find` | error | the check degrades to dimension-wide and the fixture's own correct hit counts as its own false positive |
| `must_not_find` missing `line`, different dimension | warning | sometimes intentional, but indistinguishable from a forgotten line |
| Window collision | error | a `must_find` and a `must_not_find` in the same dimension, 3 or fewer lines apart; the `must_find` line falls inside the `must_not_find`'s +/-3 false-positive window |
| Line out of range | error | a cited `line` is <=0 or past the end of the fixture file (only checked when `fixture` names a single resolvable file; directory fixtures are skipped, not guessed at) |
| Missing fixture | error | `fixture` points at a path that does not exist under `fixtures/` |
| Unknown dimension | error | `dimension` is not one of find.js's `ALL_DIMENSIONS` or the two documented aliases (`quality`, `correctness`, both of which `dim_pattern_for()` resolves to the `code_quality` pattern) |
| Unknown severity | error | a `must_find` `severity` other than `critical`/`important`/`minor` (case-insensitive) |
| Hyphenated keyword | warning, or error if every keyword in one entry is hyphenated | `score_fixture` runs the log through `tr '-' ' '` before matching, so a keyword containing a hyphen can never match; write keywords space-separated. Escalates to a hard error only when no sibling keyword in the same entry can match either |

## Running

Requires bash 4+ (`declare -A`); on macOS: `brew install bash`.

```bash
bash audit/evals/run-evals.sh
```

Outputs precision (correct findings / all findings) and recall (correct findings
/ expected findings) per category and total.

**Know the cost before you start a full run.** A fixture is a single file, but
an unscoped `/audit` still dispatches around ten workers that read dozens of
guideline files. Measured on 2026-08-04, one security fixture at `--effort
low`: 896 seconds, 6.93 USD. The full set is hours and triple-digit dollars.

Three options exist for that reason:

| Option | Effect |
|---|---|
| `--only <substring>` | Run only fixtures whose path contains the substring |
| `--scoped` | Run `/audit <dimension>` derived from the fixture's category instead of a full audit. Far cheaper, but it measures worker recall instead of routing plus worker recall, so scoped numbers are not comparable to unscoped baselines |
| `--timeout <sec>` | Per-fixture cap. A timed-out fixture scores as a miss, which is indistinguishable from a recall collapse, so timeouts are printed per fixture and totalled in the summary. Never read a recall number without checking that line |
| `--validate-only` | Run only `validate_expected()` (see above) and exit. Seconds, no cost, no fixtures run — use this first |
| `--recheck <dir>` | Re-run the scorer-gap tripwire (see below) over a stored `results/<timestamp>/` directory instead of running fixtures. Seconds, no cost — see "Scorer-gap tripwire" below |

## Scorer-gap tripwire

Every scoring run compares two things that should roughly agree, per dimension
present in a fixture's `must_find`: how many real finding lines the audit log
actually carries tagged with that dimension, against how many `must_find`
hits the strict scorer credited for it. It only fires on a hard
zero-vs-nonzero mismatch in either direction, never on "found more or fewer
than expected" — a dimension where the scorer credited at least one hit never
trips it, so a fixture that scores correctly cannot trigger it.

- `SCORER_GAP`: the log carries findings tagged with the dimension, but the
  scorer credited zero `must_find` hits for it. The audit likely reported the
  right thing and the scorer failed to count it (a strict keyword or line
  window mismatch) — this needs a human look, not a lower recall number.
- `SUSPICIOUS_CREDIT`: the inverse. The scorer credited a hit while the log
  carries no finding tagged with that dimension at all — it may have matched
  a non-finding line (a scope/summary sentence, a table header) instead of an
  actual finding.

A finding line is recognized two ways: the canonical `[Severity][Dimension]`
bracket tag, or the dimension's own worker-ID prefix (`dim-n-n`) followed
within ~20 characters by a bare severity word — real sessions drift from the
bracket shape into several punctuation variants around that same ID (a bold
bullet, a markdown table row, a numbered list), and the ID+severity pair is
the one thing that survives all of them. This is a rough, dimension-level
count comparison by design, not a second scorer: it does not check that the
reported line and the credited hit are about the same finding, only that the
counts agree in sign. A fifth punctuation variant that also breaks the
ID+severity adjacency is invisible to it, the same fragility the rest of this
harness already lives with (see "Honest limitations" below).

Both counters print per-fixture warning lines and a total in the summary,
under both a normal run and `--recheck`. Measured on the 2026-09-10 security
batch (20 fixtures): 2 `SCORER_GAP` fires, both confirmed by hand to be real
(the audit cited the correct dimension and defect a few lines outside the
scorer's line window) — 0 false positives on a batch where 19/24 fixtures
scored correctly.

`--recheck <dir>` runs this same comparison over a stored
`results/<timestamp>/` directory's `*-auditlog.md` / `*-stdout.txt`
artifacts, without executing anything — free, after the fact, on any past
run:

```bash
bash audit/evals/run-evals.sh --recheck audit/evals/results/2026-09-10_222221
```

## A malformed expected/*.json invalidates its own fixture, not the suite

`validate_expected()` (the same checks `--validate-only` runs, see above)
also runs at the start of a normal run. It no longer aborts the whole suite
when it finds an error: a broken `expected/*.json` only invalidates the one
fixture it belongs to. The summary of errors/warnings by class still prints
exactly as under `--validate-only`, but the run then continues instead of
exiting.

Each fixture whose `expected/*.json` failed an error-level check (warnings do
not invalidate) is skipped during the fixture loop with its own line:

```
  INVALID_EXPECTED <fixture> (expected/<name>.json: <reason class>) — skipped, not scored
```

and counted in the final summary as `INVALID EXPECTATION`, its own category,
separate from both `Recall` and `UNMEASURED`: it was never a scoreable
candidate in the first place, so it is neither a recall miss (nothing ran
against it) nor a harness failure while running (the harness worked exactly
as designed).

`--validate-only` keeps the old behavior unchanged: it still prints the
summary and exits non-zero when there are errors, since that mode exists to
fail loudly in a pre-commit or CI context.

## Exit code

`run-evals.sh` exits non-zero when nothing was actually measured: every
candidate fixture (one with a matching, valid `expected/*.json`) failed
before producing an audit log or session stdout to score (mktemp failure, or
the `claude` session dying before writing anything), or there were zero
candidate fixtures at all (e.g. a typo'd `--only`, or `--only` matching
nothing but fixtures skipped as `INVALID_EXPECTED`, since those never become
candidates either). This case prints `ERROR: nothing was measured` and is
reported in the summary as `UNMEASURED`, separate from recall. A zero-recall
result with exit 0 means fixtures genuinely ran and were scored; it does not
mean the harness itself worked, but at least one fixture did produce
scorable output. Do not read a `Recall: 0/N` line as proof the audit missed
everything without first checking the exit code and the `UNMEASURED` line —
a harness failure and a genuine recall collapse both used to look identical
(2026-09-10 incident).

## Adding a fixture

1. Drop the bad file under `fixtures/{category}/`.
2. Add the matching JSON directly under `expected/` (flat, no category
   subdirectory). The runner matches by basename, not by category:
   - Single-file fixture (`fixtures/{category}/{name}.{ext}`): strip ALL
     extensions from the filename and match `expected/{name}.json`. This
     matters for double extensions: `foo.blade.php` maps to
     `expected/foo.json`, not `expected/foo.blade.json`.
   - Directory fixture (`fixtures/{category}/{name}/`, several files staged
     together as one scenario): match `expected/{name}.json` using the
     directory's own name.
   A fixture whose name does not line up exactly with an `expected/*.json`
   file is silently skipped (`SKIP ... (no expected/{base}.json)`) and never
   scored: the score won't tell you it was missed, only the runner's log
   line does.
3. Re-run. Check the diff in score.

**Fixture names are free keyword matches, name the scenario, never the
defect.** Findings are required to cite `file:line`, so the fixture's own
path is quoted on every scoring log line, and the scorer runs the log
through `tr '-' ' '` before matching. A fixture named after its bug (e.g.
`pretooluse-exit-1-nonblocking.sh`) turns hyphens in the filename into
free-standing keyword hits ("exit 1", "nonblocking") that a completely
wrong finding scores just by citing the right line, no worker reasoning
required (caught 2026-08-05: two fixtures scored hits from filename alone,
confirmed by pushing a deliberately wrong finding line through the actual
scorer). Name fixtures for the scenario/component under test
(`db-command-guard.sh`, `deploy-guard-skill.md`), not for the defect, and
double check no `matches` keyword is a substring of the fixture's own path
after the hyphen-to-space transform.

## Honest limitations

- This is a fixture suite assembled from bugs the audit once missed, not a
  general-capability benchmark: it measures recall on known failure modes, and
  a clean run says nothing about failure modes not yet represented here.
  Per-category counts are still small (as low as 1-2 in some categories), so a
  single category's score can swing a lot on one fixture.
- Real-world bugs aren't this clean. Sampling production-bug findings into
  fixtures is the only way to make this meaningful.
- The runner parses audit-log markdown. If the log format changes, the runner
  breaks. Worth living with for now.
