# /audit internals

Rules and commands bound to `/audit`'s own tooling. Loaded when a file under `audit/` is read.
Cross-cutting rules that also apply here (orchestrator writes/subagents return, fresh-shell-per-Bash-block,
marker hashing, model:inherit, hook scope) live in the root `CLAUDE.md`.

## Architecture

`/audit` is a PR review before push (rebuilt 2026-10-03, replaces the per-dimension Workflow pipeline).
Flow: deterministic pre-checks, then the built-in `/code-review high` in a review worktree (plus one
`code-reviewer` checklist agent when `orch_sensitive_paths` returns paths), triage by the
orchestrator, one `spec-executor` fix round, one test run, log, push marker. `audit/SKILL.md` stays under ~150 lines.

Why (evidence, 2026-10-02/03):
- The old pipeline used about 45% of the weekly usage limit in 7 days (single runs 8-78 M weighted tokens).
- A benchmark on 5 historical diffs with 6 known Criticals: built-in `/code-review high` found all 3 security Criticals and 1 of 2 architecture ones, plus 2 serious issues the pipeline missed, at ~0.1-1.7 M per run.
- It missed one privacy Critical (third-party map tiles without consent) and one policy bypass; `references/sensitive-checklist.md` covers those two.

Other decisions:
- No verifier agents, no backlog file, no start question, no dimension selection. Triage is the orchestrator's job.
- Marker only when pre-checks are clean, every dispatched review completed, no Critical/Important is open and tests are green. `orch_marker_write` keeps its argument semantics: `selected` = reviews run, `incomplete` = failed reviews plus open findings.
- A `DIFF_CLASS=prose` diff runs the deterministic checks only (`references/prose-gate.md`).
- Platform: `detect-framework.sh` emits `PLATFORM=web|native|cross`; `/screens` uses it. `check-i18n-keys.sh` handles `.lproj` and `values-*/strings.xml`.

## Commands

`. audit/bin/lib-orchestrator.sh` functions: `orch_resolve_audit_root`, `orch_helper`, the two
cwd-hash families `orch_hash_passed`/`orch_hash_progress`, `orch_progress_claim`/`touch`/`release`,
`orch_state_save`/`orch_state_load`/`orch_state_clear`, `orch_tree_hash`,
`orch_marker_write`/`orch_marker_matches`/`orch_marker_delta`, `orch_url_host`/`orch_host_public`,
`orch_run_log`, `orch_ship_value`, `orch_test_command_declared`, `orch_test_command`,
`orch_unaudited_record`/`orch_unaudited_base`/`orch_unaudited_clear`, `orch_sensitive_paths`,
`orch_review_worktree_create`/`orch_review_worktree_remove`, `orch_usage_start`/`orch_usage_report`.
`orch_progress_claim` clears state so a run starts empty.

| Command | Purpose |
|---|---|
| `bash audit/bin/collect-scope.sh` | `BASE_REF` plus the `---FILES---`, `---FRONTEND---`, `---TRANSLATIONS---`, `---DIFF---` sections |
| `bash audit/bin/pre-checks.sh` | Secret scan, lockfile drift, binary artifacts |
| `bash audit/bin/check-i18n-keys.sh [root]` | Deterministic i18n key-set diff across locales |
| `bash audit/bin/check-outdated.sh [root] [--security-only]` | Dependency vulnerabilities (push-blocking) and outdated majors (Minor) |
| `bash audit/bin/check-ci-hardening.sh [root]` | Tag-pinned `uses:` and missing `permissions:` in `.github/workflows/*.yml` |
| `bash audit/bin/check-silencing.sh [root]` | New suppression comments, disabled tests, empty catches, removed assertions, lowered thresholds; run in Phase 1 and again after the fix round |
| `bash audit/bin/check-token-contrast.sh [root] [--tokens FILE] [--all]` | WCAG contrast check for SwiftUI design tokens |
| `bash audit/bin/check-docs-claims.sh [root]` | CLAUDE.md/README.md/`*/SKILL.md` claims verified against disk |
| `bash audit/bin/check-fresh-shell.sh [root]` | Bash blocks calling `orch_*` without sourcing the lib, or reading an unset state variable (`FRESH_SHELL_RESULT=OK\|HITS (N)\|SKIP`); scans `*/SKILL.md` and `*/references/*.md` |
| `bash audit/bin/classify-diff.sh [--paths]` | `DIFF_CLASS=prose\|code` |
| `bash audit/bin/run-cost.sh <projects-dir> <session-id> [--since <epoch>] [--json]` \| `--latest <projects-dir>` \| `--window <projects-root> <since-epoch>` | Sums agents/turns/tokens of a session plus `subagents/*.jsonl` against a fixed price table (checked 2026-10-03 against `/usage`). `orch_usage_report` combines it with the week since the reset in `~/.claude/usage-limits.conf` (defaults Thu 12:00 Europe/Berlin, 2600 USD); 1 % of the week is about 26 USD API value, the percentage is a local estimate, `/usage` is exact |
| `bash audit/bin/test-lock.test.sh` | Pins `test-lock.sh` (`--cmd`, `-destination` keying, linked-worktree lock dir, waiter notice) |
| `bash audit/bin/oracle-lock.sh snapshot\|check\|clear --run <id> [files...]` | Content-hash lock for `/delegate`'s oracle tests plus shared test setup; state under `--git-common-dir`; `check` prints `ORACLE_CHANGED=<file>` and `ORACLE_RESULT=OK\|CHANGED\|NONE` |
| `bash audit/bin/oracle-lock.test.sh` | Pins `oracle-lock.sh` (unchanged OK, sed edit, deletion, shared setup edit, unknown run NONE, run ids isolated, clear) |
| `bash audit/bin/mutate.sh <root> <base-ref> [--oracle-files "<f>..."]` | Targeted mutation run for `/delegate` Phase 5: changed files matching the project's `.claude/mutation-targets`, Pest (`--mutate --covered-only`) or Infection, one total budget `MUTATE_BUDGET` (600 s) inside `test-lock.sh`, survivors on changed lines +-3, max 15. Target line `<glob> :: TestA|TestB` pins the test classes (indirectly tested classes); Infection runs only the selected tests via `--test-framework-options=--filter`. Emits `MUTATE_RESULT=OK\|SKIP\|TIMEOUT\|ERROR`; ERROR reasons `runner-failed` and `initial-tests-failed` (Infection refuses a red suite, `MUTATE_ERROR` names the failing test file); SKIPs without `timeout`/`gtimeout`, coverage driver or runner. Infection is a manual one-time install: `curl -L -o ~/.local/share/claude/infection.phar https://github.com/infection/infection/releases/latest/download/infection.phar` (verified 2026-10-08 on zeit; `INFECTION_PHAR` overrides the path) |
| `bash audit/bin/mutate.test.sh` | Pins `mutate.sh` (target intersection, SKIP reasons, FQCN, Pest and Infection parsers against the real logs in `audit/bin/fixtures/mutate/`, +-3 filter and cap 15, no-timeout SKIP, stub-runner full flow) |
| `bash audit/bin/test-gate.test.sh` | Pins `test-gate.sh` (slot free/taken/handover/dead holder/PID reuse/non-owner release/timeout; `run` green, flake rerun, repeated flake within 14 days, no rerun on count mismatch, Feature failure or more than 5 files). Fixtures come from a real parallel Pest run |
| `bash audit/bin/orch-review-worktree.test.sh` | Pins the review worktree: committed, uncommitted and untracked scope files appear as an uncommitted diff at `BASE_REF`, the user's tree is untouched, remove leaves no entry |
| `bash audit/bin/orch-sensitive-paths.test.sh` | Pins `orch_sensitive_paths` (one hit per surface class; tests, style, prose files and `author` ignored) |
| `bash audit/bin/orch-zsh-source.test.sh` | Pins that the lib resolves its own directory when sourced from zsh |
| `bash audit/bin/orch-tree-hash.test.sh` | Pins `tree-hash.sh` (via `orch_tree_hash`): untracked non-ignored files count, ignored ones do not, the real index stays untouched, the hash equals HEAD's tree after `git add -A` and commit |
| `bash audit/bin/unaudited-base.test.sh` | Pins the quick-fix collection (`orch_unaudited_*`) |
| `bash audit/bin/classify-diff.test.sh` | Pins the prose/code classification of path lists |
| `bash audit/hooks/block-unsafe-push.test.sh` | Pins the push guard: a push without a fresh marker asks on every branch, with a fresh marker it passes, and a marker over a then-untracked file still matches (same `tree-hash.sh` as the marker) |

Every test is a single script; there is no wrapper that runs all of them.

## Audit Context (auditing this repo itself)

- Markdown + Bash skills repo, no runtime, no dependencies. Findings about missing package manifests, test frameworks, or CI configs for the skills themselves are noise.
- **Public repo on GitHub.** Secrets/keys/tokens anywhere in the diff are always Critical. Audit logs under `.claude/audits/` are committed, so they reference `file:line` and never reproduce file content.
- `audit/bin/*.sh` and every hook must stay **bash 3.2 compatible** (macOS default): no `declare -A`, no `readarray`, no `${var,,}`.
- German-named contract identifiers (`ALLE_DATEIEN`, ...) are deliberate cross-file contracts, NOT English-migration violations.
- Deliberate decision: orchestrator writes, subagents return (subagents cannot write under `.claude/`); `exit 2` blocking in the audit Stop hook is intentional, `additionalContext` would not block.

## Gotchas

- **Every Bash block in a SKILL.md is a fresh shell; nothing sourced or assigned survives into the next block.** Every block that calls an `orch_` function starts with the one-line source loop from the lib header, and every value a later block needs is saved with `orch_state_save` and re-read with `orch_state_load`. Enforced by `check-fresh-shell.sh`.
- **Marker hash families.** `/tmp/claude-audit-passed-*` hashes the cwd WITHOUT trailing newline, `/tmp/claude-audit-in-progress-*` WITH newline (`pre-compact.sh` recomputes the latter). Never mix them (root `CLAUDE.md`).
- **Push guard: every push needs a fresh marker.** `hooks/block-unsafe-push.sh` asks for any `git push` without a marker younger than 30 minutes, whatever the branch name; pinned by `hooks/block-unsafe-push.test.sh`.
- **Pre-push marker and `git push` must be separate Bash calls.** The PreToolUse hook scans the command string for `git push` and blocks before a marker write in the same call would execute.
- **Review worktree helpers by name only.** `hooks/block-worktree-wide-git.sh` denies the forced worktree-remove git command whenever it appears in a Bash call (it also blocks a heredoc that merely contains it); use `orch_review_worktree_create`/`orch_review_worktree_remove`.
- **The prose gate is the audit's stopping rule.** Fixing what an audit finds in prose creates the next diff that deserves an audit, a loop with no exit (2026-08-05). `classify-diff.sh` emits `DIFF_CLASS`; a `prose` diff runs the deterministic checks only. `references/prose-gate.md`.
- **The audit log's finding-line format is a contract.** `- [Severity][source] file:line: description` on ONE physical line (`references/audit-log-template.md`); humans grep it.
- **"Which files are frontend?" has one definition, `FRONTEND_EXT_RE` in `lib-git-base.sh`.** `collect-scope.sh` reads it with an inline literal fallback so a missing lib does not collapse to "nothing is frontend".
- **`SOURCE_DIRS` from `detect-framework.sh` is quoted per element, not as a whole string.** Each directory is individually `%q`-quoted, joined by plain spaces. Capture stdout as text, extract the value after `SOURCE_DIRS=`, rebuild the array with `eval "SOURCE_DIRS_ARR=($SOURCE_DIRS)"`; never one blanket `eval "$(...)"` over the three lines. The safety against attacker-controlled directory names comes entirely from the per-element `printf %q`. A directory name with a literal newline cannot round-trip.
- **`TEST_COMMAND` is a repo-supplied command string** (`.claude/ship.md` `test-command:`, else the manifest's own). Every test run, also a hand-assembled `xcodebuild test`, goes through `test-lock.sh`; two concurrent runs on one simulator kill each other ("Early unexpected exit, operation never finished bootstrapping").
- **`mutate.sh` reports `SKIP no-mutations` in a worktree whose `vendor/` is a symlink to the main project.** Pest then resolves the class to the main project's file and prints `No mutations created`; nothing was tested. Run the mutation step from the main checkout, or give the worktree its own `vendor/`. A runner that dies without a summary (e.g. a Browser test needing Playwright) is `ERROR`, never `OK`; `Browser/` test directories are excluded from discovery.
