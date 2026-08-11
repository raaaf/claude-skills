---
name: diagnose
description: |
  Systematic bug diagnosis workflow. Creates a fast, shareable reproduction signal first,
  then minimizes, hypothesizes, instruments, fixes, and adds a regression test. Use when a
  bug is reported, something is broken after a recent change, or a previous fix attempt failed.
  Never hypothesizes before reproducing.
when_to_use: "/diagnose, bug report, something is broken, fix attempt failed, can't reproduce, regression, debugging"
argument-hint: "[optional: brief bug description]"
model: sonnet
effort: high
allowed-tools:
  - Read
  - Edit
  - Write
  - Bash
  - Grep
  - Glob
---

# Diagnose

Structured debugging. Reproduce first; everything else depends on it.

## Phase 0: Intake

`$ARGUMENTS` holds the bug description passed with the invocation (empty when none was given). Determine (from it, the conversation, or by asking):

1. What was expected?
2. What actually happened (exact error, output, behavior)?
3. When did it last work (commit, deploy, date)?
4. Deterministic or flaky?

If the user already provided this: skip directly to Phase 1.

If information is missing: ask for it before touching code. A diagnosis without a clear
failure description is guesswork.

## Phase 1: Reproduce

**Goal:** One command, one output, reproducible every time.

1. Read the relevant entry point (route, controller, component, test). Max 2 files.
2. Run the smallest command that should trigger the failure:
   ```bash
   # e.g. php artisan test --filter=FooTest
   # e.g. node test.js
   # e.g. curl -s http://localhost/api/foo
   ```
3. Confirm: does the actual output match the reported failure?

**If you cannot reproduce: STOP.**

Report exactly what you ran, what came back, and what you expected. Ask the user for
the missing context. Do not proceed to Phase 2 with an unconfirmed repro.

**Rule out the tool before you believe the symptom.** A repro attempt that fails or
hangs is evidence about your setup until proven otherwise. One logout hunt burned an
evening on three independent tooling artifacts, each of which looked exactly like the
reported bug: browser-extension clicks that fire no page events (the button "does
nothing"), a text locator that silently waits on a hidden duplicate of the element and
times out, and a simulator serving a cached page after a rebuild (the fix "has no
effect"). Only a test seam that injected the hanging dependency isolated the real
defect.

So before a failed repro becomes a hypothesis: reproduce the same step through a second,
independent mechanism (a trusted-click browser test instead of an extension, a
container-scoped selector instead of a text match, a cache-busted URL instead of the
same one). If the two mechanisms disagree, you are debugging your tools. Prefer a test
seam that injects the suspect dependency over any UI-level repro, since it fails for
exactly one reason.

Document the repro signal:
```
Repro:
  Command: {command}
  Output:  {output or error}
```

## Phase 2: Minimize

Strip the repro to the smallest failing case:

- Remove environment variables, extra data, setup steps not needed to trigger the failure
- Identify the exact file, function, and line where the failure manifests
- If it is a test: identify which assertion fails and the actual vs expected values
- If it is a runtime error: identify the first stack frame in project code

Updated repro signal:
```
Minimal repro:
  Command: {command}
  Fails at: {file}:{line}
  Reason:   {one line}
```

## Phase 3: Hypothesize

Based only on what the minimal repro revealed:

1. List 2-3 hypotheses ranked by probability
2. For each: what evidence supports it? What would disprove it?
3. Pick the top candidate

Do not read additional files during this phase. Hypotheses come from the repro, not
from scanning the codebase.

Example format:
```
Hypotheses:
1. (most likely) {file}:{line}: {what might be wrong}; evidence: {from repro output}
2. {file}:{line}: {what might be wrong}; evidence: {from repro output}
3. {file}:{line}: {what might be wrong}; evidence: {from repro output}
```

## Phase 4: Instrument

Add targeted instrumentation to test the top hypothesis:

- Use the project's debug output: `dd()` (Laravel), `console.log()`, `var_dump()`, `print()`
- Two points maximum: one before the suspected failure, one inside it
- Run the Phase 1 repro command again; capture instrumented output

Outcome:
- Hypothesis confirmed: proceed to Phase 5
- Hypothesis disproved: return to Phase 3 with the next hypothesis

Never add more than 3 instrumentation points per iteration.

## Phase 5: Fix

1. Read the target file (if not already read in Phase 1)
2. Apply the minimal fix (surgical change, no unrelated edits)
3. Re-run the Phase 1 repro command -- must pass now
4. If the fix breaks something else: document the regression, return to Phase 3

## Phase 6: Regression Test

Write a test that would have caught this bug before the fix was applied.

Rules:
- Test behavior via the public interface, not the implementation detail that was fixed
- The test must fail on the unfixed code and pass on the fixed code
- Use the project's test runner (detected from `package.json`, `composer.json`, `pyproject.toml`)

```bash
# Run only the new test
```

If no test runner exists in the project: document the manual repro steps as a test plan instead.

## Phase 7: Cleanup

Remove all instrumentation added in Phase 4.

Check:
```bash
grep -r "dd(\|console\.log\|var_dump\|print_r\|debugger" {changed_files}
```

No debug output in committed code.

## Summary Output

```
Diagnose complete

Bug:       {one-line description}
Root cause: {file}:{line}: {what went wrong and why}
Fix:       {what was changed}
Test:      {test file}:{line} (run: {command})
Repro was: {the Phase 1 command}
```
