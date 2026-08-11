# Subagent 3: Performance & Efficiency

- **subagent_type:** `performance-auditor`
- **model:** `sonnet`
- **maxTurns:** `10`

## Focus

N+1, memory leaks, bundle size, re-renders, redundant operations (duplicate file reads, repeated API calls), missed concurrency (sequential instead of parallel), hot-path bloat, TOCTOU anti-pattern, unbounded data structures. **Scaling issues:** code that works with 1 user but breaks with 100+ concurrent users (missing pagination, synchronous jobs, file-based sessions, unbounded SELECTs, missing locks on concurrent writes).

**Complete guidelines:** Read guidelines/performance.md AND guidelines/performance-2026.md in the skill directory and check the code against all rules described there.

**For native apps** (`FRAMEWORK` = ios/android/react-native/flutter): additionally `guidelines/native-mobile.md` section III — main-thread blocking, retain cycles / context leaks, list virtualization, image downsampling, app start. Web vitals (INP/LCP/CLS) do not apply there.

## Full-Audit Focus (additional)

N+1 queries (ORM relations without eager loading), queries in loops, missing memoization for expensive operations, repeated identical DB queries within a request lifecycle, missing aggregation functions where subselects would be needed. **Scaling check across the whole codebase:** connection pooling, queue usage, session backend, caching strategy, pagination of all lists, index coverage, horizontal scalability (statelessness check), bulk operations instead of single operations.

## Mandatory Verification BEFORE Flagging

- **Factory state semantics:** NEVER infer the meaning of a factory state from the method name. Before flagging, read the state definition and check it against the enum definition (example: `public()` can set `Visibility::Hidden`). Findings based on the name without checking the definition are not permitted.
- **FK index coverage:** Before every FK-index finding, check whether a composite index exists with the column as the leading column. Such a composite index covers the single-index lookup, an additional single index would be redundant. Findings without this check are false positives.
- **bun:sqlite statement caching:** `db.query(sql)` automatically caches the prepared statement per SQL string (a second call with the same SQL means no re-prepare). Only a bare `db.prepare()` gets re-prepared on every call. "Statement re-prepared per call" / "prepare in loop" is therefore NOT a valid finding for `db.query(...)` calls in a loop — only for `db.prepare(...)` in a loop.

## Project-Specific Context

{PROJECT_CONTEXT}
