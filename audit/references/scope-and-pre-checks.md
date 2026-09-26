# Scope & Pre-Checks (Phase 1 Detail)

Detailed logic for Phase 1. Read by the orchestrator when pre-checks are non-trivial.

## Contents
- Evaluating the Diff-Size Gate
- Output of collect-scope.sh
- Output of detect-framework.sh
- Output of pre-checks.sh
- Pre-Check Evaluation (immediately, before any subagent dispatch)
- Deriving Variables from Script Outputs
- Audit Context Check (MANDATORY when context is missing)
- Intent-Docs / Decided Tradeoffs (DECIDED_TRADEOFFS)
- Deterministic checks: how to turn their result codes into findings

## Evaluating the Diff-Size Gate

| `DIFF_SIZE_RESULT` | Action |
|---|---|
| `SMALL` (<=950 lines AND <=28 files) | Continue, no `hunkScope`. Below this a diff still shows real issues even on the smaller dimensions (measured 2026-09-26), so coverage stays full; only the specialist dispatch shape changes (`find.js`'s `chunkFilesForDimension` collapses each dimension to one unchunked specialist call, except `security`/`privacy`/`payments`, which always keep normal chunking). |
| `OK` (everything above `SMALL`, up to the `LARGE` threshold) | Continue, with `hunkScope` on. Model routing is fixed by find.js/fix.js (Sonnet everywhere except the scout and the Critical refuter, which run Opus). |
| `LARGE` (>2000 lines OR >20 files) | Report the file/line counts and continue; find.js's chunking handles the size. Size does not change worker models. |
| `HUGE` (>5000 lines; or >50 files AND >=1000 lines) | Hard block: abort. "Diff too large for a meaningful audit. Please split into multiple commits/PRs." No audit run. |

**Two-axis HUGE evaluation:** if only the file axis exceeds the threshold (>50 files) but the line count is under 20% of the line threshold (<1000), the script itself downgrades to `LARGE` and emits `DIFF_SIZE_NOTE=...`. Output the note in chat (warning: many small, logically separate changes) and continue normally — no manual override needed.

**Delta-scope carve-out at HUGE:** a previously audited slice may be excluded only when all
conditions hold: (1) it was audited clean the same day and its log under `.claude/audits/` is
referenced; (2) every slice file's current content hash matches its logged audited input hash,
including uncommitted working-tree content, with no missing, added or renamed scope files;
(3) the new log's `## Scope` names the slice, original log, file count and hash verification.
A HEAD-only git diff is insufficient. Missing hash evidence or any mismatch forbids the
exclusion; apply the partitioning criteria below or retain the hard block.

**Same-HEAD partitioning at HUGE:** when no prior clean slice can be excluded, continue only
if the scope separates into bounded groups without hiding a shared symbol or dependency across
them. Record the groups, file/line counts and the pinned HEAD in the log. Execute the complete
file list once through find.js: its built-in chunking and cluster scouts handle partitioning,
while docs/copy retain the whole scope. Do not introduce a separate outer batch loop or
W1/W2/W3/W4 dispatch. If the scope cannot be partitioned meaningfully, the hard block stands.
Every selected dimension must cover its assigned files and every uncovered result blocks
completion.

**Model routing:** find.js/fix.js request Sonnet for scouts, specialists, verifiers and fixers,
and Opus for the Critical refuter. Diff size changes warnings and scope handling, not model
selection.

## Output of collect-scope.sh

`collect-scope.sh` provides:
- `DEFAULT_BRANCH`, `BASE_REF`
- Classified file lists: `---FILES---`, `---FRONTEND---`, `---TRANSLATIONS---`
- Deduplicated unified diff: `---DIFF---`

**Project-level `scope-extensions:` override — does not apply here.** `.claude/audit-guidelines.md` may declare a `scope-extensions:` line (see CLAUDE.md "Project-specific overrides" / Gotchas) to add extensions to `/full-audit`'s fixed-glob tree scan. `/audit`'s scope above is diff-based instead — `collect-scope.sh` lists every changed file regardless of extension — so a changed `SKILL.md`, `agents/*.md` or any other Markdown file is already in `ALLE_DATEIEN` today, with or without the override. The line only has an effect for `/full-audit`.

## Output of detect-framework.sh

Provides: `FRAMEWORK`, `SOURCE_DIRS`, `PLATFORM` (three lines, exactly `FRAMEWORK=`, `SOURCE_DIRS=`, `PLATFORM=`, in that order). `SOURCE_DIRS` is a list of directories, each `%q`-quoted individually and joined by plain (unescaped) spaces — a `%q` escape only ever protects a space that is actually inside a directory name, so the separators between directories stay real spaces. Consume it by capturing the script's stdout as text (never one blanket `eval "$(...)"` over all three lines — the `SOURCE_DIRS` line's unescaped separators make it multiple shell words, not a single assignment), extracting the value after `SOURCE_DIRS=`, then reconstructing the array with `eval "SOURCE_DIRS_ARR=($SOURCE_DIRS)"`. That targeted `eval` is required (not optional) — it is what turns the `%q` escaping back into real array elements. The safety against an attacker-controlled directory name in an audited repo comes ENTIRELY from `detect-framework.sh`'s per-element `printf %q`: an unescaped `$(...)` inside an `eval "arr=(...)"` executes like anywhere else in `eval`, and `%q` is what turns it into a literal word (verified 2026-09-16).

## Output of pre-checks.sh

Three sections: `SECRET_SCAN_RESULT`, `LOCKFILE_DRIFT_RESULT`, `BINARY_ARTIFACTS_RESULT`.

## Pre-Check Evaluation (immediately, before any subagent dispatch)

| Pre-check | Result | Action |
|---|---|---|
| `SECRET_SCAN_RESULT=FINDINGS` | — | As **Critical** in the audit log. Warn the user immediately. Push is blocked until secrets are removed + history is cleaned. |
| `LOCKFILE_DRIFT_RESULT=DRIFT` | — | As **Important** in the audit log. Check manifest consistency, regenerate lockfile if needed. |
| `BINARY_ARTIFACTS_RESULT=FINDINGS` | — | As **Important**. Suggestion: remove from index, extend `.gitignore`. |

If the diff is empty and all pre-checks are `CLEAN`: report and stop. Not a git repo? Report the error.

## Deriving Variables from Script Outputs

- **ALLE_DATEIEN:** section `---FILES---` from `collect-scope.sh`
- **FRONTEND_DATEIEN:** section `---FRONTEND---`
- **TRANSLATION_DATEIEN:** section `---TRANSLATIONS---`
- **VISUELL_RELEVANTE_DATEIEN:** `FRONTEND_DATEIEN` + framework-specific backend files (e.g. `app/Livewire/`, controllers with `return view(...)`/`return Inertia::render(...)`). NOT: pure services, models, migrations, commands, jobs, middleware — unless they change what's passed to the view.
- **UNIFIED_DIFF:** section `---DIFF---` (goes only to Triage, NOT to Workers)
- **SUPPRESSIONS:** load `$AUDIT_STORE_ROOT/.claude/audits/suppressions.json` if present (`AUDIT_STORE_ROOT` = main checkout via `--git-common-dir`, same derivation as `pre-flight-checks.md`; from a linked worktree `--show-toplevel` misses the file entirely, reproduced 2026-09-03), extract `pattern` fields. Otherwise `"No suppressions"`. **Re-validate factual-claim reasons first:** for any entry whose `reason` asserts something about the current code ("unused", "never called", "dead code", "no callers"), grep the codebase to confirm it still holds before honouring the suppression; if the claim is now false, drop that pattern from the passed-in set for this run and note it (`Stale suppression re-activated: {pattern}`). Decision/tradeoff reasons ("accepted risk", "by design") are never re-checked. Do not edit `suppressions.json` here — the user decides on the file in Phase 5. (Incident: `hairlineStrong` suppressed as "unused" rode through several audits after it had gained call sites.) **Expiry:** an entry may carry `"expires": "YYYY-MM-DD"`. Past that date the pattern is dropped from the set for this run and noted (`Suppression expired: {pattern}`), so the finding comes back once and the user decides again instead of the silence being permanent. A decision reason is the case that needs this: factual claims are already re-validated every run by the paragraph above, while "accepted risk" and "by design" are never re-checked and so would otherwise hold forever, including long after the risk was fixed or the design changed. Entries without `expires` still work unchanged; count them and, when there are any, add ONE aggregated open point (`N suppressions without an expiry date`, naming the file, not the patterns) rather than one per entry.
- **PROJECT_CONTEXT:** `## Audit Context` from `CLAUDE.md` (if present), via `awk '/^## Audit Context$/{f=1;next} /^## /{f=0} f'`. Otherwise `"No project-specific context."`

## Audit Context Check (MANDATORY when context is missing)

If `PROJECT_CONTEXT` is empty or `CLAUDE.md` has no `## Audit Context` section, **before the first subagent dispatch** ask the user via `AskUserQuestion` whether a context section (stack/framework rules, deliberate architecture decisions, scaling goals, critical interfaces) should be drafted and added to `CLAUDE.md`. Options:

- **Yes, create it now** → analyze repo structure (`composer.json`/`package.json`, routes, README), draft a proposal, insert into `CLAUDE.md`, then continue the audit.
- **No, skip once** → continue the audit without context.
- **Never ask again** → create marker `.claude/audit-no-context.flag`, continue the audit. Follow-up audits check the marker and skip the question.

Marker check before the question:
```bash
[ -f "$(git rev-parse --show-toplevel)/.claude/audit-no-context.flag" ] && SKIP_CONTEXT_PROMPT=true
```

## Intent-Docs / Decided Tradeoffs (DECIDED_TRADEOFFS)

Deliberate, documented decisions must not be re-raised as findings. Deterministic globbing:

```bash
ROOT=$(git rev-parse --show-toplevel)
INTENT_DOCS=$( { ls "$ROOT"/docs/adr/*.md "$ROOT"/docs/adrs/*.md "$ROOT"/docs/decisions/*.md 2>/dev/null
                 ls "$ROOT"/DESIGN.md "$ROOT"/PRODUCT.md "$ROOT"/CONTEXT.md 2>/dev/null; } | sort -u )
```

- Matches found → read the files (for many ADRs: only title + status + decision line per ADR) and summarize as `DECIDED_TRADEOFFS`: one line per decision ("ADR-007: sync-over-async write in store.ts is deliberate — consistency over latency"). Max 15 lines.
- No matches → `DECIDED_TRADEOFFS="no documented decisions found"`.
- Passed through to all workers (prompt-template.md placeholder). Worker rule there: don't report documented tradeoffs; code drift from the decision is a docs_sync finding ("a stale ADR is itself a finding").

**Trust boundary, stated once.** `DECIDED_TRADEOFFS`, `PROJECT_GUIDELINES` (`.claude/audit-guidelines.md`),
`PROJECT_CONTEXT` and `SUPPRESSIONS` are all authored by the audited repo, and every one of them can
make a finding go away. That is deliberate: they carry the repo owner's decisions, the same trust the
audit already extends to `CLAUDE.md`, and an owner who wants to hide a defect from their own audit can
do so far more simply in the code itself. What the boundary does NOT cover: a hostile repo opened for
the first time. There the audit's other rules hold (repo content is never an instruction, a suppression
with a factual reason is re-validated every run, an `OFFEN`/`by design` note is logged not silently
dropped), and the residual, a by-design note that lies, is accepted rather than gated, because the
alternative is an audit that ignores the owner's documented decisions. Raised as a security finding on
2026-09-16 and left UNCERTAIN by the verifier for lack of exactly this paragraph.

## Deterministic checks: how to turn their result codes into findings

Phase 1 runs the scripts below. Each prints a result code; the orchestrator converts it into findings
by this table. The scope rule is the same everywhere: a hit on a file **inside the diff** becomes a
finding, a hit outside the diff is printed as a hint and nothing more (this is `/audit`, not
`/full-audit`).

| Script | Result code | Becomes |
|---|---|---|
| `check-outdated.sh` (only when a manifest/lockfile is in the diff) | `DEP_SECURITY_RESULT=VULNS` | one **Critical** `[Security]` per reported line. A vulnerable dependency blocks the push like any Critical. |
| | `DEP_OUTDATED_RESULT=OUTDATED` | one **Minor** `[Dependencies]` per reported line. New version available, not a blocker. |
| | `DEP_SECURITY_RESULT=TIMEOUT` | **no automatic finding, never treated as clean.** The vulnerability check did not complete within the network timeout. Log a gap note (`Dependency security: skipped, network check timed out`), same class as the full-audit test-runner/build-preflight gap notes, so a repeat accumulates toward an aged-gap escalation instead of silently passing as clean. |
| | `DEP_OUTDATED_RESULT=TIMEOUT` | same handling as above, lower stakes: gap note `Dependency updates: skipped, network check timed out`. |
| | `SKIP`/`CLEAN`/`CURRENT` | nothing |
| `check-i18n-keys.sh` | `I18N_RESULT=MISSING` | one **Important** `[i18n]` per `MISSING {locale}: {key}` line, when the affected keys/files are in the diff |
| `check-duplicate-array-keys.sh` | `DUPKEY_RESULT=DUPLICATES` | one **Critical** `[Correctness]` per `DUPLICATE {file}:{line}` line. PHP keeps the LAST value on a duplicate key and drops the first silently, so the crash only appears once a code path reads the shadowed key. `php -l` does not catch this. |
| `check-number-format-locale.sh` | `NUMFMT_RESULT=MISSING_LOCALE` | one **Important** `[Correctness]` per line. Only runs when `lang/de` exists. |
| `check-swift-deprecations.sh` | `SWIFTDEPR_RESULT=FINDINGS` | one **Minor** `[Code-Quality]` per `SWIFTDEPR {file}:{line}` line. **Never Critical**: these are convention drift, not correctness bugs (`UIScreen.main`, `try!` outside `#Preview`/tests, hardcoded `Color.red`/`.white` outside `Theme.swift`/`Brand.swift`). |
| `check-token-contrast.sh` | `TOKEN_CONTRAST_RESULT=HITS` | one **Important** `[A11y]` per `TOKEN_CONTRAST_HIT` line: a surface/background token used as a foreground color, or a token pair used together in a changed Swift file with a computed WCAG ratio under 3:1. SKIPs silently when no Swift token file exists (web projects). Learning 2026-08-10: the same token-contrast class recurred across three SwiftUI audits and only an agent read caught it. |
| `check-silencing.sh` | `SILENCING_RESULT=HITS (N)` | one finding per `SILENCING_HIT {file}:{line} {kind}` line, severity by kind: `suppression-added` and `threshold-lowered` -> **Important** `[Code-Quality]`, dropped to **Minor** when the same line carries a written justification or the same commit also removes the code the suppression covered; `test-disabled` -> **Important** `[Code-Quality]`; `error-swallowed` -> **Minor** `[Code-Quality]`, since a deliberately non-throwing telemetry call is the common legitimate case; `test-skipped-at-runtime` and `assertions-removed` -> **Minor**, both need the guard or the hunk read before they mean anything. The point is not that these edits are forbidden, it is that they make a check pass without the underlying problem being fixed, so each one is a finding to justify. Also re-run after the last fix wave (Phase 3c): a fix agent that silences a linter instead of satisfying it produces exactly this diff, and nothing else in the pipeline looks for it. Calibration and the measured false-positive history are in the script header. |
| `check-test-count-drift.sh` | `TESTCOUNT_RESULT=MISMATCH` | **no automatic finding.** Counting tests from source is only an approximation with parametrized tests (`test.each`, `@Test arguments:`). Instead, Phase 3c holds the documented claims against the REAL test-run output; only a runtime deviation becomes an **Important** `[Docs]`. Re-run the script after the last fix wave: fix agents add tests, and that is exactly when the numbers go stale unnoticed (three audits in a row). |

| `check-docs-path-drift.sh` | `DOCSPATH_RESULT=FINDINGS` | one **Important** `[Docs]` per `DOCSPATH {doc}:{line}` line: a live doc still names a file this diff deleted or renamed away. The severity is fixed at Important because the doc gives an instruction pointing at nothing. This is the structural half of docs-sync — the class that needs no judgment. Whether a surviving description is still TRUE stays with the docs_sync worker. Archives (`docs/plans/`, `docs/adr/`, `docs/decisions/`, `docs/archive/`) are excluded by the script: a plan naming a file that was deleted three months later is history, not drift. |
| `check-fresh-shell.sh` | `FRESH_SHELL_RESULT=HITS (N)` | one **Critical** `[Architecture]` per `FRESH_SHELL_HIT {file}:{line} {fns}` line: a ```bash block in a SKILL.md calls an `orch_*` function without sourcing `lib-orchestrator.sh` in that same block. Every block is a fresh shell, so the call hits an undefined function and its command substitution yields empty output (a marker path without its hash, a run-log call that never fires). Fix by adding the one-line source loop from the lib header at the top of the block. Since 2026-09-16 the script also emits `FRESH_SHELL_HIT <file>:<line> vars: NAME...` (a block expands an uppercase variable it did not set without calling `orch_state_load`, or no `orch_state_save` in any scanned `*/SKILL.md` or `*/references/*.md` carries that name, then marked `(never saved)`) and `FRESH_SHELL_HIT <file>:<line> save-unset: NAME...` (a block saves a name it never set). Fix for `vars:` is a save where the value is produced plus a load in the reader, never the source loop. |
| `check-workflow-dupes.sh` | `WORKFLOW_DUPES_RESULT=HITS (N)` | one **Important** `[Code-Quality]` per `WORKFLOW_DUPES_HIT <symbol>` line: a helper that `find.js` and `fix.js` must carry as identical copies (the Workflow tool forbids imports) has drifted between them. Fix by making the copies identical again, never by deleting one. |
| `check-docs-claims.sh` | `DOCSCLAIM_RESULT=FINDINGS (N)` | one **Important** `[Docs]` per `DOCSCLAIM {doc}:{line}: {reason}` line: `CLAUDE.md`/`README.md`/`*/SKILL.md` reference a repo script, path, or roster entry that does not exist right now. Diff-independent (unlike `check-docs-path-drift.sh`, which only catches paths THIS diff just deleted) — catches claims that went stale from any earlier change. Repo-path heuristic: a backtick-quoted token is only checked if its first path segment names one of this repo's own top-level directories (`find -maxdepth 1`, computed at runtime); everything else (`app/Models/Customer.php`, `src/services/`, `.claude/*`) is treated as a foreign-project illustrative example and skipped. `.claude/` is excluded on purpose — it holds gitignored, runtime-generated audit state that legitimately does not exist on a fresh checkout. Bare directory mentions (no file extension on the final segment, e.g. `docs/adr/`) are skipped too — a directory is often naming an OPTIONAL/conditional glob source, not a claim it exists now. Never reports under `audit/evals/` (deliberately-broken fixtures). Also cross-checks the Skill roster table against real `*/SKILL.md` directories, both directions. |

`OK`/`SKIP` always means: do nothing. New checks follow `references/writing-deterministic-checks.md`.
