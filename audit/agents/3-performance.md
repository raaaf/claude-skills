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

**Defect classes calibrated against real findings (2026-09-05/2026-08-27 audits):**
- **Expensive object recreated instead of cached:** a crypto key, compiled regex, hashed cache key,
  or derived URL recomputed on every call/render/request instead of memoized once per input.
- **Quota/budget consumed inside a request-coalescing path:** a shared budget or rate counter
  decremented inside the dedup/coalesce block itself, so a second caller that "inherits" the
  coalesced result also inherits an incorrect budget charge (or none at all).
- **Bulk insert/update without a transaction:** `insertMany`/loop-of-writes issued as individual
  statements instead of wrapped in one transaction.
- **Count-then-fetch instead of COUNT:** a loop counts rows by selecting full rows (`SELECT *`)
  instead of `COUNT(*)`, or re-fetches a full dataset just to derive a length/total.
- **Per-tick array materialization:** a rate limiter/token bucket doing `Array.from`/full-collection
  rebuild on every tick instead of an incremental structure.

## Severity

`Critical` requires a demonstrated user-facing outage or data-loss path under realistic load
(unbounded growth, a lock that starves under concurrency, a query that times out at real data
volume). A measurable but non-outage degradation is `Important`. Micro-optimizations are `Minor`.

## Output

Reply with the specialist schema: `findings[{id, severity, confidence, files, issue, impact}]`
plus `coverage`. Every ID is prefixed `performance-`. Set `coverage` to `COVERAGE: full` or
`COVERAGE: partial | not read: {file1}, {file2}`.
