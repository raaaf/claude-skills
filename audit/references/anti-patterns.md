# Audit: Anti-Patterns (Red Flags)

Read this file when the rules in the main skill aren't top of mind. Each line marks a thinking error that breaks the audit loop.

## Loop Control

- **"I'm waiting for user confirmation before starting the next round"** → WRONG. The loop runs autonomously. No user input between rounds.
- **"One round is enough"** → WRONG. The loop only ends at `AUDIT_STATUS: SAUBER`. `FIXES_APPLIED` + `RUNDE < {MAX_RUNDEN}` → immediately start the next round.
- **"Let me explain the plan now"** → WRONG. Execute directly.
- **"Findings stayed the same, I'll try one more round"** → WRONG. On `NO_CONVERGENCE` (round ≥ 2 and findings aren't decreasing): end the loop immediately.

## Subagent Discipline

- **"In round 2, Architecture and Code Quality are enough"** → WRONG. In EVERY round, ALL subagents marked relevant by triage are dispatched. A security fix can introduce a performance problem. An architecture refactor can break a11y.
- **"The validator is overkill, I trust the subagents"** → WRONG. LLM findings hallucinate file paths, line numbers, and API signatures. Step D.5 is mandatory.
- **"This finding looks off, I'll just fix it anyway"** → WRONG. Hallucination validator first. If the file/line doesn't exist: discard the finding.
- **"An agent went idle without a report, I'll wait / keep nudging it"** → WRONG. The official recovery path is: exactly ONE re-prompt via SendMessage, then the per-agent-type failure path from SKILL.md Step C (triage → floor routing, worker → skip dimension, fix agent → check `git diff` then re-dispatch once, verifier → `RECOMMEND=patch`). Prevention (REPORT_DELIVERY block in the prompt template) demonstrably does not catch every case — recovery is part of the loop, not an exception.

## Stale-Diff Artifact (named repeat offender)

Findings produced against a diff base that no longer matches the working tree. Three distinct incidents so far: 07-09 (parallel-session commit mid-audit), 07-14 status-badge (stale snapshot), 07-14 quote-workflow (index drift). Countermeasures already in the loop: `AUDIT_BASE_HEAD` pinning (Phase 1), wave HEAD pinning + `WORKER_RESULT=HEAD_DRIFT` (Step B.6), Phase 4 drift check.

- **"The diff looked fine at dispatch, findings are still valid"** → WRONG. On any HEAD/status drift: re-pin, re-collect scope, re-dispatch the wave. Findings from a stale base are hallucinations with extra steps.
- **Escalation rule:** on the NEXT distinct stale-diff mechanism (4th incident) or a 2nd HEAD-drift-from-shared-checkout incident, ASK the user whether audits should default to an isolated worktree. Never decide this silently — it conflicts with the standing "no worktrees" preference (feedback_no_worktrees); the user reconciles, not the orchestrator.

## Test Plan

- **"I can skip the test plan because there are no visual changes"** → Check `FRONTEND_DATEIEN` / `VISUELL_RELEVANTE_DATEIEN`. If empty: correct, no test plan needed. If not empty: a test plan is mandatory.
- **"I'll generate a generic test plan"** → WRONG. The test plan must reference concrete pages, routes, and changes from the diff. Max 10 steps, prioritized by risk.

## Full-Audit-Specific

- **"This finding is Minor, I'll skip it"** → WRONG. Full-audit fixes EVERYTHING — Critical, Important, and Minor.
- **"I can skip the convergence check"** → WRONG. Without a convergence check you end up in fix loops.

## Why the working-tree cross-check exists (2026-07-22)

A fix agent ran `git stash` + `git stash pop`, wiped a sibling agent's fix for the run's only
Critical, and reported `FIX_RESULT=APPLIED`. Nothing in the reports revealed it; only the
deterministic cross-check against `git status` did. Agent reports are a claim, `git status` is the
evidence. Same reason the stash check in Step E is not optional.

## Cost of the two verification stages

Both the finding verifier (Step D.7) and the fix verifier (Step E.5) run on Sonnet at roughly a
third of a worker each, in parallel, adding about 5-10s per round. D.7 is what makes a high-recall
finder prompt affordable: without a real filter behind it, coverage at the finding stage would turn
into wrong fixes, which are far more expensive than a refuted finding.
