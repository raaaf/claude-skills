# Verify-by-Measurement (Performance Findings)

Performance fixes aren't just judged by peer review (fix-verifier) — they're verified against
an actual measurement: metric before the fix, metric after the fix, verdict from the
delta. Adapted from AvdLee's Xcode-Build-Optimization skill (benchmark -> apply -> re-benchmark),
tailored to the `/audit` fix loop.

## Activation

Opt-in. Active only when a measurement command is declared:
- ENV `PERF_MEASURE_CMD`, or
- line in `.claude/audit-guidelines.md`:  `perf-measure: <command>`

The command MUST print exactly one line `PERF_METRIC=<number>` (lower = better).
Examples:
- Bundle budget:  `perf-measure: npx size-limit --json | jq -r '"PERF_METRIC=\([.[].size]|add)"'`
- Build time:     `perf-measure: { /usr/bin/time -p npm run build; } 2>&1 | awk '/^real/{print "PERF_METRIC="$2}'`
- Query count:    a test that uses `DB::enableQueryLog()` and prints the count as `PERF_METRIC=`

Without a declared command: no behavior changes — performance fixes still go through
the fix-verifier (peer review) as before. In the log, `Verification: review` instead of `measured`.

## Flow (Step E / E.5)

1. **Baseline (Step E, before the fix agent):** If the round contains a `[Performance]` finding
   and `PERF_MEASURE_CMD` is set, measure once per round:
   `PERF_BASELINE=$(bash "$AUDIT_BIN/perf-measure.sh" --run "$PERF_MEASURE_CMD")`
2. Fix agents run as usual.
3. **Re-measure (Step E.5, after all fixes of the round):**
   `PERF_AFTER=$(bash "$AUDIT_BIN/perf-measure.sh" --run "$PERF_MEASURE_CMD")`
4. **Verdict (deterministic, no LLM):** compare the `PERF_METRIC` numbers.
   - `AFTER <= BASELINE` (improved or held) -> performance fixes `keep`,
     log: `Verification: measured {BASELINE}->{AFTER}`.
   - `AFTER > BASELINE` (regressed) -> the round's performance fixes are revert candidates:
     report as an open point ("Perf fix worsens metric: {BASELINE} -> {AFTER}") and
     additionally run the fix-verifier to narrow down the cause.
   - `NA` (one side of the measurement failed) -> fall back to fix-verifier (review), note in the log.

## Limits (honest)

- Measures per round in aggregate, not per finding. With multiple perf fixes in one round and a
  regression, the exact culprit isn't unambiguous — hence the additional fix-verifier.
- The measurement command checks ONLY the metric, not correctness or regressions in other
  dimensions. Verify-by-measurement replaces the fix-verifier only for the metric question; on
  regression, the review still runs.
- Cost: one measurement run per round with perf fixes. For expensive builds, runtime scales
  accordingly — hence opt-in and not on by default.
