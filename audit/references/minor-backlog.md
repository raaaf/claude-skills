# Minor backlog

Decided 2026-10-01 (replaces the 2026-09-25 rule that every finding, Minor included, is fixed). A zeit audit
produced 249 raw findings, 224 Minor, 25 Important, 0 Critical; fixing all of them meant ~17
spec-executor rounds on a HUGE diff, and 122 logs since 09-15 carry 1,900+ Minors.

## Rules

1. A `CONFIRMED`/`UNCERTAIN` Minor goes to the fix wave only when its file already receives a
   Critical/Important fix in the same wave (multi-file Minor: only when ALL its files do).
2. Every other non-refuted Minor goes to the backlog, also with `AUDIT_FIX_SCOPE=none`.
3. A backlog entry whose file receives a fix agent in a later wave joins that file's fixes as
   `verdict: "UNCERTAIN"`. `FIXED` or `DISCARDED` entries are removed; entries whose file no longer
   exists are dropped on every write.

`bin/minor-split.mjs` applies rules 1 to 3 (`audit/SKILL.md` Phase 2, "Decide per finding"). The store
is `.claude/audits/minor-backlog.tsv` (main checkout, gitignored like `patterns.json`), maintained only
through `orch_backlog_add`, `orch_backlog_for_files`, `orch_backlog_remove` and `orch_backlog_count` in
`bin/lib-orchestrator.sh`. Line: `key  dimension  file  line  first_seen  description`.

## Sweep

Trigger: the user explicitly asks to clear the backlog ("Minor-Backlog abarbeiten", "Minors abarbeiten",
"clear the minor backlog"). No other run does this.

1. Start as Phase 0/1 do (claim, lib sourced in every block), skip scope, find and the start question.
2. Read the whole store: `orch_backlog_for_files` with every file in it (or read the TSV).
3. Every entry becomes a finding with `verdict: "UNCERTAIN"`, grouped by file, at most ~40 fixes per
   `fix.js` call (several calls in sequence for more). Phase 3 applies unchanged (baseline, verification,
   the full suite once after the wave, silencing re-checks).
4. `orch_backlog_remove` the keys of every entry that came back `FIXED` or `DISCARDED`; `FAILED` ones stay.
5. Write a short log (Result, Fixed, Discarded, `### Backlog (Minor)`), print `MINOR_BACKLOG: N open`,
   write NO push marker: a sweep certifies nothing about the diff.
