# Examples

Real artifacts these skills produce, so you can judge the output before installing anything.

- **[audit-log.md](./audit-log.md)** — an actual `/audit` run against this very repo (2026-07-07): triage routing with the deterministic floor visible, findings per severity, what was auto-fixed vs. deliberately left, pre-checks, and the post-loop record. This file is written to `.claude/audits/` at the end of every audit.

Plans written by `/plan-it` follow the executor-grade template in `plan-it/references/plan-templates.md` (drift check against the planned-at commit, verify criterion per step, machine-checkable done criteria, STOP conditions) and land in the target repo under `docs/plans/`.
