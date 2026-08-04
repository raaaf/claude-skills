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

As of 2026-08-04: 52 scorable fixtures (matched against `expected/<base>.json`)
across 9 categories (a11y, architecture, correctness, docs, performance,
quality, security, ui, ux) ship with the repo. Not yet a stable benchmark:
add a new fixture every time you discover a class of bug the audit missed.

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
counts as a hit. `must_not_find` catches false positives.

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
