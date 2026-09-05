---
name: full-audit
description: "Comprehensive one-time audit of an entire codebase (not just recent changes). Auto-detects framework, runs the same per-dimension Workflow pipeline as /audit across all 13 dimensions with SCOPE=repo, fixes per the chosen scope (Minor always logged, never fixed). Use when the user runs /full-audit, starts on a new project, asks for a comprehensive review, or wants the whole codebase checked. NOT for pre-push of recent changes — use /audit instead."
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
  - Workflow
---

# Full Codebase Audit

**Start directly with Phase 0; there is nothing to confirm first.**

> **Architecture note:** No worker agents of its own. Uses `../audit/agents/*.md` and
> `../audit/workflows/{find,fix}.js` (referenced via `AUDIT_ROOT`). Change worker configuration
> there, not here.

## Phase 0: Resolve audit root + pre-checks

```bash
AUDIT_ROOT=""
for candidate in \
  "$(dirname "${CLAUDE_SKILL_DIR:-/nonexistent}")/audit" \
  "${CLAUDE_PROJECT_DIR:+${CLAUDE_PROJECT_DIR%/full-audit}/audit}" \
  "$HOME/.claude/skills/audit" \
  "$HOME/.claude/skills/claude-skills/audit"; do
  [ -n "$candidate" ] && [ -d "$candidate/agents" ] && { AUDIT_ROOT="$candidate"; break; }
done
[ -z "$AUDIT_ROOT" ] && { echo "ERROR: audit skill not found. Install audit alongside full-audit."; exit 1; }
AUDIT_AGENTS="$AUDIT_ROOT/agents"; AUDIT_BIN="$AUDIT_ROOT/bin"; AUDIT_REFS="$AUDIT_ROOT/references"
bash "$AUDIT_BIN/run-log.sh" --start --skill full-audit
bash "$AUDIT_BIN/verify-agents.sh" "$AUDIT_AGENTS" || { echo "Abgebrochen — fehlende Agent-Dateien."; exit 1; }
FW_OUT="$(bash "$AUDIT_BIN/detect-framework.sh")"
FRAMEWORK=$(printf '%s\n' "$FW_OUT" | sed -n 's/^FRAMEWORK=//p')
SOURCE_DIRS=$(printf '%s\n' "$FW_OUT" | sed -n 's/^SOURCE_DIRS=//p')
bash "$AUDIT_BIN/pre-checks.sh"
bash "$AUDIT_BIN/check-ci-hardening.sh" "$(git rev-parse --show-toplevel)"
bash "$AUDIT_BIN/check-outdated.sh" "$(git rev-parse --show-toplevel)"
```

**Scope** (equivalent of `collect-scope.sh --all`, `full-audit/references/scope.md` for the exact
glob and bash block — execute it here):
`SOURCE_DIRS` walked for the fixed extension list plus `scope-extensions:` from
`.claude/audit-guidelines.md`. `PROJECT_GUIDELINES` read the same way as `/audit` Phase 1.

CWD_HASH=... In-progress marker claim: same commands as `audit/SKILL.md` Phase 1 (claim now, touch
after find.js, touch after fix.js, release at Phase 4).

## Phase 1.5: Start questions

**Same rule and same two questions as `audit/SKILL.md` Phase 1.5** ("A set variable suppresses
both questions"): `AUDIT_DIMENSIONS` / `AUDIT_FIX_SCOPE`, `references/dimension-selection.md`
(now under `audit/references/`) for the presets. `/full-audit` sets no push marker regardless of
the answer, so a partial selection here has no gate consequence, only a smaller log.

## Phase 2-5: same as `audit/SKILL.md`, with `SCOPE=repo`, no marker

Run Phases 2 through 5 of `audit/SKILL.md` unchanged, with two substitutions:

- `find.js` args: `scope: "repo"`, `files` from the Phase 0 scope walk above (not a diff).
- Phase 4 never writes `/tmp/claude-audit-passed-*` — `/full-audit` has no push gate. Everything
  else (log finalization, `run-cost.sh`, `run-log.sh --counts`, in-progress marker release,
  learning phase) is identical.

`runId` for both the find and fix workflows goes into the same log-header position `audit/SKILL.md`
uses, so `Workflow({ scriptPath, resumeFromRunId })` resumes a full-audit run exactly like a
regular one across a session limit.

## Last line of every run

```
Audit: {C} Critical, {I} Important offen | Push nicht zutreffend
```
