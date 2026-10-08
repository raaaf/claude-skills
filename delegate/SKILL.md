---
name: delegate
description: "Default working mode for implementation tasks: the expensive session model (currently Opus 5.5) analyzes the task, asks clarifying questions on genuine ambiguities, writes an executor-ready mini-spec, and hands off implementation to a Sonnet executor. Afterward the expensive model reviews the result like a tech lead (reads the diff, re-runs criteria itself) and renders a verdict. Use when the user asks to implement, build, fix, change, or refactor code (even without typing /delegate). NOT for: questions/explanations (answer directly), planning discussions or large features needing a written plan (use /plan-it), audits (/audit), pure test writing (test-writer agent)."
when_to_use: "/delegate, implementiere, baue, aendere, fixe, setz das um, refactor this, build this feature"
argument-hint: "[Task in your own words; optional --worktree, --no-oracle]"
effort: high
allowed-tools:
  - Agent
  - Bash
  - Read
  - Grep
  - Glob
  - TodoWrite
  - AskUserQuestion
  - SendMessage
  - ToolSearch
---

# Delegate: Analysis (expensive) → Implementation (Sonnet) → Review (expensive)

**Start directly with Phase 0.**

> Frontmatter deliberately has NO `model:` field and NO `disable-model-invocation` (both documented exceptions to the repo convention): the skill inherits the session model (currently Opus 5.5) so analysis and review run on the strongest available model — an explicit `model:` pin (e.g. `opus`) would fix the skill to that model instead of tracking whatever the session runs on; `model: inherit` keeps analysis on it. Auto-trigger on implementation tasks is intentional, this is the default working mode.

Economics of this skill: the expensive model does the work where intelligence matters (understand, decide, specify, review). Sonnet generates the code volume. **HARD RULE: the orchestrator NEVER edits code itself** — Edit/Write are deliberately not in allowed-tools. Every code fix, even during review, goes through the executor.

## Phase 0: Scope Gate

The task is `$ARGUMENTS` (free text, plus optional `--worktree` and `--no-oracle` flags; empty when the user described the task in conversation instead). `--no-oracle` skips Phase 3.5. Classify it before any work happens:

| Classification | Signal | Action |
|---|---|---|
| Not an implementation task | question, explanation, opinion, debugging discussion | Leave the skill, answer normally |
| Trivial | 1 file, < ~10 lines, mechanical (typo, rename, config value) | Skip phases 1-2, 3-line mini-spec, go straight to phase 3 |
| Normal | clear task, 1-5 files, no architecture decision | full flow |
| Large / architectural | new data model, > ~5 files, unclear framing, multiple valid approaches, breaking change | **AskUserQuestion:** "/plan-it first (Recommended — plan + challenges, then /plan-it execute)" vs. "Implement directly via /delegate". If plan-it: leave the skill, /plan-it takes over. |

Once classified as Trivial, Normal, or Large-with-delegate-chosen (i.e. this run is actually going to implement something, not leaving the skill), before Phase 1 or Phase 3 begins — run-ledger start marker (see audit/bin/run-log.sh header):

```bash
for c in "$(dirname "${CLAUDE_SKILL_DIR:-/nonexistent}")/audit/bin/lib-orchestrator.sh" \
         "$HOME/.claude/skills/audit/bin/lib-orchestrator.sh"; do
  [ -f "$c" ] && { . "$c"; break; }
done
type orch_run_log >/dev/null 2>&1 || echo "lib-orchestrator.sh not found; run log and helpers unavailable (skill continues)"
orch_run_log --start --skill delegate
```

## Phase 1: Analysis (orchestrator, expensive)

- **Plan file given?** When the user points at a plan file (`docs/plans/...`), use its `## Delegate spec` section as the Phase 3 mini-spec: check it against the live code (drift check from the plan's Meta), skip Phase 2 unless the check trips, and go to Phase 4. Do not re-specify.
- Translate the task into a verifiable goal ("add validation" → "one test per invalid-input branch, then green"; "wire up UI" → "live walkthrough, no test"). Tests follow CLAUDE.md §6: required for bugfix repro and new branching logic, never for rendering, wiring, getters or mock-call checks. Zero new tests is a valid spec.
- Targeted codebase scan: read affected files, **grep every identifier to be changed repo-wide** (parallel implementations, wizard duplicates — never assume there's only one spot).
- Identify conventions + an exemplar file (components instead of raw HTML, error pattern, test style).
- Determine the repo's verification commands (test runner, linter, typecheck) — do NOT guess, read from package.json/composer.json/CI. Only diff-scoped tests, never the full suite.
- **Test authority:** exactly ONE instance runs tests at a time. When the orchestrator runs tests itself, executor subagents must NOT start their own test runs (especially `composer test`/`composer test:parallel` — shared test databases corrupt each other). Decide up front who tests, and say so in the executor briefing. Whoever tests runs the command through `audit/bin/test-lock.sh`, the same mkdir-spinlock `/audit` uses: the briefing is a convention between this skill and its own executor, while the lock also holds against an `/audit` fix wave or a second session running in the same worktree, which the briefing cannot reach.
- List assumptions explicitly.

## Phase 2: Clarifying questions (only genuine ambiguities)

If multiple interpretations exist or an assumption would tip the outcome: **AskUserQuestion**, each question with the recommended answer first (Recommended pattern from /plan-it). Max 2 rounds. No questions whose answer is already in the code.

## Phase 3: Write the mini-spec

Inline (no file; when a plan's `## Delegate spec` exists, reuse it verbatim, see Phase 1), executor-ready — the executor does not know this session:

```markdown
## Task: {Title}
**Goal:** {how success is recognized — measurable}
**Context:** {current state with file:line; conventions with exemplar: "error handling like src/lib/result.ts, exactly like that"}
**Affected files:** {final list, each with its line range(s) and any known symbol/function name the step touches — e.g. `src/lib/result.ts:40-58 (formatResult)`}
**Out of Scope:** {related-looking files that will NOT be touched — with reason}
**Steps:**
1. {concrete, file + what} → verify: {command → expected result}
2. ...
**Bugfix?** Step 1 is ALWAYS: write a repro test that's red. Fix afterward, test green.
**Logic test steps:** mark every step whose verify names a new or changed test for a calculation, parsing, validation, date, status or matching rule, or a bugfix repro, with `[logic test]`. Rendering, wiring and mock-call tests never qualify.
**Done criteria (all):** {test command → exit 0; new tests only where a step names one, 0 is a valid count; lint/typecheck → exit 0; git status: only affected files}
**STOP conditions:** {current state deviates; verify fails twice; fix would need an out-of-scope file; core assumption wrong}
```

## Phase 3.5: Oracle tests (working-tree mode only)

Skip with a one-line note (report `oracle=skipped`) when: the mini-spec has no `[logic test]` step, `--no-oracle` was given, or the run uses `--worktree` (a worktree holds only committed files; `/plan-it execute` keeps its own flow). Otherwise the tests come from a separate agent that sees the contract, not the implementation. Detail, contract rules, triage: `references/oracle.md`.

1. Write the **contract** from the mini-spec, the user's request and public signatures/docblocks only, never from implementation bodies read in Phase 1. Every line carries its source (`spec`, `request`, `docblock`). Include the real project setup (factory states, exemplar test file, helpers).
2. Dispatch `Agent(subagent_type: test-writer, run_in_background: false)` with "oracle mode", the contract, and an output cap (files written plus assumptions, under 150 words).
3. Red check: run each oracle file through `test-lock.sh`. Accepted: assertion failure, or a missing-symbol error for a not-yet-existing unit. Parse error or green: one retry with the error text. Still wrong: fall back to the old flow (executor writes the tests, Phase 5 step 4), report `oracle=fallback`. Never BLOCK here.
4. On success snapshot the files and save the run id:

```bash
for c in "$(dirname "${CLAUDE_SKILL_DIR:-/nonexistent}")/audit/bin/lib-orchestrator.sh" "$HOME/.claude/skills/audit/bin/lib-orchestrator.sh"; do [ -f "$c" ] && { . "$c"; break; }; done   # fresh shell per block: source the lib again
orch_resolve_audit_root
ORACLE_RUN_ID="delegate-$(date +%s)-$$"
ORACLE_EXPECTED=1
bash "$AUDIT_BIN/oracle-lock.sh" snapshot --run "$ORACLE_RUN_ID" {ORACLE_FILES}
orch_state_save ORACLE_RUN_ID ORACLE_EXPECTED
```

## Phase 4: Dispatch the executor (Sonnet)

Default: directly in the working tree (review happens before every commit). Isolated worktree (`isolation: worktree`) only when: the user says `--worktree`, the working tree contains foreign uncommitted changes, or the task is risky (migrations, > 5 files).

```
Agent(
  subagent_type: spec-executor,
  prompt: "{Executor preamble + report format from plan-it/references/execute-review.md, section Dispatch}
    {MINI_SPEC inline}"
)
```

When Phase 3.5 produced oracle tests, the briefing lists them as **locked, read-only** (with `tests/Pest.php`, `tests/TestCase.php`, `phpunit.xml`) and adds the STOP condition "a locked test looks wrong: stop and report why". Contract gap: test-writer amends and the orchestrator re-snapshots. Executor error: REVISE.

The executor runs in the background (the default) and its report arrives as a completion notification. That is fine here, but **test authority follows the executor**: while it runs, the orchestrator does not start its own test run. Phase 5 verification begins after the report has arrived, not alongside it.

Preamble core (long form in the reference; substitute `{WORKDIR}`/`{COMMIT_RULE}` for the working-tree case — the executor does NOT commit here): step by step, confirm every verify, only affected files, do not explore beyond the mini-spec's listed files except to grep an identifier's usages, respect STOP conditions instead of improvising, if 40 tool calls pass without a verify criterion turning green stop and report what blocks, check every report claim against a real tool result, same-diff duplication self-check at block level before reporting (identical guard/resolver/logic blocks in two places of the executor's own diff → extract, even inside otherwise different method bodies — the audit-side check cannot catch executor duplicates early), exact report format (`STATUS / STEPS / STOPPED BECAUSE / FILES CHANGED / NOTES`).

Resolve the reference (same candidate logic as audit):

```bash
for c in "$(dirname "${CLAUDE_SKILL_DIR:-/nonexistent}")/plan-it" "$HOME/.claude/skills/plan-it"; do
  [ -f "$c/references/execute-review.md" ] && { EXEC_REF="$c/references/execute-review.md"; break; }
done
```

## Phase 5: Review (orchestrator, expensive)

Do NOT trust the executor report — verify it yourself (checklist = execute-review.md, section Review):

1. Read the full `git diff`; judge against the goal + conventions (does it read like the rest of the repo?).
2. Re-run every done criterion yourself (Bash).
3. Scope: `git diff --stat` against the affected-files list. A file outside it = fail.
4. READ new tests: does the test assert something meaningful, or does it game the criterion? For new classification/status tests (draft-vs-invited, state predicates): check BRANCH coverage, not just the happy path — mutation-check the target line of every new test (invert it, the test must go red; a happy-path test stays green while the new branch ships untested). A test that only asserts mock calls, mounts a component, or has no assertion = fail.
5. Judge documented deviation in NOTES on its merits; undocumented deviation = fail.
6. **Oracle check** (only when `ORACLE_EXPECTED=1`): `bash "$AUDIT_BIN/oracle-lock.sh" check --run "$ORACLE_RUN_ID"`. `ORACLE_RESULT=CHANGED` = review fail (name the `ORACLE_CHANGED=` files; for a shared setup file check `git log` first, another session may have edited it). `NONE` while expected = review fail (a lost snapshot is not a pass). Also run `bash "$AUDIT_BIN/check-silencing.sh"` (catches `skip`/`markTestSkipped` workarounds).
7. **Mutation run** (only when the diff touches a file matched by the project's `.claude/mutation-targets`): `bash "$AUDIT_BIN/mutate.sh" "$PWD" HEAD --oracle-files "{ORACLE_FILES}"`. Triage the survivors and run at most one informed test round, then one confirmation run; procedure in `references/oracle.md`. `SKIP`, `TIMEOUT` and `ERROR` never block; report `ERROR` (with its `MUTATE_ERROR` line) in the result and log `mutate=ERROR`.

**Verdict:**

| Verdict | Action |
|---|---|
| APPROVE | First stop the executor explicitly: `SendMessage` to it with "APPROVED. Stop now: no further edits, test runs, or process kills." and wait for its acknowledgement before anything else runs in this tree. On 2026-08-29 an executor that was never told to stop kept running into the `/audit` that followed and killed the audit's own test processes. Then the result report to the user (below). No commit — committing stays with the user (or /ship). |
| REVISE | SendMessage to the SAME executor with a concrete finding ("criterion 3 red: X; api.ts:90 swallows the error — result pattern per spec"). Max 2 rounds, then BLOCK. |
| BLOCK | Changes in the working tree: `git checkout` the affected files after asking the user, or leave them + finding. Finding + corrected spec to the user. |

**Run log (fires once a terminal verdict — APPROVE or BLOCK — is reached; REVISE is not terminal):**

```bash
for c in "$(dirname "${CLAUDE_SKILL_DIR:-/nonexistent}")/audit/bin/lib-orchestrator.sh" "$HOME/.claude/skills/audit/bin/lib-orchestrator.sh"; do [ -f "$c" ] && { . "$c"; break; }; done   # fresh shell per block: source the lib again
orch_resolve_audit_root
orch_state_load
bash "$AUDIT_BIN/oracle-lock.sh" clear --run "${ORACLE_RUN_ID:-none}"   # drop the snapshot at every terminal verdict
orch_run_log --skill delegate --outcome "{APPROVE|BLOCK}" \
  --counts "revision_rounds={N},oracle={used|fallback|skipped},mutate={OK|SKIP|TIMEOUT|ERROR|none},survivors={N}"
```

## Phase 6: Live walkthrough (visual tasks only)

Only for visual tasks (the mini-spec's affected files contain a frontend file, or the task names a
screen, page or component) and only after the verdict is APPROVE. Non-visual tasks skip this phase
silently, no note in the report.

Load the needed tools via `ToolSearch` in one batch before starting: for a web project,
`mcp__claude-in-chrome__*` (`tabs_context_mcp`, `tabs_create_mcp`, `navigate`, `computer`,
`read_page`); for an iOS project, `mcp__Claude_Code_iOS_Simulator__control`.

- **Web:** start the dev server via the project's own mechanism (`.claude/launch.json` or the
  project's run command) if nothing is serving, and confirm the URL responds before opening a tab.
- **iOS:** `attach` to the booted simulator, then navigate via `open_url`/`tap`.

Step by step, one completed item at a time, with the user's approval before moving to the next:

1. Open one tab (web) or navigate to the screen (iOS) for that item.
2. Say in one sentence what changed and where to look.
3. `AskUserQuestion`: "Passt" / "Passt nicht, Anmerkung".
4. "Passt nicht" → record it as a rework item: SendMessage the concrete note to the executor as a
   REVISE finding, re-run Phase 5's review on the fix, then resume the walkthrough at the next item.
5. Only after the current item is answered, continue with the next.

## Phase 7: Result report

```
Delegate complete: {Title}
Verdict: APPROVE ({N} revision rounds)
Changed: {files with 1-line what}
Verified: {command → result, per done criterion}
Executor NOTES: {if relevant}
Visual: {live walkthrough outcome per item, or omit the line for non-visual tasks}
Open: {nothing | deliberately deferred with reason}
```

Tests red or criterion not achievable: say so honestly, never sugarcoat. Afterward normal rules apply: commit only on explicit request, /audit before push.
