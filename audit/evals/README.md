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
| security | 20 | 20/24 expected findings | 8 as first measured, 4 after the harness repairs | 1 (timeout at 901s) |
| architecture | 17 | 17/18 | 0 | 0 |
| code_quality | 12 | 12/13 | 0 | 1 (timeout, partial output still scored) |
| docs_sync | 4 | 5/5 | 0 | 0 |
| a11y | 13 | 14/16 | 0 | 0 |
| ux | 5 | 4/5 | 1 | 0 |
| ui_design | 2 | 2/2 | 0 | 0 |
| animation | 1 | 1/1 | 0 | 0 |
| copy | 1 | 1/1 | 0 | 0 |
| performance | 1 | 1/1 | 0 | 0 |
| correctness | 7 | 9/10 | 1 | 0 |
| reliability | 1 | 1/1 | 0 | 0 |

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

A `must_find` entry uses either `line` (a single anchor) or `lines` (an array
of two or more anchors), never both — `run-evals.sh` hard-errors on an entry
that sets both, since it would be ambiguous which anchor is authoritative. Use
`lines` when the defect genuinely lives at more than one place in the source
(e.g. a key declared twice, a route left ungated by a middleware mounted
elsewhere) and a citation of either place is correct; a finding counts as a
hit when its cited line falls within the usual +/-3 window of ANY one of the
listed anchors, not only the first. Do not use `lines` to paper over an
imprecise citation that is genuinely wrong; only add an anchor you can justify
from the fixture source.

`matches` is a list of substrings; any one matching the finding description
counts as a hit. Matching tolerates ordinary word-form variation: keywords of
9+ characters are trimmed by their trailing 3 characters before matching (e.g.
`idempotent` also matches `idempotency`), so keywords shorter than that are
matched verbatim and phrasing you actually expect the audit to use, not a
mash of synonyms, is still the right way to write `matches`. `must_not_find`
catches false positives.

Every `matches` entry is a literal substring, never a regex, even though
several entries get joined into one `grep -E` alternation internally
(`stem_match`/`ere_escape` in `run-evals.sh`): the runner escapes ERE
metacharacters (`. ^ $ * + ? ( ) [ ] { } |` and `\`) after trimming, so write
`n+1`, `with(`, `nav[x-show]` exactly as they appear in the finding text — no
backslashing needed on your end. A keyword that starts with a letter, digit,
or underscore is anchored with `\b` so it can only match at a word boundary,
never mid-word; a keyword that starts with punctuation (`{!!`, `.help(`,
`$attributes`) is matched unanchored, because `\b` in front of a
non-word-starting keyword would only fire when the character immediately
before it in the log text is itself a word character, the opposite of the
common case where such a token is preceded by whitespace or a line start.

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

## A discarded finding is not a false positive

The `must_not_find` check only counts a real, standing finding as a false positive. A finding the
audit pipeline itself rejected (verdict `REFUTED`, or otherwise marked discarded per
`audit/references/audit-log-template.md`'s `## Discarded` section) is the verification stage
working, not the audit getting it wrong, so `strip_discarded_findings()` removes it before the
false-positive grep ever runs.

Two removal rules, both deliberately narrow so a genuine false positive is never swallowed:

- Section-based: any line between a bare `## Discarded` heading and the next `## ` heading.
- Marker-based: a line containing `REFUTED`, `discarded as `, `discarded,` or `discard:`
  (case-insensitive), the exact vocabulary `audit-log-template.md` defines for a rejected finding —
  a fallback for a drifted log that inlines the verdict without the section.

Neither rule fires on `Minor` severity, `low confidence`, or `never fixed` alone: every logged
Minor finding reads "never fixed" by policy (Minor is never fixed, always logged), so treating that
phrase alone as a discard signal would exempt every real Minor false positive from ever being
counted.

Found 2026-09-12: `advisory-landing-hero-auditlog.md` logged a `[Minor][security]` line under `##
Discarded` ("Discarded as out of scope: the finding itself states the file is static markup...")
that the false-positive check counted anyway, penalizing the `security` specialist for a finding
its own regression pass had already rejected.

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

### code_quality, 2026-09-11

12 of 13, no false positives, one timeout, one scorer gap. The gap is the finding of the run:
`lock-race-entry-clobber` reported the defect in the expectation's own words
(`connect() mutates client and state outside the NSLock that guards every other transition`) and
cited line 23, the `func connect` declaration, while the expectation anchors line 29, the assignment
itself. Six lines apart, so outside the window, so scored a miss.

That is the same cause as `widget-lock-time-check` in the 2026-09-10 security run (cited 47, the
enclosing function; expected 52, the statement). Two dimensions, two fixtures, one habit: specialists
cite the declaration that encloses the defect rather than the defect's own line. Every recall number
measured before 2026-09-11 is therefore a floor, not a reading, and the correction is in
`agents/prompt-template.md`, not in the scorer.

### The citation rule, and why the early numbers are floors

`agents/prompt-template.md` asked for `file:line` without saying which line, and specialists
routinely cited the declaration enclosing a defect rather than the defect itself. Two fixtures in
two dimensions were scored as misses for exactly that: `widget-lock-time-check` (cited 47, expected
52) and `lock-race-entry-clobber` (cited 23, expected 29). The rule now names the defect's own line.

Verified on 2026-09-11 by rerunning `lock-race-entry-clobber` alone: it flipped from a miss to a
hit, and the log gained a citation at line 30 where it previously carried only 1, 12 and 23. One
non-deterministic run does not prove a rule works, but a new citation appearing at the defect line,
where there was none before, is evidence about the mechanism rather than about the score.

Consequence for the table above: `payments`, `security`, `architecture` and `code_quality` were
measured before that fix and are floors, not readings. `docs_sync` is the first dimension measured
after it. Do not compare across that line without saying so.

`docs_sync` is also the first dimension whose fixtures had never been scored at all: four of its
expectations named the dimension `docs`, which no tag ever matches, so they returned nothing from
the day they were written until 2026-09-11. The expectation that a never-exercised category would
score poorly turned out to be wrong; it is the only dimension so far at 5 of 5.

### Keywords are substrings, and were being run as regular expressions

`matches` entries went into a `grep -E` alternation unescaped, so every one was a pattern rather
than the literal text its author wrote. Two failure modes, both wrong: `with(`, `filled(`, `.help(`
and `{!!` break the alternation outright, which makes NO keyword match and the fixture score zero no
matter how good the finding was; `n+1`, `nav[x-show]` and `(int)` stay valid and quietly match
something else. 12 expected files carry such keywords.

Measured on the 2026-09-11 runs, rescored from stored artifacts without rerunning anything:
performance went 0/1 to 1/1, a11y 13/16 to 15/16, ux 2/5 to 3/5, and four of the seven reported
scorer gaps disappeared. The security run was the regression check and did not move.

The uncomfortable part is the selection effect: a keyword like `eager load` was always fine, while
`with(` silently disabled its whole entry. The rule penalised precisely the authors who wrote the
concrete code fragment they expected to see. The numbers in the table above from before this repair
are floors for that reason as well.

### Scope comes from the expectation, not from the folder name

`--scoped` derived the dimension from the fixture's category directory via `dimension_for_category`.
That table guessed where the expectation already knew: every one of the 88 expected files names
exactly one `must_find` dimension. Two consequences followed from the guess. `quality` and `copy`
were simply missing from the table, so 13 fixtures ran a full unscoped audit despite `--scoped`,
roughly ten times the agents each. And `correctness` (7 fixtures) plus `reliability` (1) were left
unmapped on purpose, because those categories span several dimensions, even though each of their
fixtures names one: six want `code_quality`, one `architecture`, one `correctness`, which is a
scoring synonym for `code_quality`.

The derivation now reads `must_find`, normalizes the three category-shaped names
(`correctness`/`quality` to `code_quality`, `ui` to `ui_design`, `docs` to `docs_sync`), and falls
back to the category table only when a fixture has no `must_find` at all, which is the case for the
pure false-positive trap. That turned an estimated two hours and about 55 USD of unscoped runs into
a normal scoped batch.

### A revoked token is not a miss

On 2026-09-12 the CLI's OAuth token was revoked partway through that batch. Six sessions exited in
two to four seconds with `Failed to authenticate. API Error: 401`. Their stdout is not empty, so the
existing "no log and no output" guard did not catch them, and they were scored: `correctness` was
reported as 2 of 10, when two fixtures had run and both had passed. The runner now recognizes a
startup failure by its message and reports those fixtures as UNMEASURED, printing the underlying
error. Matching on the message rather than on the short runtime, since a genuinely fast audit is
legitimate.

### One defect, two correct places to report it

`must_find` may carry `lines: [a, b]` instead of `line`, and a hit counts when a citation falls
within plus or minus 3 of any of them. Both fields on one entry is a hard error, since the intent is
then ambiguous.

This exists because three fixtures showed the same shape, and only two of them turned out to need
it. A PHP array declaring `queue` at line 15 and again at 25 has its defect in the pair, and both
citations are right; `lang-duplicate-array-key-crash` cited 25 in one run and 15 in the next,
scoring 1 and then 0 for the same correct analysis. A route gated by middleware mounted on an exact
path has the bug at the mount (line 8, where the fix goes) and at the ungated sibling route (line
19); `vocab-id-route-gating` cited the mount and was scored a miss.

The third, `widget-lock-time-check`, deliberately did NOT get a second anchor. Citing the enclosing
`getTimeline` declaration instead of the assignment inside it is a precision gap, not a second
location: the function header itself does nothing wrong. That one is the citation rule's job, and
adding an anchor would have papered over an imprecise citation.

The distinction is the whole point of the field. An anchor belongs in `lines` when reporting the
defect AT that line is genuinely correct, never because an audit happened to point there.

### All 13 categories measured, 2026-09-11 and 2026-09-12

Numbers move as harness repairs land, which is why several rows above carry their history rather
than a single figure. Two things are worth keeping in view when reading the table. The small
categories (`ui_design`, `animation`, `copy`, `performance`, `reliability`) hold one or two fixtures
each, so their percentages carry almost no weight. And a single run is not a stable measurement:
`lang-duplicate-array-key-crash` scored 1 then 0 on consecutive days with equally correct analysis
both times, differing only in which half of one defect it cited.

### Remeasuring a11y and ux, 2026-09-12

Both were rerun after the citation rule, the multi-anchor field and the own-dimension rule landed.
All five scorer gaps and all three false positives from the first pass are gone. What remains is one
ux gap and one ux false positive, both explained above.

a11y's recall moved 15 to 14 across the two runs, which is not a regression from those rules. The
misses simply landed elsewhere: `missing-aria` 2 of 3 and `radiogroup-arrow-keys-missed-same-file`
1 of 2, both fixtures expecting several findings where one went unreported, while the two fixtures
that had failed before now pass. Read that number as evidence that a single run over 13 fixtures
varies by about one finding, not as a trend.

### A discarded finding is not a false positive

The false-positive check grepped severity tags and had no notion of a finding the pipeline itself
rejected. One `[Minor][security]` line in `advisory-landing-hero` read "Discarded as out of scope:
the finding itself states the file is static markup with no script, no interpolation and no user
input" and still counted against the dimension, penalising it for the verification stage working
correctly.

Discarded findings are now stripped before the check, by the `## Discarded` section that
`audit-log-template.md` defines and, as a fallback for drifted logs, by an explicit `REFUTED` or
`discarded as` marker on the line. Deliberately NOT by `Minor`, `low confidence` or `never fixed`:
every logged Minor carries "never fixed" by policy, so treating that as the signal would have
exempted every real Minor false positive and quietly emptied the metric.
