# Scope & Pre-Checks (Phase 1 Detail)

Detailed logic for Phase 1. Read by the orchestrator when pre-checks are non-trivial.

## Evaluating the Diff-Size Gate

| `DIFF_SIZE_RESULT` | Action |
|---|---|
| `OK` | Continue. `MODEL_OVERRIDE=null` (subagents use their default models). |
| `LARGE` (>2000 lines OR >20 files) | Targeted escalation: only Architecture and Security run on Opus. Output: "Diff is large ({LINES} lines / {FILES} files) — Architecture + Security run on Opus for deeper reasoning." Set `HEAVY_REASONING_OVERRIDE=opus`. Continue. |
| `HUGE` (>5000 lines; or >50 files AND >=1000 lines) | Hard block: abort. "Diff too large for a meaningful audit. Please split into multiple commits/PRs." No audit run. |

**Two-axis HUGE evaluation:** if only the file axis exceeds the threshold (>50 files) but the line count is under 20% of the line threshold (<1000), the script itself downgrades to `LARGE` and emits `DIFF_SIZE_NOTE=...`. Output the note in chat (warning: many small, logically separate changes) and continue normally — no manual override needed.

**Delta-scope carve-out at HUGE (official pattern):** a HUGE diff does not have to hard-block when part of it is already covered. A previously audited slice may be excluded from scope if ALL of these hold: (1) the slice was audited clean the SAME day and its audit log under `.claude/audits/` is referenced, (2) the remaining diff contains NO changes to any file of that slice since its audit (verify via `git diff --stat {slice_audit_head}..HEAD -- {slice files}` → empty), (3) the exclusion is documented in the new audit log under `## Scope` (slice name, log reference, file count). If any condition fails, the hard block stands. This keeps "audit in slices, then push everything" workable without silently re-trusting stale results.

**Why only two dimensions escalate:** Architecture (code reasoning across multiple modules) and Security (subtle attack vectors) benefit measurably from Opus. Performance, Code Quality, SEO, A11y, Typography, UI, UX, Animation are predominantly rule- or pattern-based — Sonnet is sufficient. Triage and fix agents stay on Haiku.

## Output of collect-scope.sh

`collect-scope.sh` provides:
- `DEFAULT_BRANCH`, `BASE_REF`
- Classified file lists: `---FILES---`, `---FRONTEND---`, `---TRANSLATIONS---`
- Deduplicated unified diff: `---DIFF---`

## Output of detect-framework.sh

Provides: `FRAMEWORK`, `SOURCE_DIRS`.

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
- **SUPPRESSIONS:** load `$(git rev-parse --show-toplevel)/.claude/audits/suppressions.json` if present, extract `pattern` fields. Otherwise `"No suppressions"`.
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
