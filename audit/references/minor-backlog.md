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
is `.audit/minor-backlog.tsv` (main checkout) is a TRACKED file, committed with the code, kept sorted by key so diffs stay stable;
`orch_backlog_add` removes the old `.gitignore` line for it and ensures `.gitattributes` carries
`.audit/minor-backlog.tsv merge=union`. It never enters audit scope (`collect-scope.sh` drops `.audit/` and `.claude/audits/`) and a
delta of only the tsv/`.gitattributes` classifies as `prose`. It is maintained only through `orch_backlog_add`,
`orch_backlog_for_files`, `orch_backlog_remove`, `orch_backlog_oldest` and `orch_backlog_count` in
`bin/lib-orchestrator.sh`.

**Location (moved 2026-10-02).** `.claude/` is protected even in headless sessions, so the store lives in `.audit/` at the
repo root. Reads prefer `.audit/` and fall back to the legacy `.claude/audits/minor-backlog.tsv`; the first write goes to
`.audit/` and prints `BACKLOG_LEGACY_FILE=...`, which the report must repeat as "legacy file can be deleted" (the audit never
deletes under `.claude/`). An emptied `.audit/` store stays as an empty file so the legacy copy is not read again.

Order: every backlog write happens BEFORE `orch_marker_write` (and `orch_audited_record`), because the marker certifies
the tracked tree and a later write would invalidate it. Line: `key  dimension  file  line  first_seen  description`. Rows
with a 7th column (written by an older version for a retired triage step) are still read, looked up and removed; the column is ignored.

## Sweep

Trigger: the user explicitly asks to clear the backlog ("Minor-Backlog abarbeiten", "Minors abarbeiten",
"clear the minor backlog"). No other run does this; there is no scheduled or nightly run.

1. Start as Phase 0/1 do (claim, lib sourced in every block), skip scope, find and the start question.
2. Pick the entries: oldest first (`orch_backlog_oldest <n>`), or grouped by file (`orch_backlog_count`, then the stored
   rows per file via `orch_backlog_for_files`) when the user names files or asks for "by file". Default is the 40 oldest.
3. Every picked entry becomes a finding with `verdict: "UNCERTAIN"`, grouped by file, at most ~40 fixes per
   `fix.js` call (several calls in sequence for more). Phase 3 applies unchanged (baseline, verification,
   the full suite once after the wave, silencing re-checks).
4. `orch_backlog_remove` the keys of every entry that came back `FIXED` or `DISCARDED`; `FAILED` ones stay.
5. The fixes stay in the working tree for the user to review; one branch plus PR or a commit only on request.
6. Write a short log (Result, Fixed, Discarded, `### Backlog (Minor)`), print `MINOR_BACKLOG: N open`,
   write NO push marker: a sweep certifies nothing about the diff.
