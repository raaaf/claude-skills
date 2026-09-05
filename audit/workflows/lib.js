// audit/workflows/lib.js
//
// Shared helper for find.js and fix.js: both scripts dispatch an agent() call
// and must treat a null result (thrown/aborted agent, per the Workflow-Kontrakt
// in references/finding-schema.md) as a logged, non-fatal event rather than a
// silent drop. Kept as one function instead of duplicating the same
// if (!result) { log(...); } guard in every call site of both workflow scripts.

export function warnIfNull(log, result, message) {
  if (!result) {
    log(message);
    return true;
  }
  return false;
}
