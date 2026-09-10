---
name: full-audit
description: "Comprehensive one-time audit of an entire codebase (not just recent changes). Auto-detects framework, runs the same per-dimension Workflow pipeline as /audit across all 13 dimensions (plus a conditional 14th, payments, on repos with a Stripe integration) with SCOPE=repo, fixes per the chosen scope (Minor always logged, never fixed). Use when the user runs /full-audit, starts on a new project, asks for a comprehensive review, or wants the whole codebase checked. NOT for pre-push of recent changes — use /audit instead."
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
STRIPE_OUT="$(bash "$AUDIT_BIN/detect-stripe.sh" "$(git rev-parse --show-toplevel)")"
STRIPE=$(printf '%s\n' "$STRIPE_OUT" | sed -n 's/^STRIPE=//p')
STRIPE_MODE=$(printf '%s\n' "$STRIPE_OUT" | sed -n 's/^STRIPE_MODE=//p')
STRIPE_RECURRING=$(printf '%s\n' "$STRIPE_OUT" | sed -n 's/^STRIPE_RECURRING=//p')
STRIPE_FILES=$(printf '%s\n' "$STRIPE_OUT" | sed -n '/^STRIPE_FILES<<END$/,/^END$/{/^STRIPE_FILES<<END$/d;/^END$/d;p;}')

# project_path for the run ledger: the MAIN checkout via --git-common-dir, not
# the worktree (see run-log.sh header comment — run-stats.sh keys per-repo
# conditions on this exact field).
GIT_COMMON_DIR="$(git rev-parse --path-format=absolute --git-common-dir)"
case "$GIT_COMMON_DIR" in
  */.git) PROJECT_PATH="${GIT_COMMON_DIR%/.git}" ;;
  *) PROJECT_PATH="$(git rev-parse --show-toplevel)" ;;
esac

# payments re-run decision: default is RERUN=1 (re-run), the safe default for
# every degenerate case (no ledger, no jq, payments_head that no longer
# resolves to a commit) — never "abort", always "re-run".
PAYMENTS_RERUN=1
PAYMENTS_SKIP_NOTE=""
if [ "$STRIPE" = "yes" ]; then
  LEDGER_FILE="$HOME/.local/state/claude/skill-runs.jsonl"
  if command -v jq >/dev/null 2>&1 && [ -f "$LEDGER_FILE" ]; then
    PRIOR=$(jq -c --arg p "$PROJECT_PATH" \
      'select(.project_path == $p) | select(.counts.payments_head != null)' \
      "$LEDGER_FILE" 2>/dev/null | tail -1)
    if [ -n "$PRIOR" ]; then
      PRIOR_HEAD=$(printf '%s' "$PRIOR" | jq -r '.counts.payments_head')
      PRIOR_TS=$(printf '%s' "$PRIOR" | jq -r '.ts')
      # (a) prior entry found. Only trust it when PRIOR_HEAD still resolves —
      # a rebase, a shallow clone or a fresh machine make an old sha
      # unresolvable, and that means re-run, never abort.
      if git cat-file -e "${PRIOR_HEAD}^{commit}" 2>/dev/null; then
        CHANGED_SINCE=$(git diff --name-only "$PRIOR_HEAD"..HEAD 2>/dev/null)
        # (b) diff since payments_head intersects the Stripe surface
        STRIPE_TOUCHED_SINCE=$(comm -12 <(printf '%s\n' "$CHANGED_SINCE" | sort -u) <(printf '%s\n' "$STRIPE_FILES" | sort -u))
        # (c) the Stripe dependency version changed in the lockfile diff
        DEP_TOUCHED_SINCE=$(git diff "$PRIOR_HEAD"..HEAD -- composer.lock package-lock.json 2>/dev/null | grep -iE '^\+.*stripe' || true)
        # (d) the golive dashboard answers are missing
        STRIPE_GOLIVE_FILE="$(git rev-parse --show-toplevel)/.claude/stripe-golive.md"
        if [ -z "$STRIPE_TOUCHED_SINCE" ] && [ -z "$DEP_TOUCHED_SINCE" ] && [ -f "$STRIPE_GOLIVE_FILE" ]; then
          PAYMENTS_RERUN=0
          PAYMENTS_SKIP_NOTE="last run $PRIOR_TS at sha $PRIOR_HEAD"
        fi
      fi
    fi
  fi
fi
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

**`payments` (CONDITIONAL 14th dimension):** on `STRIPE=yes` (from Phase 0), `payments` is in scope
with `SCOPE=repo`, i.e. the whole `STRIPE_FILES` surface, not a diff-based subset — `/full-audit`
has no diff to intersect against, that gating only exists in `/audit`. Whether it actually *runs*
this time is `PAYMENTS_RERUN` from Phase 0: `1` → add `payments` to `SELECTED_DIMENSIONS`; `0` →
leave it out and print `payments: skipped, no change since $PAYMENTS_SKIP_NOTE`.

When `payments` is added to `SELECTED_DIMENSIONS`, append `payments.md<TAB>mandatory<TAB>scoped` to
`GUIDELINE_MATCHES` if `match-guidelines.sh` did not already emit it, same reason and same
condition as `audit/SKILL.md` Phase 1.5: `guidelines/payments.md`'s `applies_to` regex may not match
a generic file in the payment surface, but the dimension only runs once the repo is already known to
be a Stripe integration, so the guideline always applies when it runs.

## Phase 2-5: same as `audit/SKILL.md`, with `SCOPE=repo`, no marker

Run Phases 2 through 5 of `audit/SKILL.md` unchanged, with two substitutions:

- `find.js` args: `scope: "repo"`, `files` the Phase 0 scope walk above (not a diff), and `fileContents` built the same way as `audit/SKILL.md` Phase 2 (read every file in that scope with the Read tool in batches, pass the path-to-content map). `STRIPE_FILES` is deliberately NOT unioned into `files` and NOT read into `fileContents` here: the `payments` scout and its specialists read that surface themselves, and passing its content inline cost about 104 KB of orchestrator context in a real repo, enough to make a session bypass the whole pipeline. `find.js` only requires complete `fileContents` for `args.files`; a `dimensionFiles`-only path without content simply falls back to the scout for that dimension. One `find.js` call for every selected dimension, same as `audit/SKILL.md` Phase 2: when `payments` is in `SELECTED_DIMENSIONS`, pass `dimensionFiles: { payments: STRIPE_FILES }` and `dimensionContext: { payments: "STRIPE_MODE=" + STRIPE_MODE + " STRIPE_RECURRING=" + STRIPE_RECURRING }` alongside the shared `files`/`dimensions`/`guidelines` args, otherwise both default to `{}`.
- Phase 4 never writes `/tmp/claude-audit-passed-*` — `/full-audit` has no push gate, so the
  coverage conditions that gate `audit/SKILL.md`'s marker do not apply here. The log still must
  say the same thing they would check: any dimension that came back `skipped` or `status:
  incomplete`, and the `degradedDimensions` array from the Phase 2 `find.js` result, go in the log
  under `## Not completed` same as `audit/SKILL.md`. Everything else (log finalization,
  `run-cost.sh`, `run-log.sh --counts`, in-progress marker release, learning phase) is identical,
  plus: when `payments` ran, add `payments_head=$(git rev-parse HEAD)` to the `--counts` argument,
  same as `audit/SKILL.md` Phase 4 — this is the value the Phase 0 re-run decision reads back on
  the next run.

`runId` for both the find and fix workflows goes into the same log-header position `audit/SKILL.md`
uses, so `Workflow({ scriptPath, resumeFromRunId })` resumes a full-audit run exactly like a
regular one across a session limit.

## Last line of every run

```
Audit: {C} Critical, {I} Important offen | Push nicht zutreffend
```
