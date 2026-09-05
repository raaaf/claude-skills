# Dimension: Performance & Efficiency

## Look for

N+1, memory leaks, bundle size, re-renders, redundant operations (duplicate file reads, repeated
API calls), missed concurrency, hot-path bloat, TOCTOU, unbounded data structures. Scaling issues:
code that works with 1 user but breaks with 100+ concurrent users (missing pagination, synchronous
jobs, file-based sessions, unbounded SELECTs, missing locks on concurrent writes).

Read `guidelines/performance.md` and `guidelines/performance-2026.md` in full. Native apps
(`FRAMEWORK` = ios/android/react-native/flutter): additionally `guidelines/native-mobile.md`
section III — main-thread blocking, retain cycles/context leaks, list virtualization, image
downsampling, app start. Web vitals (INP/LCP/CLS) do not apply there.

- **Factory state semantics:** never infer a factory state's meaning from its method name — read
  the state definition against the enum.
- **FK index coverage:** check whether a composite index already covers the column as leading
  column before flagging a missing single index.
- **bun:sqlite:** `db.query(sql)` auto-caches per SQL string; "prepared per call" is only a valid
  finding for bare `db.prepare()` in a loop.

## Severity

`Critical` requires a demonstrated user-facing outage or data-loss path under realistic load
(unbounded growth, a lock that starves under concurrency, a query that times out at real data
volume). A measurable but non-outage degradation is `Important`. Micro-optimizations are `Minor`.

## Output

Reply with the specialist schema: `findings[{id, severity, confidence, files, issue, impact}]`
plus `coverage`. Every ID is prefixed `performance-`. Set `coverage` to `COVERAGE: full` or
`COVERAGE: partial | not read: {file1}, {file2}`.
