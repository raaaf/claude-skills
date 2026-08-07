# Execute & Reconcile (Phase 5 Detail)

Follow-through for written plans. Core rule stays: the orchestrator never edits production code itself — the executor works in its own workspace, the orchestrator reviews and renders a verdict, like a tech lead who doesn't push to the branch themselves. Concept after shadcn/improve (closing-the-loop), adapted to our skill conventions.

**Two callers, two workspaces:** `/plan-it execute` ALWAYS dispatches into an isolated worktree (`{WORKDIR}` = worktree path, executor commits there). `/delegate` dispatches into the working tree by default (`{WORKDIR}` = repo root, executor does NOT commit — review happens before every commit; worktree only with `--worktree`/risk, then like plan-it). Substitute the spots marked `{WORKDIR}`/`{COMMIT_RULE}` below accordingly.

## `/plan-it execute <plan-file>` — Dispatch + Review Executor

### Preconditions (check all, otherwise stop and say why)

1. Repo is a git repository (worktree isolation needs it).
2. The plan file exists under `docs/plans/`.
3. Run the drift check yourself: `git diff --stat {PLANNED_AT_SHA}..HEAD -- {affected files}`. On drift: update the plan first (current state + refresh SHA), never hand a stale plan to an executor.

### Dispatch

Start ONE executor subagent: `subagent_type: general-purpose`, `isolation: worktree`, model `sonnet` (or whatever the user names: `/plan-it execute {plan} haiku`).

The prompt MUST include:

1. **The complete plan text/spec inline.** A worktree only contains committed files — an uncommitted plan isn't readable there. Never assume, always inline it (applies to both callers).
2. The executor preamble:

> You are the executor for the following plan. Follow it step by step.
> Run every verify criterion and confirm the expected result before
> moving on. Touch only the affected-files list. If a STOP condition
> occurs: stop immediately and report, do not improvise.
> {COMMIT_RULE: Worktree -> "Commit your work in the worktree (Conventional
> Commits)." | Working tree (/delegate default) -> "Do NOT commit — the
> changes stay uncommitted, review happens before every commit."}
> Before reporting, check every claim against a real tool result from this
> session — clearly name any failed or skipped verifications.
> Before reporting, run the same-diff duplication self-check on your own
> diff, at BLOCK level: if the same method/logic sequence OR the same
> guard/resolver/error-mapping block appears at >= 2 places you touched
> (even inside two otherwise different method bodies), extract or delegate
> the shared logic as part of the task instead of finishing. The check is
> structural (statement sequence, branching shape), not name-based.
> Do not invent machinery around the plan: no helper scripts, state
> files, progress ledgers, scoreboards, or verification harnesses beyond
> what the plan itself names — verification belongs to the review, state
> to the orchestrator. If a step seems to require such tooling, treat it
> as a STOP condition and report instead of building it.
> Answer exactly in the report format.

3. The report format:

```
STATUS: COMPLETE | STOPPED
STEPS: per step — done/skipped + verify result
STOPPED BECAUSE: (only if STOPPED) which STOP condition, what was observed
FILES CHANGED: list
NOTES: deviations, surprises, judgment calls
```

Note on fresh worktrees (not applicable in the working-tree case): git history yes, `node_modules`/build artifacts no — the executor must install dependencies first. That's expected, not a deviation.

### Review (the orchestrator's actual work)

Do NOT trust the executor's report — verify it yourself (all commands in `{WORKDIR}`; in the working-tree case that's the repo root without `-C`):

1. **Re-run every done criterion in `{WORKDIR}`.**
2. **Scope compliance:** `git -C {WORKDIR} diff --stat` against the affected-files list. Any file outside it = review fail.
3. **Read the complete diff** and judge it against the plan's "Problem"/"Goal" and the conventions section.
4. **Read new tests:** A test that asserts nothing meaningful passes `npm test` and proves nothing — executors game criteria.

**Judge documented deviations on merit, don't block reflexively.** "Do not improvise" prevents silent drift; an executor that minimally works around a real obstacle and explains it in NOTES acted correctly — approve if it serves the plan's goal and stays in scope. UNDOCUMENTED deviations are review fails.

### Verdict

| Verdict | When | Action |
|---|---|---|
| APPROVE | Criteria green, scope clean, quality fits | Present to the user: diff summary, workspace (worktree path + branch, or working-tree status), NOTES. **Merging/committing is the user's decision — never merge/push/commit yourself.** |
| REVISE | Fixable gaps | SendMessage to the same executor with concrete, actionable feedback. Max 2 revision rounds, then BLOCK. |
| BLOCK | STOP condition, scope violation, revisions exhausted | Rework the plan with what was learned; report to the user what happened and what changed in the plan. |

Verification commands in `{WORKDIR}` are allowed — in the worktree case regardless (isolated, disposable); in the working-tree case only read-only/transient commands (tests, lint), nothing that writes artifacts outside ignored directories.

## `/plan-it reconcile` — Maintain the Plan Backlog

Processes what has happened since the last session. Read `docs/plans/*.md` (plus `.claude/plans/logs/` for context), per plan:

- **Implemented** (done criteria hold on current HEAD, spot-check the cheap ones): mark as implemented in the plan. Never delete plan files — they are the record.
- **Drifted** (drift check trips): check whether the problem still exists at all (may have been fixed incidentally). If it does: refresh the current-state sections + planned-at SHA. If it doesn't: mark as done/moot with a 1-line justification.
- **Blocked/stalled:** investigate the obstacle in the code; rewrite the plan around it or discard it with a justification.

Closing report: what's verified as implemented, what was refreshed, what was discarded, what is executable NOW.
