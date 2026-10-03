# Review phase: built-in /code-review in a review worktree

Read by `audit/SKILL.md` Phase 2. The core of `/audit`: the built-in `/code-review high` reviews the
diff, one checklist agent covers what it misses.

## Contents
- Why
- Target form: a review worktree
- Prompt and reply contract (a)
- Checklist agent (b)
- Reply handling

## Why

Decided 2026-10-02/03. The custom per-dimension pipeline used about 45% of the weekly usage limit in
the 7 days to 2026-10-03 (single runs 8-78 M weighted tokens). A blind benchmark on 5 historical diffs
with 6 known Criticals: the built-in `/code-review high` found all 3 security Criticals and 1 of 2
architecture ones, found 2 serious issues the pipeline missed (a refund without `reverse_transfer`, an
unauthenticated `mapPins`), and missed one privacy Critical (map tiles from a third party without
consent) and one policy bypass. It costs about 0.1-1.7 M per run. The sensitive-path checklist
(`sensitive-checklist.md`) covers the two misses. A pre-push audit is a PR review.

`/security-review` is not used: it diffs commits against `origin/HEAD`, and repairing a missing
`origin/HEAD` would move a ref every worktree shares.

## Target form: a review worktree

The `code-review` skill reviews "the current diff", or a PR/branch/path target. None of those equals
the audit scope (`BASE_REF..HEAD` plus uncommitted changes), so the scope is materialized:
`orch_review_worktree_create` makes a temporary detached worktree at `BASE_REF` under `$TMPDIR`,
applies `git diff --binary BASE_REF` of the main tree and copies the untracked non-ignored scope files
over (intent-to-add). The whole scope is the worktree's UNCOMMITTED diff and the user's tree is never
touched. Call the two helpers by name only: `audit/hooks/block-worktree-wide-git.sh` denies the
forced worktree-remove git command whenever it is typed into a Bash call.
`orch_review_worktree_remove` also runs after a failure.

## Prompt and reply contract (a)

ONE `Agent` call, `subagent_type: general-purpose`, `model: sonnet`, `run_in_background: false`:

```text
cd {REVIEW_WORKTREE}. It is a temporary worktree whose uncommitted diff is exactly the change to review.
Invoke the Skill tool with skill "code-review" and args "high" on the current diff. Pass no --comment
and no --fix. Do not edit any file, do not post comments, do not leave {REVIEW_WORKTREE}.
Reply with ONLY this JSON (an empty list is valid):
{"findings":[{"id":"code_review-0-N","dimension":"code_quality","files":[{"path":"...","lines":"12-18"}],
"issue":"max 50 words, file:line references, no code, never a secret value","severity":null}]}
severity is the skill's own wording (Critical|Important|Minor) or null.
```

## Checklist agent (b)

Only when `orch_sensitive_paths` returned paths. ONE `Agent` call, `subagent_type: code-reviewer`,
`model: sonnet`, `run_in_background: false`, prompt = `sensitive-checklist.md` with `{WORKTREE}` and
`{SENSITIVE_PATHS}` filled in. Same JSON contract, ids `sensitive-N`, `dimension: security`.

## Reply handling

1. A reply that is not the JSON, a failed dispatch, a failed worktree creation or a missing Skill tool:
   the review is incomplete. Log it under `## Not completed` with the reason; it blocks the marker.
2. `severity: null` is the orchestrator's call in Phase 3 (Critical, Important or Minor).
3. A finding from (a) and one from (b) that name the same file within 20 lines and the same problem are
   one finding; keep the one with the clearer description.
4. Source tags in the log: `[code_review]` for (a), `[sensitive]` for (b), `[pre-check]` for scripts.
