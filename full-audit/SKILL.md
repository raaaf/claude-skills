---
name: full-audit
description: "Comprehensive one-time audit of an entire codebase (not just recent changes). Auto-detects framework, runs the same per-dimension audit pipeline as /audit across all 13 dimensions with SCOPE=repo, fixes per the chosen scope (Minor always logged, never fixed). Use when the user runs /full-audit, starts on a new project, asks for a comprehensive review, or wants the whole codebase checked. NOT for pre-push of recent changes, use /audit instead."
when_to_use: "/full-audit, ganzes projekt prüfen, komplette codebase auditen, gesamten code einmal durchchecken, neues projekt komplett prüfen, full codebase audit, audit whole project, starting on a new project, comprehensive review"
model: inherit
effort: high
allowed-tools:
  - Agent
  - Bash
  - Read
  - Edit
  - Write
  - Glob
  - Grep
  - TodoWrite
  - AskUserQuestion
---

# Full Codebase Audit

**Select the runtime, then start Phase 0; there is nothing to confirm first.**

> **Architecture note:** No worker agents of its own. Uses `../audit/agents/*.md` and
> `../audit/workflows/{find,fix}.js` (referenced via `AUDIT_ROOT`). Change worker configuration
> there, not here.

## Runtime selection

Resolve `FULL_AUDIT_ROOT` from the absolute path of the actual loaded `full-audit/SKILL.md`.
Resolve `AUDIT_ROOT` as its sibling `audit` directory; do not search an unrelated installation.
Read `../audit/SKILL.md` runtime selection and `../audit/references/codex-runtime.md`
before proceeding. Set `AUDIT_RUNTIME=codex` when native collaboration is available,
otherwise use Claude's native `Agent` tool. Both execute the same find/fix scripts through
the shared Node request/response bridge with persisted responses. Do not use `Workflow`
resume. Never shell-launch Claude or Codex or require API keys. Codex skips Claude hooks
and transcript pricing.
Use the current checkout as `PROJECT_ROOT`; Codex state is `.codex/audits` in that checkout.

## Phase 0: Resolve audit root + pre-checks

```bash
# FULL_AUDIT_ROOT is the literal directory of the loaded SKILL.md, established above.
AUDIT_ROOT="$(dirname "$FULL_AUDIT_ROOT")/audit"
[ -f "$AUDIT_ROOT/SKILL.md" ] && [ -d "$AUDIT_ROOT/agents" ] || {
  echo "ERROR: install audit alongside full-audit."; exit 1;
}
AUDIT_AGENTS="$AUDIT_ROOT/agents"; AUDIT_AGENTS_DIR="$AUDIT_AGENTS"; AUDIT_BIN="$AUDIT_ROOT/bin"; AUDIT_REFS="$AUDIT_ROOT/references"
[ "$AUDIT_RUNTIME" != claude ] || bash "$AUDIT_BIN/run-log.sh" --start --skill full-audit
bash "$AUDIT_BIN/verify-agents.sh" "$AUDIT_AGENTS" || { echo "Abgebrochen, fehlende Agent-Dateien."; exit 1; }
FW_OUT="$(bash "$AUDIT_BIN/detect-framework.sh")"
FRAMEWORK=$(printf '%s\n' "$FW_OUT" | sed -n 's/^FRAMEWORK=//p')
SOURCE_DIRS=$(printf '%s\n' "$FW_OUT" | sed -n 's/^SOURCE_DIRS=//p')
bash "$AUDIT_BIN/pre-checks.sh"
bash "$AUDIT_BIN/check-ci-hardening.sh" "$(git rev-parse --show-toplevel)"
bash "$AUDIT_BIN/check-outdated.sh" "$(git rev-parse --show-toplevel)"
```

**Scope** (equivalent of `collect-scope.sh --all`, `full-audit/references/scope.md` for the exact
glob and bash block, execute it here):
`SOURCE_DIRS` walked for the fixed extension list plus `scope-extensions:` from
the resolved project guidelines. Read applicable `AGENTS.md` and `.codex/audit-guidelines.md` in Codex, falling back to `.claude/audit-guidelines.md` if needed. `PROJECT_GUIDELINES` is read the same way as `/audit` Phase 1; use that resolved file for `scope-extensions:` too.

Claude only: CWD_HASH=... In-progress marker claim: same commands as `audit/SKILL.md` Phase 1 (claim now, touch
after find.js, touch after fix.js, release at Phase 4).

## Phase 1.5: Start questions

**Same rule and same two questions as `audit/SKILL.md` Phase 1.5** ("A set variable suppresses
both questions"): `AUDIT_DIMENSIONS` / `AUDIT_FIX_SCOPE`, `references/dimension-selection.md`
(now under `audit/references/`) for the presets. `/full-audit` sets no push marker regardless of
the answer, so a partial selection here has no gate consequence, only a smaller log.

## Phase 2-5: same as `audit/SKILL.md`, with `SCOPE=repo`, no marker

Run the selected runtime branch of Phases 2 through 5 of `audit/SKILL.md`, with these substitutions:

- `find.js` args: `scope: "repo"`, `files` from the Phase 0 scope walk above (not a diff), and scope content loaded by the shared bridge as specified in `audit/SKILL.md` Phase 2.
- Phase 4 records `skill: full-audit` and `gate: not_applicable`. Incomplete finding/fix/regression verification still means an incomplete audit, never success.
- Phase 4 never writes `/tmp/claude-audit-passed-*`, `/full-audit` has no push gate. Everything
  else (log finalization, `run-cost.sh`, `run-log.sh --counts`, in-progress marker release,
  learning phase) is identical.

In both runtimes, persist the find and fix bridge directories in the log and resume with
`step` through the shared reference. Completed responses are replayed from disk without
redispatch; recover persisted native worker IDs for pending requests before launching more
workers. Codex costs remain unavailable/null unless actual accounting exists.

## Last line of every run

```
Audit: {C} Critical, {I} Important offen | Push nicht zutreffend
```
