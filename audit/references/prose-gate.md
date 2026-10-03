# The Prose Gate: when the audit scales itself down

Read this when `DIFF_CLASS=prose` (computed in Phase 1), or when you are tempted to remove the gate.

## The problem it solves

`/audit` is a pre-push gate calibrated for code that ships to users: a built-in code review of the
diff, a triage and a fix round. On a diff of that kind, that is exactly right.

Applied to a diff that only changes prose, a review still finds something, because finding
something is what it is built to do. And every finding it fixes produces a new diff, which by the
repo's own rule deserves an audit before it is pushed.

That is a fixed point with no exit. It happened on 2026-08-05: three audits in one night, each one
auditing the fixes of the previous one.

| Run | What it found |
|---|---|
| 22:30 | An effort branch that silently ran `xhigh` at two rounds; an eval suite that had been scoring wrong for months |
| 00:15 | Both PreToolUse guards completely dead, for three independent reasons |
| 02:00 | A wrong word in a comment, a stale number in a doc, a fixture name that leaked its own keyword |

Every one of those findings was correct. The first run was worth its cost several times over. The
third was not, and nothing in the skill noticed the difference.

## The rule

`bin/classify-diff.sh` decides. A diff is `prose` when it contains no file that executes, configures
a build, or is consumed by a runtime: no source file, no script, no manifest or lockfile, no CI
config, no template or stylesheet. Documentation, guidelines, agent definitions and audit logs are
prose. Eval fixtures are exempt from the code signal on purpose, since they are deliberately broken
test data that is never shipped, and adding a test case should not re-trigger the full gate.

On `prose` (rewritten 2026-10-02, adapted 2026-10-03):

- **no built-in review and no checklist agent.** `/audit` runs Phase 1 only (`audit/SKILL.md`), skips
  Phases 2 to 4 and goes to Phase 5. The run is a pass with zero review findings; the marker is written
  with `orch_marker_write 1 0 0 0` (the deterministic gate counts as the one review).
- **the deterministic checks stay**, including `check-docs-claims.sh`, `check-docs-path-drift.sh`, the
  secret scan and the lockfile check. They are the whole gate for prose: a doc claim that contradicts
  the disk is still caught, a Critical from them (a secret) still blocks the marker.
- **the normal marker rules apply**, on the tree as it is.

Until 2026-10-02 a prose diff ran two LLM dimensions (`docs_sync` and `copy`). The prose findings that
mattered were claims that disagree with the code, which `check-docs-claims.sh` finds mechanically.

The gate fails open: anything the classifier cannot place is `code`. Under-auditing a code change is
the expensive mistake; over-auditing prose is merely annoying.

## What the gate deliberately does not do

It does not skip the pre-checks. Secret scanning, lockfile drift and the deterministic language
checks run on every diff regardless of class, because a secret in a Markdown file is still a secret
in a public repo.

It does not lower severity. A Critical in prose is still a Critical and still blocks the push.

## The judgment the gate cannot make for you

The gate is mechanical and looks only at file types. It cannot tell that a one-line change to a
guideline will steer every future audit, or that a comment correction is load-bearing because it
justifies a shipped security control. Both happened in this repo.

So: when a prose diff changes something that *decides* how future work is done, say so and raise the
scope by hand for that run. That is a deliberate, stated exception, which is different from adding
review rounds reflexively because the diff felt important.
