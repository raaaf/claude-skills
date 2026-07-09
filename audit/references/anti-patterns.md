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

## Test Plan

- **"I can skip the test plan because there are no visual changes"** → Check `FRONTEND_DATEIEN` / `VISUELL_RELEVANTE_DATEIEN`. If empty: correct, no test plan needed. If not empty: a test plan is mandatory.
- **"I'll generate a generic test plan"** → WRONG. The test plan must reference concrete pages, routes, and changes from the diff. Max 10 steps, prioritized by risk.

## Full-Audit-Specific

- **"This finding is Minor, I'll skip it"** → WRONG. Full-audit fixes EVERYTHING — Critical, Important, and Minor.
- **"I can skip the convergence check"** → WRONG. Without a convergence check you end up in fix loops.
