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
| `OK` | Continue. `MODEL_OVERRIDE=null` (subagents use their default models). |
| `LARGE` (>2000 lines OR >20 files) | Targeted escalation: only Architecture and Security run on Opus. Output: "Diff is large ({LINES} lines / {FILES} files) — Architecture + Security run on Opus for deeper reasoning." Set `HEAVY_REASONING_OVERRIDE=opus`. Continue. |
| `HUGE` (>5000 lines; or >50 files AND >=1000 lines) | Hard block: abort. "Diff too large for a meaningful audit. Please split into multiple commits/PRs." No audit run. |

**Two-axis HUGE evaluation:** if only the file axis exceeds the threshold (>50 files) but the line count is under 20% of the line threshold (<1000), the script itself downgrades to `LARGE` and emits `DIFF_SIZE_NOTE=...`. Output the note in chat (warning: many small, logically separate changes) and continue normally — no manual override needed.

**Delta-scope carve-out at HUGE (official pattern):** a HUGE diff does not have to hard-block when part of it is already covered. A previously audited slice may be excluded from scope if ALL of these hold: (1) the slice was audited clean the SAME day and its audit log under `.claude/audits/` is referenced, (2) the remaining diff contains NO changes to any file of that slice since its audit (verify via `git diff --stat {slice_audit_head}..HEAD -- {slice files}` → empty), (3) the exclusion is documented in the new audit log under `## Scope` (slice name, log reference, file count). If any condition fails, the hard block stands. This keeps "audit in slices, then push everything" workable without silently re-trusting stale results.

**Why only Architecture escalates:** Architecture (code reasoning across multiple modules) benefits measurably from Opus on a LARGE diff. Security also runs on Opus, but unconditionally rather than on escalation, so it is not part of the override. Every other worker, triage and the fix agents included, runs on Sonnet: Haiku was dropped repo-wide on 2026-08-11 (see CLAUDE.md, "Worker model routing").

## Output of collect-scope.sh

`collect-scope.sh` provides:
- `DEFAULT_BRANCH`, `BASE_REF`
- Classified file lists: `---FILES---`, `---FRONTEND---`, `---TRANSLATIONS---`
- Deduplicated unified diff: `---DIFF---`

**Project-level `scope-extensions:` override — does not apply here.** `.claude/audit-guidelines.md` may declare a `scope-extensions:` line (see CLAUDE.md "Project-specific overrides" / Gotchas) to add extensions to `/full-audit`'s fixed-glob tree scan. `/audit`'s scope above is diff-based instead — `collect-scope.sh` lists every changed file regardless of extension — so a changed `SKILL.md`, `agents/*.md` or any other Markdown file is already in `ALLE_DATEIEN` today, with or without the override. The line only has an effect for `/full-audit`.

## Output of detect-framework.sh

Provides: `FRAMEWORK`, `SOURCE_DIRS`, `PLATFORM` (three lines, exactly `FRAMEWORK=`, `SOURCE_DIRS=`, `PLATFORM=`, in that order). `SOURCE_DIRS` is a list of directories, each `%q`-quoted individually and joined by plain (unescaped) spaces — a `%q` escape only ever protects a space that is actually inside a directory name, so the separators between directories stay real spaces. Consume it by capturing the script's stdout as text (never one blanket `eval "$(...)"` over all three lines — the `SOURCE_DIRS` line's unescaped separators make it multiple shell words, not a single assignment), extracting the value after `SOURCE_DIRS=`, then reconstructing the array with `eval "SOURCE_DIRS_ARR=($SOURCE_DIRS)"`. That targeted `eval` is required (not optional) — it is what turns the `%q` escaping back into real array elements, and it is also what keeps an attacker-controlled directory name in an audited repo inert: `NAME=(...)` compound-assignment syntax only ever treats the parenthesized content as array-literal words, never as commands to execute.

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
- **SUPPRESSIONS:** load `$(git rev-parse --show-toplevel)/.claude/audits/suppressions.json` if present, extract `pattern` fields. Otherwise `"No suppressions"`. **Re-validate factual-claim reasons first:** for any entry whose `reason` asserts something about the current code ("unused", "never called", "dead code", "no callers"), grep the codebase to confirm it still holds before honouring the suppression; if the claim is now false, drop that pattern from the passed-in set for this run and note it (`Stale suppression re-activated: {pattern}`). Decision/tradeoff reasons ("accepted risk", "by design") are never re-checked. Do not edit `suppressions.json` here — the user decides on the file in Phase 5. (Incident: `hairlineStrong` suppressed as "unused" rode through several audits after it had gained call sites.)
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
| `check-test-count-drift.sh` | `TESTCOUNT_RESULT=MISMATCH` | **no automatic finding.** Counting tests from source is only an approximation with parametrized tests (`test.each`, `@Test arguments:`). Instead, Phase 3c holds the documented claims against the REAL test-run output; only a runtime deviation becomes an **Important** `[Docs]`. Re-run the script after the last fix wave: fix agents add tests, and that is exactly when the numbers go stale unnoticed (three audits in a row). |

| `check-docs-path-drift.sh` | `DOCSPATH_RESULT=FINDINGS` | one **Important** `[Docs]` per `DOCSPATH {doc}:{line}` line: a live doc still names a file this diff deleted or renamed away. The severity is fixed at Important because the doc gives an instruction pointing at nothing. This is the structural half of docs-sync — the class that needs no judgment. Whether a surviving description is still TRUE stays with the docs_sync worker. Archives (`docs/plans/`, `docs/adr/`, `docs/decisions/`, `docs/archive/`) are excluded by the script: a plan naming a file that was deleted three months later is history, not drift. |
| `check-docs-claims.sh` | `DOCSCLAIM_RESULT=FINDINGS (N)` | one **Important** `[Docs]` per `DOCSCLAIM {doc}:{line}: {reason}` line: `CLAUDE.md`/`README.md`/`*/SKILL.md` reference a repo script, path, or roster entry that does not exist right now. Diff-independent (unlike `check-docs-path-drift.sh`, which only catches paths THIS diff just deleted) — catches claims that went stale from any earlier change. Repo-path heuristic: a backtick-quoted token is only checked if its first path segment names one of this repo's own top-level directories (`find -maxdepth 1`, computed at runtime); everything else (`app/Models/Customer.php`, `src/services/`, `.claude/*`) is treated as a foreign-project illustrative example and skipped. `.claude/` is excluded on purpose — it holds gitignored, runtime-generated audit state that legitimately does not exist on a fresh checkout. Bare directory mentions (no file extension on the final segment, e.g. `docs/adr/`) are skipped too — a directory is often naming an OPTIONAL/conditional glob source, not a claim it exists now. Never reports under `audit/evals/` (deliberately-broken fixtures). Also cross-checks the Skill roster table against real `*/SKILL.md` directories, both directions. |

`OK`/`SKIP` always means: do nothing. New checks follow `references/writing-deterministic-checks.md`.
