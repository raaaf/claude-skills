---
name: delegate
description: "Default working mode for implementation tasks: the expensive session model (currently Opus 5.5) analyzes the task, asks clarifying questions on genuine ambiguities, writes an executor-ready mini-spec, and hands off implementation to a Sonnet executor. Afterward the expensive model reviews the result like a tech lead (reads the diff, re-runs criteria itself) and renders a verdict. Use when the user asks to implement, build, fix, change, or refactor code (even without typing /delegate). NOT for: questions/explanations (answer directly), planning discussions or large features needing a written plan (use /plan-it), audits (/audit), pure test writing (test-writer agent)."
when_to_use: "/delegate, implementiere, baue, aendere, fixe, setz das um, refactor this, build this feature"
argument-hint: "[Task in your own words; optional --worktree]"
effort: medium
allowed-tools:
  - Agent
  - Bash
  - Read
  - Grep
  - Glob
  - TodoWrite
  - AskUserQuestion
  - SendMessage
  - SendUserFile
---

# Delegate: Analysis (expensive) → Implementation (Sonnet) → Review (expensive)

**Start directly with Phase 0.**

> Frontmatter deliberately has NO `model:` field and NO `disable-model-invocation` (both documented exceptions to the repo convention): the skill inherits the session model (currently Opus 5.5) so analysis and review run on the strongest available model — an explicit `model:` pin (e.g. `opus`) would fix the skill to that model instead of tracking whatever the session runs on; `model: inherit` keeps analysis on it. Auto-trigger on implementation tasks is intentional, this is the default working mode.

Economics of this skill: the expensive model does the work where intelligence matters (understand, decide, specify, review). Sonnet generates the code volume. **HARD RULE: the orchestrator NEVER edits code itself** — Edit/Write are deliberately not in allowed-tools. Every code fix, even during review, goes through the executor.

## Phase 0: Scope Gate

The task is `$ARGUMENTS` (free text, plus an optional `--worktree` flag; empty when the user described the task in conversation instead). Classify it before any work happens:

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

- Translate the task into a verifiable goal ("add validation" → "tests for invalid inputs, then green").
- Targeted codebase scan: read affected files, **grep every identifier to be changed repo-wide** (parallel implementations, wizard duplicates — never assume there's only one spot).
- Identify conventions + an exemplar file (components instead of raw HTML, error pattern, test style).
- Determine the repo's verification commands (test runner, linter, typecheck) — do NOT guess, read from package.json/composer.json/CI. Only diff-scoped tests, never the full suite.
- **Test authority:** exactly ONE instance runs tests at a time. When the orchestrator runs tests itself, executor subagents must NOT start their own test runs (especially `composer test`/`composer test:parallel` — shared test databases corrupt each other). Decide up front who tests, and say so in the executor briefing. Whoever tests runs the command through `audit/bin/test-lock.sh`, the same mkdir-spinlock `/audit` uses: the briefing is a convention between this skill and its own executor, while the lock also holds against an `/audit` fix wave or a second session running in the same worktree, which the briefing cannot reach.
- List assumptions explicitly.

## Phase 2: Clarifying questions (only genuine ambiguities)

If multiple interpretations exist or an assumption would tip the outcome: **AskUserQuestion**, each question with the recommended answer first (Recommended pattern from /plan-it). Max 2 rounds. No questions whose answer is already in the code.

## Phase 3: Write the mini-spec

Inline (no file), executor-ready — the executor does not know this session:

```markdown
## Task: {Title}
**Goal:** {how success is recognized — measurable}
**Context:** {current state with file:line; conventions with exemplar: "error handling like src/lib/result.ts, exactly like that"}
**Affected files:** {final list}
**Out of Scope:** {related-looking files that will NOT be touched — with reason}
**Steps:**
1. {concrete, file + what} → verify: {command → expected result}
2. ...
**Bugfix?** Step 1 is ALWAYS: write a repro test that's red. Fix afterward, test green.
**Done criteria (all):** {test command → exit 0 including N new tests; lint/typecheck → exit 0; git status: only affected files}
**STOP conditions:** {current state deviates; verify fails twice; fix would need an out-of-scope file; core assumption wrong}
```

## Phase 3.5: Before-screenshot (visual tasks only)

Only when the mini-spec's affected files contain a frontend file (`FRONTEND_EXT_RE` in
`audit/bin/lib-git-base.sh` is the repo's single definition of that) or the task names a screen,
page or component. Everything else skips this phase silently.

The before-image can only be taken here, before the executor touches anything. That is the whole
reason this is its own phase and not part of the review.

**Screens catalog first, when the repo has one.** Before resolving a target the old way, check for
`.screens/config.json`:

```bash
for c in "$(dirname "${CLAUDE_SKILL_DIR:-/nonexistent}")/audit/bin/lib-orchestrator.sh" "$HOME/.claude/skills/audit/bin/lib-orchestrator.sh"; do [ -f "$c" ] && { . "$c"; break; }; done   # fresh shell per block: source the lib again
SCREENS_BIN="$(dirname "${CLAUDE_SKILL_DIR:-/nonexistent}")/screens/bin/screens.mjs"
[ -f "$SCREENS_BIN" ] || SCREENS_BIN="$HOME/.claude/skills/screens/bin/screens.mjs"
SCREENS_AFFECTED_IDS=""
if [ -f ".screens/config.json" ] && [ -f "$SCREENS_BIN" ]; then
  SCREENS_AFFECTED_IDS=$(node "$SCREENS_BIN" affected --files {mini-spec affected files, space-separated} \
    | sed -n 's/^AFFECTED_ID //p')
fi
orch_state_save SCREENS_BIN SCREENS_AFFECTED_IDS
```

No `.screens/config.json`, or it returns no ids: fall through to the target order below, unchanged.
One or more ids: run `node "$SCREENS_BIN" plan`, keep only the `PLAN_ENTRY <id> <status>` lines
whose id is in `SCREENS_AFFECTED_IDS` and whose status is not `unchanged`, then capture just those
through the same `up -> driver -> promote -> down` sequence `screens/SKILL.md` Phase 5 documents
(scoped to the platform(s) those ids belong to, and on the driver step to just these ids via that
platform's own per-entry filter, e.g. `--grep` on web) so "before" reflects HEAD. Copy the resulting
catalog PNGs (`screenshots/<platform>/<device-class>/<area>/<view>/<state>__<role>__<theme>.png`)
into `.claude/screenshots/before/` at the same relative path, then skip straight to Phase 4 (no
`capture-screens.sh` target to resolve).

Otherwise, resolve a target, in this order, and skip the phase when none resolves. Never guess a
URL: a screenshot of a connection error looks like a result.

1. A URL the user named in the task.
2. `.claude/launch.json` in the repo: a configuration's `url`, else `http://localhost:<port>`.
   Start the server first if nothing is serving; leave it running for Phase 5.
3. iOS: a booted simulator, under Simulator.app or Xcode 27's Device Hub alike (the script checks via `simctl`; it skips when there is none). Physical devices are not captured.

```bash
for c in "$(dirname "${CLAUDE_SKILL_DIR:-/nonexistent}")/audit/bin/lib-orchestrator.sh" "$HOME/.claude/skills/audit/bin/lib-orchestrator.sh"; do [ -f "$c" ] && { . "$c"; break; }; done   # fresh shell per block: source the lib again
CAPTURE=$(orch_helper capture-screens.sh) || CAPTURE=""
SCREEN_NAME="{slug for the screen, e.g. settings}"; CAPTURE_TARGET="{--url http://localhost:PORT/path | --ios}"
[ -n "$CAPTURE" ] && bash "$CAPTURE" --label before $CAPTURE_TARGET --name "$SCREEN_NAME"
orch_state_save SCREEN_NAME CAPTURE_TARGET   # Phase 5 captures the same thing
```

Phase 5 reads `SCREEN_NAME` and `CAPTURE_TARGET` back from the state, so the after-image is of the
same screen. A `CAPTURE_RESULT=SKIP` is not a failure and never blocks the task: say one line why,
and continue without an after-image, rather than pretending a comparison exists.

## Phase 4: Dispatch the executor (Sonnet)

Default: directly in the working tree (review happens before every commit). Isolated worktree (`isolation: worktree`) only when: the user says `--worktree`, the working tree contains foreign uncommitted changes, or the task is risky (migrations, > 5 files).

```
Agent(
  subagent_type: spec-executor,
  prompt: "{Executor preamble + report format from plan-it/references/execute-review.md, section Dispatch}
    {MINI_SPEC inline}"
)
```

The executor runs in the background (the default) and its report arrives as a completion notification. That is fine here, but **test authority follows the executor**: while it runs, the orchestrator does not start its own test run. Phase 5 verification begins after the report has arrived, not alongside it.

Preamble core (long form in the reference; substitute `{WORKDIR}`/`{COMMIT_RULE}` for the working-tree case — the executor does NOT commit here): step by step, confirm every verify, only affected files, respect STOP conditions instead of improvising, check every report claim against a real tool result, same-diff duplication self-check at block level before reporting (identical guard/resolver/logic blocks in two places of the executor's own diff → extract, even inside otherwise different method bodies — the audit-side check cannot catch executor duplicates early), exact report format (`STATUS / STEPS / STOPPED BECAUSE / FILES CHANGED / NOTES`).

Resolve the reference (same candidate logic as full-audit → audit):

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
4. READ new tests: does the test assert something meaningful, or does it game the criterion? For new classification/status tests (draft-vs-invited, state predicates): check BRANCH coverage, not just the happy path — mutation-check the fix line when in doubt (a happy-path test stays green while the new branch ships untested).
5. Judge documented deviation in NOTES on its merits; undocumented deviation = fail.

6. **After-screenshot.** When Phase 3.5's before set came from `/screens` (`SCREENS_AFFECTED_IDS`
   saved): rerun the same ids through `plan -> up -> driver -> promote -> down` (same scoped
   sequence as Phase 3.5), copy the catalog PNGs into `.claude/screenshots/after/` at the same
   relative path, and for each before/after pair say what changed visually in one or two sentences;
   a pair whose PNG hash did not change is listed as "unchanged" in the report (Phase 6) instead of
   attached. Otherwise, when Phase 3.5 captured a before-image via `capture-screens.sh`: rerun the
   same command with `--label after` and the same `--name`, against the same target, and describe
   the visual difference the same way; a pair of images with no reading of them is decoration. If
   the before-image was skipped, do not capture an after-image either: a single picture invites a
   comparison the run cannot make.

   ```bash
   for c in "$(dirname "${CLAUDE_SKILL_DIR:-/nonexistent}")/audit/bin/lib-orchestrator.sh" "$HOME/.claude/skills/audit/bin/lib-orchestrator.sh"; do [ -f "$c" ] && { . "$c"; break; }; done   # fresh shell per block
   orch_state_load   # SCREEN_NAME, CAPTURE_TARGET, SCREENS_BIN, SCREENS_AFFECTED_IDS from Phase 3.5
   if [ -n "${SCREENS_AFFECTED_IDS:-}" ]; then
     node "$SCREENS_BIN" plan   # PLAN_ENTRY lines for the same ids drive the same scoped up -> driver -> promote -> down as Phase 3.5, output into .claude/screenshots/after/
   else
     CAPTURE=$(orch_helper capture-screens.sh) || CAPTURE=""
     [ -n "$CAPTURE" ] && [ -n "${SCREEN_NAME:-}" ] && bash "$CAPTURE" --label after $CAPTURE_TARGET --name "$SCREEN_NAME"
   fi
   ```

**Verdict:**

| Verdict | Action |
|---|---|
| APPROVE | First stop the executor explicitly: `SendMessage` to it with "APPROVED. Stop now: no further edits, test runs, or process kills." and wait for its acknowledgement before anything else runs in this tree. On 2026-08-29 an executor that was never told to stop kept running into the `/audit` that followed and killed the audit's own test processes. Then the result report to the user (below). No commit — committing stays with the user (or /ship). |
| REVISE | SendMessage to the SAME executor with a concrete finding ("criterion 3 red: X; api.ts:90 swallows the error — result pattern per spec"). Max 2 rounds, then BLOCK. |
| BLOCK | Changes in the working tree: `git checkout` the affected files after asking the user, or leave them + finding. Finding + corrected spec to the user. |

**Run log (fires once a terminal verdict — APPROVE or BLOCK — is reached; REVISE is not terminal):**

```bash
for c in "$(dirname "${CLAUDE_SKILL_DIR:-/nonexistent}")/audit/bin/lib-orchestrator.sh" "$HOME/.claude/skills/audit/bin/lib-orchestrator.sh"; do [ -f "$c" ] && { . "$c"; break; }; done   # fresh shell per block: source the lib again
orch_run_log --skill delegate --outcome "{APPROVE|BLOCK}" \
  --counts "revision_rounds={N}"
```

## Phase 6: Result report

```
Delegate complete: {Title}
Verdict: APPROVE ({N} revision rounds)
Changed: {files with 1-line what}
Verified: {command → result, per done criterion}
Executor NOTES: {if relevant}
Visual: {what changed between before and after, or omit the line entirely}
Open: {nothing | deliberately deferred with reason}
```

When before/after images exist, attach them with `SendUserFile` (before first, then after) so the
user sees the change instead of reading a path. They live under `.claude/screenshots/`, which the
script adds to `.gitignore`, so they never reach a commit.

Tests red or criterion not achievable: say so honestly, never sugarcoat. Afterward normal rules apply: commit only on explicit request, /audit before push.
