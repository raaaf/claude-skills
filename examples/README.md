# Examples

Real artifacts these skills produce, so you can judge the output before installing anything.

- **[audit-log.md](./audit-log.md)** — an actual `/audit` run against this very repo (2026-07-07): triage routing with the deterministic floor visible, findings per severity, what was auto-fixed vs. deliberately left, pre-checks, and the post-loop record. This file is written to `.claude/audits/` at the end of every audit.
- **[full-audit-state.md](./full-audit-state.md)** — the persistent goal-loop state file `/full-audit` maintains in `.claude/audits/full-audit-state.md`: one row per batch, machine-readable header, blocked section. `full-audit/bin/status-line.sh` turns it into the deterministic `FULL_AUDIT_STATUS` line that decides completion; `resume-check.sh` decides which clean batches must be re-audited after code changes.

Plans written by `/plan-it` follow the executor-grade template in `plan-it/references/plan-templates.md` (drift check against the planned-at commit, verify criterion per step, machine-checkable done criteria, STOP conditions) and land in the target repo under `docs/plans/`.
