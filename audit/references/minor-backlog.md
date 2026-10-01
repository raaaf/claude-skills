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
is `.claude/audits/minor-backlog.tsv` (main checkout) is a TRACKED file, committed with the code, kept sorted by key so diffs stay stable;
`orch_backlog_add` removes the old `.gitignore` line for it and ensures `.gitattributes` carries
`.claude/audits/minor-backlog.tsv merge=union`. It never enters audit scope (`collect-scope.sh` drops `.claude/audits/`) and a
delta of only the tsv/`.gitattributes` classifies as `prose`. It is maintained only through `orch_backlog_add`,
`orch_backlog_for_files`, `orch_backlog_remove`, `orch_backlog_oldest` and `orch_backlog_count` in
`bin/lib-orchestrator.sh`.

Order: every backlog write happens BEFORE `orch_marker_write` (and `orch_audited_record`), because the marker certifies
the tracked tree and a later write would invalidate it. Line: `key  dimension  file  line  first_seen  description`.

## Sweep

Trigger: the user explicitly asks (or the nightly cloud routine runs it headless, see below) to clear the backlog ("Minor-Backlog abarbeiten", "Minors abarbeiten",
"clear the minor backlog"). No other run does this.

1. Start as Phase 0/1 do (claim, lib sourced in every block), skip scope, find and the start question.
2. Read the whole store: `orch_backlog_for_files` with every file in it (or read the TSV).
3. Every entry becomes a finding with `verdict: "UNCERTAIN"`, grouped by file, at most ~40 fixes per
   `fix.js` call (several calls in sequence for more). Phase 3 applies unchanged (baseline, verification,
   the full suite once after the wave, silencing re-checks).
4. `orch_backlog_remove` the keys of every entry that came back `FIXED` or `DISCARDED`; `FAILED` ones stay.
5. Write a short log (Result, Fixed, Discarded, `### Backlog (Minor)`), print `MINOR_BACKLOG: N open`,
   write NO push marker: a sweep certifies nothing about the diff.

## Headless sweep (nightly routine)

Same sweep, run by a daily Claude Code cloud routine per repo. Only the user or that routine triggers it.

1. `orch_backlog_count` is 0: print `MINOR_BACKLOG: 0 open` and stop before any agent dispatch.
2. Open PRs from an earlier `chore/minor-backlog-*` branch (`gh pr list --state open`, head ref prefix): stop and
   report instead of opening a second one (no stacking).
3. Limit `N = ${AUDIT_MINOR_SWEEP_LIMIT:-15}`. Take `orch_backlog_oldest N` (oldest first_seen, then key), group by file.
4. Fix wave over them as `UNCERTAIN` (step 3 of the sweep above), affected tests through `bin/test-lock.sh`.
5. `orch_backlog_remove` the `FIXED`/`DISCARDED` keys; `FAILED` stay.
6. Branch `chore/minor-backlog-YYYY-MM-DD` from the current default branch, commit code plus the updated tsv
   (`chore: clear N minor backlog items`), push the branch, `gh pr create` listing each item as
   `[dimension] file:line: description` with its outcome. Never push to the default branch; no push marker.
