---
name: delegate
description: "Default working mode for implementation tasks: the expensive session model (Fable/Opus) analyzes the task, asks clarifying questions on genuine ambiguities, writes an executor-ready mini-spec, and hands off implementation to a Sonnet executor. Afterward the expensive model reviews the result like a tech lead (reads the diff, re-runs criteria itself) and renders a verdict. Use when the user asks to implement, build, fix, change, or refactor code (even without typing /delegate). NOT for: questions/explanations (answer directly), planning discussions or large features needing a written plan (use /plan-it), audits (/audit), pure test writing (test-writer agent)."
when_to_use: "/delegate, implementiere, baue, aendere, fixe, setz das um, refactor this, build this feature"
argument-hint: "[Task in your own words; optional --worktree]"
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
---

# Delegate: Analysis (expensive) → Implementation (Sonnet) → Review (expensive)

**EXECUTE IMMEDIATELY — start directly with Phase 0.**

> Frontmatter deliberately has NO `model:` field and NO `disable-model-invocation` (both documented exceptions to the repo convention): the skill inherits the session model (Fable/Opus) so analysis and review run on the strongest available model — `model: opus` would downgrade a Fable session. Auto-trigger on implementation tasks is intentional, this is the default working mode.

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
RUN_LOG=""
for c in "$(dirname "${CLAUDE_SKILL_DIR:-/nonexistent}")/audit/bin/run-log.sh" \
         "$HOME/.claude/skills/audit/bin/run-log.sh" \
         "$HOME/.claude/skills/claude-skills/audit/bin/run-log.sh"; do
  [ -f "$c" ] && { RUN_LOG="$c"; break; }
done
[ -n "$RUN_LOG" ] && bash "$RUN_LOG" --start --skill delegate
```

## Phase 1: Analysis (orchestrator, expensive)

- Translate the task into a verifiable goal ("add validation" → "tests for invalid inputs, then green").
- Targeted codebase scan: read affected files, **grep every identifier to be changed repo-wide** (parallel implementations, wizard duplicates — never assume there's only one spot).
- Identify conventions + an exemplar file (components instead of raw HTML, error pattern, test style).
- Determine the repo's verification commands (test runner, linter, typecheck) — do NOT guess, read from package.json/composer.json/CI. Only diff-scoped tests, never the full suite.
- **Test authority:** exactly ONE instance runs tests at a time. When the orchestrator runs tests itself, executor subagents must NOT start their own test runs (especially `composer test`/`composer test:parallel` — shared test databases corrupt each other). Decide up front who tests, and say so in the executor briefing.
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

## Phase 4: Dispatch the executor (Sonnet)

Default: directly in the working tree (review happens before every commit). Isolated worktree (`isolation: worktree`) only when: the user says `--worktree`, the working tree contains foreign uncommitted changes, or the task is risky (migrations, > 5 files).

```
Agent(
  subagent_type: general-purpose,
  model: sonnet,
  prompt: "{Executor preamble + report format from plan-it/references/execute-review.md, section Dispatch}
    {MINI_SPEC inline}"
)
```

The executor runs in the background (default since Claude Code v2.1.198) and its report arrives as a completion notification. That is fine here, but **test authority follows the executor**: while it runs, the orchestrator does not start its own test run. Phase 5 verification begins after the report has arrived, not alongside it.

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
4. READ new tests: does the test assert something meaningful, or does it game the criterion?
5. Judge documented deviation in NOTES on its merits; undocumented deviation = fail.

**Verdict:**

| Verdict | Action |
|---|---|
| APPROVE | Result report to the user (below). No commit — committing stays with the user (or /ship). |
| REVISE | SendMessage to the SAME executor with a concrete finding ("criterion 3 red: X; api.ts:90 swallows the error — result pattern per spec"). Max 2 rounds, then BLOCK. |
| BLOCK | Changes in the working tree: `git checkout` the affected files after asking the user, or leave them + finding. Finding + corrected spec to the user. |

**Run log (fires once a terminal verdict — APPROVE or BLOCK — is reached; REVISE is not terminal):**

```bash
RUN_LOG=""
for c in "$(dirname "${CLAUDE_SKILL_DIR:-/nonexistent}")/audit/bin/run-log.sh" \
         "$HOME/.claude/skills/audit/bin/run-log.sh" \
         "$HOME/.claude/skills/claude-skills/audit/bin/run-log.sh"; do
  [ -f "$c" ] && { RUN_LOG="$c"; break; }
done
[ -n "$RUN_LOG" ] && bash "$RUN_LOG" --skill delegate --outcome "{APPROVE|BLOCK}" \
  --counts "revision_rounds={N}"
```

## Phase 6: Result report

```
Delegate complete: {Title}
Verdict: APPROVE ({N} revision rounds)
Changed: {files with 1-line what}
Verified: {command → result, per done criterion}
Executor NOTES: {if relevant}
Open: {nothing | deliberately deferred with reason}
```

Tests red or criterion not achievable: say so honestly, never sugarcoat. Afterward normal rules apply: commit only on explicit request, /audit before push.
