# Built-in review in the pre-push gate (Phase 2)

Decided 2026-10-02. Read by `audit/SKILL.md` Phase 2. Covers the built-in `/code-review high` that runs
next to `find.js` on every code diff and how its findings reach the finding-verifier.

## Why

Blind benchmark on 5 historical diffs with 6 known audit Criticals: Claude Code's built-in
`/code-review high` found all 3 security Criticals and 1 of 2 architecture Criticals. It missed the
privacy one (OSM tiles without consent) and one architecture policy bypass, and it found 2 serious
issues the audit never reported (a refund without `reverse_transfer`, an unauthenticated `mapPins`).
The own dimensions in the gate (`security`, `privacy`, `architecture`) cover the misses, the built-in
review covers the blind spots of the dimension prompts. The other ten dimensions cost about 40% of the
weekly usage and run nightly.

**security-review: not in the gate until verified to review the full scope (2026-10-02).** `/security-review`
diffs commits against `origin/HEAD`, it did not run once in the benchmark, and repairing a missing
`origin/HEAD` with `git remote set-head` would move a ref the main repo and every worktree share.
`orch_sensitive_paths` (lib, tested) stays for a later dispatch; nothing calls it today.

## When it runs

Only when `find.js` runs: `ALLE_DATEIEN` (filtered set) is non-empty. A `DIFF_CLASS=prose` diff and an
empty filtered set run no review (`references/prose-gate.md`). It also runs with `AUDIT_FIX_SCOPE=none`
(find and log only).

## Target form: a review worktree (chosen 2026-10-02)

The `code-review` skill reviews "the current diff", or a PR/branch/path target. None of the targets
equals the audit scope (`BASE_REF..HEAD` plus uncommitted changes, filtered file set), and a prompt that
merely names a diff relies on the skill honoring it. So the scope is materialized, exactly as in the
benchmark that worked: `orch_review_worktree_create` makes a temporary detached worktree at `BASE_REF`
under `$TMPDIR`, applies `git diff --binary BASE_REF` of the main tree (commits plus uncommitted tracked
changes) and copies the untracked non-ignored scope files over (intent-to-add), so the whole audit scope
is the worktree's UNCOMMITTED diff. The subagent works only there and never touches the user's tree.

## Dispatch (same assistant message as the `find.js` Workflow call)

`Workflow` returns a `runId` at once, so the review runs concurrently with it.

```bash
for c in "${CLAUDE_SKILL_DIR}/bin/lib-orchestrator.sh" "$HOME/.claude/skills/audit/bin/lib-orchestrator.sh"; do [ -f "$c" ] && { . "$c"; break; }; done   # fresh shell per block: source the lib again
orch_state_load   # ALLE_DATEIEN, BASE_REF from Phase 1 / 1.5
REVIEW_WORKTREE=$(orch_review_worktree_create "$BASE_REF" "$ALLE_DATEIEN") || REVIEW_WORKTREE=""
echo "REVIEW_WORKTREE=${REVIEW_WORKTREE:-<creation failed>}"
orch_state_save REVIEW_WORKTREE
```

Call the helpers by name only: `audit/hooks/block-worktree-wide-git.sh` denies the literal
`git worktree remove --force` in a Bash call (checked: the helper call is not blocked, the literal is).

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

After the subagent returns, also when it failed, remove the worktree in a fresh block:

```bash
for c in "${CLAUDE_SKILL_DIR}/bin/lib-orchestrator.sh" "$HOME/.claude/skills/audit/bin/lib-orchestrator.sh"; do [ -f "$c" ] && { . "$c"; break; }; done   # fresh shell per block: source the lib again
orch_state_load   # REVIEW_WORKTREE from the dispatch block
orch_review_worktree_remove "$REVIEW_WORKTREE"
```

A failed `orch_review_worktree_create` (empty `REVIEW_WORKTREE`) counts as a failed review below.

## From reply to verifier

1. Parse the reply. A failed creation or dispatch, a reply that is not the JSON above, or a missing Skill
   tool: `## Not completed` entry `code_review` with the reason; it blocks the marker (count one extra
   selected and one incomplete unit in Phase 4, `orch_marker_write`).
2. Findings keep their ids, dimension `code_quality`.
3. Drop a finding as duplicate when a `find.js` finding names the same file within 20 lines and the same
   problem: set `duplicateOf: {dimension, id}` on it; it skips the verifier and `minor-split.mjs` returns
   it under `duplicates`.
4. ONE `Agent` call for all remaining findings: `subagent_type: code-reviewer`, `model: sonnet`,
   `run_in_background: false`, prompt = `agents/finding-verifier.md` plus one input block per finding
   (its "Input" format, `DIFF_CONTEXT` omitted, `PROJECT_GUIDELINES` and `DECIDED_TRADEOFFS` from
   Phase 1) plus: "severity is null on these findings, assign Critical, Important or Minor yourself".
   Reply schema: `verdicts[{id, verdict, severity, reason}]` (`references/finding-schema.md`).
5. `REFUTED`: discarded, reason into `## Discarded`. `CONFIRMED` and `UNCERTAIN` (a missing id counts as
   `UNCERTAIN`) take the verifier's severity and join the `find.js` findings as the `non-REFUTED findings`
   input of `minor-split.mjs` (Phase 2, "Decide per finding"): Critical/Important to the fix wave, Minors
   split as usual, the Phase 4 `UNCERTAIN` marker rule unchanged. There is no Opus refuter pass for
   them; the fix-verifier still peer-reviews the fix.
6. Log them under `[code_quality]` with their ids, and feed one pattern per `CONFIRMED` verdict into the
   recurrence store like every other finding.
