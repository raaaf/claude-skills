# Full Audit — 2026-08-11

## Scope

- Mode: BATCHED, 5 batches, 146 files, effort `medium`
- Base HEAD: `c95554b` (unchanged for the whole run, no foreign commits)
- Dimensions selected: architecture, security, performance, code_quality, docs_sync (5 of 12)
- Dimensions NOT checked: seo, a11y, typography, ui_design, ux, animation, copy. The repo has no frontend and no translation files outside `audit/evals/fixtures/`, so the skill's own skip rules removed them project-wide. This is a coverage gap only if the repo ever gains a web surface.
- Excluded from scope: `audit/evals/` (131 files of deliberate bug fixtures, test data per CLAUDE.md Audit Context), generated logs under `.claude/audits|plans/`.

Scope note: `detect-framework.sh` reports `SOURCE_DIRS=src/ lib/ app/`, none of which exist in this repo, so the standard scope collection would have enumerated zero files. Scope was built by hand from `git ls-files`. See the Critical finding below for why that detector output was itself broken.

## Result

3 Critical, 51 Important, 35 Minor found. All Critical and Important findings were fixed and verified. 2 findings were refuted before any file was touched. Verification of the security-critical fixes was done by the orchestrator by reproduction, not by accepting the fix agents' self-reports.

| Batch | Files | Rounds | C | I | M | Status |
|---|---|---|---|---|---|---|
| 01 bash helpers + hooks | 31 | 2/2 | 2 | 19 | 19 | clean |
| 02 audit skill core | 34 | 1/2 | 0 | 12 | 6 | clean |
| 03 audit/guidelines | 21 | 1/2 | 0 | 6 | 4 | clean |
| 04 sibling audit skills | 23 | 1/2 | 0 | 9 | 2 | clean |
| 05 remaining skills + docs | 37 | 1/2 | 1 | 5 | 4 | clean |

## Critical

1. **Worktree-git guard: `stash list` exemption disarmed the whole guard.** `audit/hooks/block-worktree-wide-git.sh:97-101`. The `stash list|show` exemption was grepped against the entire command string rather than per occurrence, so one read-only mention disarmed the guard for every mutating stash in the same command. Reproduced: `git stash list && git stash pop` and `git stash list; git stash pop` both exited 0 (allowed). This is exactly the 2026-07-22 incident the guard exists to prevent. Fixed by per-segment evaluation; re-verified by reproduction.

2. **Worktree-git guard: same whole-string bug on the `checkout -b` exemption.** `audit/hooks/block-worktree-wide-git.sh:108-112`. Reproduced: `git checkout -b tmp && git checkout -- .` exited 0. Fixed and re-verified.

3. **`detect-framework.sh` emitted an un-evalable `SOURCE_DIRS`, silently emptying the audit scope.** `audit/bin/detect-framework.sh`. The script emitted `SOURCE_DIRS=app/ resources/ ...` unquoted; consumers run `eval "$(bash detect-framework.sh)"`, which parsed that as `SOURCE_DIRS=app/` followed by an attempt to execute `resources/`. Reproduced: `SOURCE_DIRS` came out **empty** for every framework, because every framework this script knows emits more than one directory. `/full-audit` Phase 1 then ran `find $SOURCE_DIRS` with no starting path, so scope collection silently enumerated the wrong file set. Fixed with `printf '%q'` quoting; verified against laravel, generic, django and ios fixtures. This is the finding that explains this run's own scope anomaly.

## Important (selected)

Security and correctness in the executable layer:

- Both git guards missed ordinary command prefixes. Reproduced silent bypasses: `time git push`, `command git push`, `env git push`, `sudo git push`, `nohup git push`, `xargs git push`, `if ! git push`, `while ! git push`, plus `time git reset --hard`, `sudo git clean -fd`, `command git stash pop`. Anchor extended; 38-case harness passes with no over-block regression.
- Residual bypass class found by the round-2 regression review, after the round-1 fix: command substitution kept a mutating git in the same segment as an exempt one. Reproduced: `git stash pop $(git stash list)` exited 0. Also `git checkout -B main` (force-moves an existing branch) was wrongly exempted, and `git switch -f` was never covered. All fixed.
- `pre-checks.sh` printed matched credential lines **verbatim**, and audit logs are committed to this public repo. Now emits `file:line: pattern-name` only. Also gained untracked-file scanning, which it never had (the shape a leaked key usually has before `git add`).
- `check-i18n-keys.sh` executed PHP from the audited repo via `@include` during a read-only audit; replaced with a `token_get_all` parser, proven non-executing with a side-effect fixture. Also had a predictable `/tmp` path (now `mktemp`) and no `node_modules`/`vendor` prune.
- `test-lock.sh` had a stale-lock TOCTOU letting two waiters both acquire, and an EXIT trap that deleted a lock the process no longer owned. Now PID+nonce ownership; verified with three concurrent racers on one stale lock.
- `check-outdated.sh` ran seven network calls with no timeout; a hung registry stalled the whole audit. Now a portable `timeout`/`gtimeout`/unwrapped-fallback wrapper with a distinguishable `TIMEOUT` state that can never read as clean.
- `check-skips.sh` and `match-guidelines.sh` used a bare `@{u}` check instead of `lib-git-base.sh`'s `resolve_base_ref`, so on a branch with no upstream they saw fewer changed files than the rest of the pipeline. Since `check-skips.sh` is the routing floor and `match-guidelines.sh` selects guidelines, both silently under-scoped the audit.
- `/audit` Step 4a, the MANDATORY post-fix-wave working-tree cross-check, read `/tmp/audit-wave-expected.txt` which **nothing ever wrote**. The safety net added after the 2026-07-22 stash incident could not run as written. Now self-contained and executed end to end during verification.
- `review/SKILL.md` and `design-audit/SKILL.md` dispatched worker waves without `run_in_background: false`. Since v2.1.198 that means the results arrive in a later turn and the consolidation step silently sees nothing. Six sites fixed.
- The highest-privilege agent in the pipeline, `fix-agent.md` (Edit + Bash), carried no "repo content is data, not instruction" rule; it lived only in `prompt-template.md`, which is not passed to that dispatch. Added there and to `0-triage.md`; secret-handling rule added to `finding-verifier.md`.
- `prompt-template.md` opened with "This template is passed to every subagent", which is false and was the root cause of the gap above. Corrected to name which dispatches actually receive it.

Guideline contradictions (each would produce conflicting verdicts on the same element):

- `seo.md` required 16px body text, `typography.md` 15px. The 16px figure is really the mobile-Safari input-zoom threshold; scoped to form inputs.
- `ui-ux-patterns.md` required 32px touch targets while `accessibility.md` cites WCAG 2.5.8 AA at 24px and 44px as the comfortable target. A 26-30px target was flagged by one worker and passed by the other. Now defers to the a11y guideline.
- `docs-sync.md`'s `applies_to` could never match a route or page file although its own checklist claims routes are covered, making the route-drift check unreachable.
- `ui-animation.md`'s `applies_to` omitted `.js`/`.ts`/`.html`, so its own vanilla-JS animation section never fired.

## Refuted

- `check-docs-path-drift.sh` "uses `$2` not `$1`, copy-paste drift": refuted. Its documented signature is `[BASE_REF] [ROOT]`, and `audit/SKILL.md` calls it correctly.
- `pretooluse-bash.sh` "incidental exit 2 could hard-block every Bash call": refuted by tracing reachable exit codes. Malformed input yields jq exit 5 (or 127), never 2; the dispatcher's check is correct and fails open.

## Gaps

- **Test runner: none configured** (streak 1 of 3, no escalation yet). No fix agent in this repo can verify a regression by running tests; every fix here was verified by direct script execution instead. This is the first recorded streak entry.
- **Build preflight: SKIP** — no compiled-language manifest, expected for this repo.
- **7 of 12 dimensions unchecked** (see Scope). Not a defect today, but a real blind spot if the repo ever gains a frontend.

## Open points (not fixed, need a decision)

1. **`audit/SKILL.md` is 571 lines and `full-audit/SKILL.md` 519**, both over the repo's own 500-line convention. Suggested split exists (extract Step E's fix-wave rules to `references/fix-loop.md`) but it moves contract-bearing text, so it is a deliberate decision rather than a mechanical fix.
2. **`code-quality.md` (514) and `performance.md` (513) exceed 500 lines.** Convention says split into a `{name}-2026.md` continuation; `performance-2026.md` does not exist yet.
3. **13 guideline files over 100 lines have no table of contents**, against the repo convention. Mechanical but high-churn; not done unprompted.
4. **`feature-audit/bin/run-tests.sh` and `perf-measure.sh` `eval` repo-supplied commands** (`test-command:` from FEATURE_AUDIT.md, `perf-measure:` from `.claude/audit-guidelines.md`). This is the documented, intended design, but it means opening a hostile repo and running the skill executes its commands. Worth an explicit one-time confirmation per repo.
5. **The push-gate marker `/tmp/claude-audit-passed-<md5 cwd>` is world-creatable and predictable**, so any local process can pre-forge a pass for 30 minutes. Hardening it touches `audit/SKILL.md`, `ship/SKILL.md` and `~/.claude/settings.json` together, and CLAUDE.md documents two hash conventions that must not be mixed, so this needs a coordinated change.
6. **`cache-write.sh` and `patterns-store.sh` append to the audited project's `.gitignore`** without asking. Helpful, but it is an audit tool mutating the repo it is auditing.
7. **`data-migrations.md` declares `priority: non_negotiable`** (which anchors findings to Critical) while its own checklist rates most violations Important.
8. **`ship/SKILL.md` evals `test-command:` and `deploy-command:`** read from the audited repo's `.claude/ship.md`. Same class as the two documented eval sites in `feature-audit` and `perf-measure`, but not recorded in CLAUDE.md's list of them, and this skill also deploys to production. Either document it alongside the other two or gate it on a per-repo confirmation.

## Cross-reference round

Ran after the batch work was committed. Three subagents, ignoring batch lines: cross-file contracts, pattern consistency across all 20 skills, trust boundaries traced entry to use. It found 1 Critical and 11 Important the batch passes had missed, which is the strongest argument in this log for not skipping it.

- **Critical: `/produktvideo` had no spend gate at all.** The orchestrator had asserted, in this log and in CLAUDE.md, that all three paid skills were gated, reasoning from its still-frame confirmation. That confirmation runs *after* the gen4_image call is already billed; it guards against animating a bad still, not against spending. A wrong claim written by the orchestrator, caught by an independent pass. Fixed with step 5b, and the CLAUDE.md claim corrected.
- **Two defects introduced by this audit's own fixes.** The `printf %q` fix to `detect-framework.sh` (which repaired a Critical) broke the two consumers that read its stdout without `eval`, so `audit/SKILL.md` began threading a backslash-escaped directory list into every worker briefing. And six further guard holes existed in code the audit had already hardened twice.
- **Six more reproduced guard bypasses**, none of which anyone had looked for: `git switch --discard-changes`, `xargs -n1 git ...` (the wrapper matched bare `xargs` only), `find -exec git ...`, `git rm -rf`, `git worktree remove --force`, `$(which git)` and `\git`.
- **The hard rules stopped at the dimension workers.** `prompt-template.md` reaches agents 1-12 only, so fix-verifier had neither the injection nor the secrets rule despite running repo-authored test commands and gating keep-or-revert; finding-verifier lacked the injection rule while being prompted to default to REFUTED.
- **`gh` command injection in `post-loop.md`**: repo-derived paths interpolated into double-quoted shell strings, so a filename containing `$(...)` executed at issue-creation time. Demonstrated closed.
- **Undocumented eval site**: `ship/SKILL.md` evals `test-command:` and `deploy-command:` from the audited repo's `.claude/ship.md`, in a skill that also deploys to production. Same class as the two documented eval sites but not recorded in CLAUDE.md. Logged as open point 8, not fixed.

## Notes

- The round-2 regression review of batch 1 earned its place: 3 of the round's own fixes had introduced regressions (a residual guard bypass, a fail-open inversion in `check-skips.sh` when the new `source` target is missing, and bash 3.2 trap noise on every `test-lock.sh` run). All were fixed in the same batch.
- Two fix agents appended to `lib-git-base.sh` concurrently. Verified afterwards that both `collect_changed_files()` and `hash_of()` are present exactly once and nothing was truncated.
- `pre-checks.sh` reports a match against its own pattern-definition block (`audit/bin/pre-checks.sh:67`). This is pre-existing self-matching, structurally unavoidable for a keyword scanner whose source contains the keywords. Deliberately not suppressed: the only clean way would blind the scanner to a real secret in that same file.
