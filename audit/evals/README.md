# Audit Eval Suite

Measure how well `/audit` actually finds the bugs it should find.

## Why

We have no way today to answer "did the audit get better or worse this month".
Anthropic's "4x fewer flaws missed" claim is from their internal evals on their
models. It doesn't tell us anything about our specific prompt + worker setup on
the kinds of code we audit.

This directory contains fixtures with known-bad code and the findings the audit
SHOULD produce. The runner scores precision/recall.

## Status: scaffold

The structure and runner are here. Real measurement needs a much larger fixture
set than three example bugs. Treat this as a starting point: add a new fixture
every time you discover a class of bug the audit missed.

## Layout

```
evals/
  README.md              this file
  run-evals.sh           runner: runs /audit on each fixture, scores against expected
  fixtures/              known-bad code organized by category
    security/sqli-laravel.php
    a11y/missing-aria.blade.php
    performance/n-plus-one.php
  expected/              expected findings per fixture
    security/sqli-laravel.json
    a11y/missing-aria.json
    performance/n-plus-one.json
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

```bash
bash audit/evals/run-evals.sh
```

Outputs precision (correct findings / all findings) and recall (correct findings
/ expected findings) per category and total.

## Adding a fixture

1. Drop the bad file under `fixtures/{category}/`.
2. Add the matching JSON under `expected/{category}/`.
3. Re-run. Check the diff in score.

## Honest limitations

- Three fixtures don't make a benchmark. They make a smoke test.
- Real-world bugs aren't this clean. Sampling production-bug findings into
  fixtures is the only way to make this meaningful.
- The runner parses audit-log markdown. If the log format changes, the runner
  breaks. Worth living with for now.
