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

**Location (moved 2026-10-02).** The first nightly run (zeit PR 437) could not update `.claude/audits/minor-backlog.tsv`
and `visual-pass-head`: Claude Code protects `.claude/` even headless, so the next night would have redone the same
work. Both files now live in `.audit/` at the repo root. Reads prefer `.audit/` and fall back to the legacy
`.claude/audits/` file; the first write goes to `.audit/` and prints `BACKLOG_LEGACY_FILE=...`, which the
report must repeat as "legacy file can be deleted" (the audit never deletes under `.claude/`). An emptied
`.audit/` store stays as an empty file so the legacy copy is not read again.

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

## Nightly audit (headless routine)

Run by a daily Claude Code cloud routine per repo. Only the user or that routine triggers it. Triggers:
"Nachtlauf" / "nightly audit" run both steps below; the backlog-only phrases from "Sweep" run step b alone
(branch `chore/minor-backlog-YYYY-MM-DD`, as before).

Why a quality pass (decided 2026-10-02, extends the 2026-10-01 visual pass): the pre-push gate now runs only
`security`, `privacy`, `architecture`, the built-in `/code-review high`
(benchmark and cost evidence: `dimension-selection.md`). The other ten dimensions
(`performance`, `code_quality`, `a11y`, `ux`, `copy`, `seo`, `docs_sync`, `typography`, `ui_design`,
`animation`) run here. Earlier evidence for the first three (122 audit logs): 0 Critical and mostly cosmetic
Importants, about 11% of audit-find cost per push; `copy` found destructive dialogs confirmed with "Ja" and
missing delete confirmations, `seo` found PIN-protected pages leaking title/description/image into og: meta.
The file names keep "visual" (`visual-pass-head`, `orch_visual_pass_*`, `AUDIT_VISUAL_PASS_CAP`) for compatibility.

Preconditions, before any agent dispatch:

- Open PRs from an earlier `chore/nightly-audit-*` or `chore/minor-backlog-*` branch (`gh pr list --state open`,
  head ref prefix): stop and report instead of opening a second one (no stacking).
- Step a has no files (`orch_visual_pass_files` empty) AND `orch_backlog_count` is 0: print
  `MINOR_BACKLOG: 0 open` and stop.

### Step a: quality pass

1. Files = `orch_visual_pass_files` (lib): whole commits since the sha in `.audit/visual-pass-head` (tracked,
   one line; legacy `.claude/audits/visual-pass-head` is read when it is missing; a missing or unknown file means the
   commits of the last day). The commits are walked oldest first (first-parent) and their still-existing
   files taken until adding the next commit would exceed `${AUDIT_VISUAL_PASS_CAP:-40}` files; a single
   commit above the cap is taken alone with its files capped, `orch_visual_pass_overflow` is the number of
   capped files and the PR body states `N Dateien wegen Limit nicht geprüft` (never silent). The remainder
   of the history is not lost: the head advances only to the last fully included commit
   (`orch_visual_pass_head`), so the next night starts right after it. No files: skip step a.
   Why 1 day and 40: the first dry run with a 7-day fallback listed 949 files in one repo and 268, 96, 93, 88 in
   others (12 repos), which would exhaust the usage limit on night one.
2. `find.js` over those files with dimensions `performance,code_quality,a11y,ux,copy,seo,docs_sync,typography,ui_design,animation`
   (`seo` still subject to `orch_seo_relevant`), hunk scope per the normal size
   rules (Phase 1 `diff-size-gate.sh` thresholds). Compute `args.hunks` first with
   `bin/hunk-ranges.sh <base-ref> <files>` (base = the head sha, else `git rev-list -1 --before='1 day ago' HEAD`): the reviewer
   agents cannot run `git diff`, so without it the hunk scope stays unfollowable (first nightly, 2026-10-02).
3. Critical/Important findings join the fix wave of step b; Minors go to the backlog (`minor-split.mjs` rules
   unchanged).
4. Write `orch_visual_pass_head` (not `git rev-parse HEAD`) to `.audit/visual-pass-head` after the run, so it is
   committed with the PR.

### Step b: Minor backlog sweep

1. Limit `N = ${AUDIT_MINOR_SWEEP_LIMIT:-15}`. Take `orch_backlog_oldest N` (oldest first_seen, then key), group by file.
   Backlog empty and step a found nothing to fix: no fix dispatch.
2. One fix wave over step a's Critical/Important findings plus these entries as `UNCERTAIN` (step 3 of the
   sweep above), affected tests through `bin/test-lock.sh`.
3. `orch_backlog_remove` the `FIXED`/`DISCARDED` keys; `FAILED` stay.
4. Branch `chore/nightly-audit-YYYY-MM-DD` (backlog-only run: `chore/minor-backlog-YYYY-MM-DD`) from the current
   default branch, commit code plus the updated tsv and `visual-pass-head`
   (`chore: nightly audit, N fixes`; backlog-only: `chore: clear N minor backlog items`), push the branch,
   one `gh pr create` listing each item as `[dimension] file:line: description` with its outcome. Never push to
   the default branch; no push marker.

## Nightly run across repos

Decided 2026-10-01. One scheduled run on the user's Mac walks every audited repo and runs the nightly audit
above where there is work.

Allowlist (2026-10-02, user decision: production systems only): when `~/.claude/nightly-repos.allow` exists
(override `NIGHTLY_ALLOW_FILE`), only the repos listed there (one path per line, `~` and `#` comments allowed)
are reported; every other repo is dropped. Their Minors stay in their backlog until a manual sweep.

- `bin/nightly-repos.sh [root...]` lists candidates (git repos up to depth 4 under `$HOME/Developer` and
  `$HOME/Local Sites` with `.audit/` or `.claude/audits/` and a GitHub `origin`, worktrees deduped by git common dir) as
  `path<TAB>status<TAB>detail`: `ready` (backlog desc), `skip-dirty` (default branch has unpushed local
  commits), `skip-open-pr` (open `chore/nightly-audit-*` / `chore/minor-backlog-*` PR), `skip-no-gh`, `nothing`.
  Backlog and quality-pass files are read from `origin/<default>` after a quiet fetch, never the working tree.
  `visual_files=M` counts the pending files since the head; above the cap the detail reads `visual_files=M (cap 40)` and the morning report line says the rest follows on the next nights (catch-up over several nights, no file skipped).
- `bin/nightly-run.sh [--dry-run] [root...]` runs the `ready` repos strictly one after another: detached
  temporary worktree from `origin/<default>` under `$TMPDIR` (the main checkout is never touched),
  a headless `claude -p` (via `bin/lib-headless.sh`: `--permission-mode acceptEdits`, `--output-format json`, explicit
  `--allowedTools` list, prompt ends with a `NIGHTLY_DONE` sentinel; a missing sentinel resumes the session with
  `--resume <session_id>`, at most 3 times, else the report line says failed) inside it, 45 min cap per attempt
  (`NIGHTLY_TIMEOUT_SECS` overrides), full session text incl. fix.js errors in `YYYY-MM-DD-<repo>.txt`, then worktree removal and prune. `--dry-run` only prints the plan.
- Headless fallback (2026-10-02): in the first run `fix.js` could not be started and the session fell back to
  single `audit-fix-agents` (the orchestrator checks their diffs). Cause not determinable: `find.js` ran through
  the same `Workflow` tool, `Workflow` is in the skill's `allowed-tools`, `claude --help` lists no Workflow flag or
  opt-in, and `-p` mode needs none for `--permission-mode acceptEdits`; the session's own error text was not kept.
  Left as is. Next night, keep the session's `fix.js` error in the PR body to find the cause.
- Report: `$HOME/.local/state/claude/nightly/YYYY-MM-DD.md`, one line per repo (PR URL, failure reason,
  timeout, or the skip status and detail); printed at the end of the run.
- Push exception: `hooks/block-unsafe-push.sh` lets a marker-less push through only for one plain
  `git [-C dir] push [-u] [remote] [refspec...]` whose every target resolves to a `chore/nightly-audit-*` or
  `chore/minor-backlog-*` branch. Chained commands, quotes, substitutions, `--force`/`-f`/`+refspec`,
  `--all`/`--tags`/`--mirror`/`--delete`, unknown options, a default-branch target and an unresolvable current
  branch keep the old "ask". Pinned by `hooks/block-unsafe-push.test.sh`.
