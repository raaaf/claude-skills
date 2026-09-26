---
name: full-audit
description: "Comprehensive one-time audit of an entire codebase (not just recent changes). Auto-detects framework, runs the same per-dimension Workflow pipeline as /audit across all 13 dimensions (plus a conditional 14th, payments, on repos with a Stripe integration) with SCOPE=repo, fixes every finding incl. Minor or discards it with a reason. Use when the user runs /full-audit, starts on a new project, asks for a comprehensive review, or wants the whole codebase checked. NOT for pre-push of recent changes — use /audit instead."
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
# Shared prologue (audit/bin/lib-orchestrator.sh); finding it is the one loop that stays inline.
for c in "$(dirname "${CLAUDE_SKILL_DIR:-/nonexistent}")/audit/bin/lib-orchestrator.sh" \
         "$HOME/.claude/skills/audit/bin/lib-orchestrator.sh"; do
  [ -f "$c" ] && { . "$c"; break; }
done
type orch_resolve_audit_root >/dev/null 2>&1 || { echo "Abgebrochen — audit-Skill nicht gefunden (lib-orchestrator.sh). audit neben full-audit installieren."; exit 1; }
orch_resolve_audit_root || { echo "Abgebrochen — audit-Root nicht gefunden."; exit 1; }
AUDIT_AGENTS="$AUDIT_AGENTS_DIR"; orch_run_log --start --skill full-audit
orch_verify_agents || { echo "Abgebrochen — fehlende Agent-Dateien."; exit 1; }
FW_OUT="$(bash "$AUDIT_BIN/detect-framework.sh")"
FRAMEWORK=$(printf '%s\n' "$FW_OUT" | sed -n 's/^FRAMEWORK=//p')
SOURCE_DIRS=$(printf '%s\n' "$FW_OUT" | sed -n 's/^SOURCE_DIRS=//p')
PRECHECK_OUT="$(bash "$AUDIT_BIN/pre-checks.sh")"; printf '%s\n' "$PRECHECK_OUT"   # SECRET lines are [Critical][security] findings in the log (no marker here, but never silent)
bash "$AUDIT_BIN/check-ci-hardening.sh" "$(git rev-parse --show-toplevel)"
bash "$AUDIT_BIN/check-outdated.sh" "$(git rev-parse --show-toplevel)"
orch_parse_stripe "$(git rev-parse --show-toplevel)"   # sets STRIPE, STRIPE_MODE, STRIPE_RECURRING, STRIPE_FILES (lib-orchestrator.sh)

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
orch_progress_claim   # run-scoped in-progress marker: claimed here, touched after each Notification, released in Phase 4
orch_state_save FRAMEWORK SOURCE_DIRS PRECHECK_OUT STRIPE STRIPE_MODE STRIPE_RECURRING STRIPE_FILES PROJECT_PATH PAYMENTS_RERUN PAYMENTS_SKIP_NOTE   # read back by later blocks with orch_state_load
```

**Scope** (equivalent of `collect-scope.sh --all`, `full-audit/references/scope.md` for the exact
glob and bash block — execute it here):
`SOURCE_DIRS` walked for the fixed extension list plus `scope-extensions:` from
`.claude/audit-guidelines.md`. `PROJECT_GUIDELINES` read the same way as `/audit` Phase 1.

In-progress marker: claimed in the Phase 0 block above; the touch after each Notification and the
release at Phase 4 are the `audit/SKILL.md` blocks that Phases 2-5 run (same lib functions, same
state dir).

## Phase 1.5: Start question

**Same rule and same question as `audit/SKILL.md` Phase 1.5** ("A set variable suppresses the
question"): `AUDIT_DIMENSIONS` / `AUDIT_FIX_SCOPE`, `references/dimension-selection.md`
(now under `audit/references/`) for the presets. `/full-audit` sets no push marker regardless of
the answer, so a partial selection here has no gate consequence, only a smaller log.

**`payments` (CONDITIONAL 14th dimension):** on `STRIPE=yes` (from Phase 0), `payments` is in scope
with `SCOPE=repo`, i.e. the whole `STRIPE_FILES` surface, not a diff-based subset — `/full-audit`
has no diff to intersect against, that gating only exists in `/audit`. Whether it actually *runs*
this time is `PAYMENTS_RERUN` from Phase 0: `1` → add `payments` to `AUDIT_DIMENSIONS`; `0` →
leave it out and print `payments: skipped, no change since $PAYMENTS_SKIP_NOTE`. It appends
`payments.md<TAB>mandatory<TAB>scoped` if `match-guidelines.sh` did not already emit it:
`guidelines/payments.md`'s `applies_to` regex may not match a generic file in the payment surface,
but the dimension only runs once the repo is already known to be a Stripe integration, so the
guideline always applies when it runs.

```bash
for c in "$(dirname "${CLAUDE_SKILL_DIR:-/nonexistent}")/audit/bin/lib-orchestrator.sh" "$HOME/.claude/skills/audit/bin/lib-orchestrator.sh"; do [ -f "$c" ] && { . "$c"; break; }; done   # fresh shell per block
orch_state_load   # STRIPE, PAYMENTS_RERUN, PAYMENTS_SKIP_NOTE from Phase 0; GUIDELINE_MATCHES from the scope walk
AUDIT_DIMENSIONS="${AUDIT_DIMENSIONS:-{comma list from the question; all 13 ids when the answer was All}}"   # a set env var (headless) wins, else the answer, substituted here
[ "$AUDIT_DIMENSIONS" = all ] && AUDIT_DIMENSIONS="architecture,security,performance,code_quality,seo,a11y,typography,ui_design,ux,animation,docs_sync,copy,privacy"   # the headless spelling; find.js accepts dimension ids only
AUDIT_FIX_SCOPE="${AUDIT_FIX_SCOPE:-all}"; [ "$AUDIT_FIX_SCOPE" = none ] || AUDIT_FIX_SCOPE=all   # headless 'none' = find and log only; everything else fixes every finding incl. Minor
if [ "$STRIPE" = "yes" ]; then
  if [ "$PAYMENTS_RERUN" = "1" ]; then
    AUDIT_DIMENSIONS="${AUDIT_DIMENSIONS:+$AUDIT_DIMENSIONS,}payments"
    GUIDELINE_MATCHES=$(orch_payments_guidelines "$GUIDELINE_MATCHES")   # payments.md always applies once the dimension runs (lib)
  else
    echo "payments: skipped, no change since $PAYMENTS_SKIP_NOTE"
  fi
fi
echo "AUDIT_DIMENSIONS=$AUDIT_DIMENSIONS AUDIT_FIX_SCOPE=$AUDIT_FIX_SCOPE"
orch_state_save AUDIT_DIMENSIONS AUDIT_FIX_SCOPE GUIDELINE_MATCHES
```

## Phase 2-5: same as `audit/SKILL.md`, with `SCOPE=repo`, no marker

Run Phases 2 through 5 of `audit/SKILL.md` unchanged, with three substitutions:

- `find.js` args: `scope: "repo"`, `files` the Phase 0 scope walk above (not a diff), and `floorFiles`
  built the same way as `audit/SKILL.md` Phase 2: the orchestrator never reads scope-file content at
  all, since `find.js` has no filesystem access and the scout/specialist subagents read the repo
  themselves; the block below computes `FLOOR_FILES` with the helper and prints it, using
  `ALLE_DATEIEN`, the same Phase 0 scope-walk list `references/scope.md` produces. `STRIPE_FILES` is
  deliberately NOT unioned into `files`: it is not part of the Phase 0 repo walk's scope, and
  unioning it in would widen what every other dimension audits. It IS passed to the helper, in a
  second invocation, because the helper reads files from disk itself, so handing it the surface costs
  the orchestrator nothing, and `payments` should get a deterministic floor over the surface it
  actually scouts, same as `audit/SKILL.md` Phase 2:

  ```bash
  for c in "$(dirname "${CLAUDE_SKILL_DIR:-/nonexistent}")/audit/bin/lib-orchestrator.sh" "$HOME/.claude/skills/audit/bin/lib-orchestrator.sh"; do [ -f "$c" ] && { . "$c"; break; }; done   # fresh shell per block: source the lib again
  orch_resolve_audit_root || { echo "Abgebrochen — audit-Root nicht gefunden."; orch_progress_release; exit 1; }
  orch_state_load   # ALLE_DATEIEN, AUDIT_DIMENSIONS, STRIPE_FILES, PROJECT_ROOT from the blocks above
  FLOOR_FILES=$(printf '%s\n' "$ALLE_DATEIEN" | node "$AUDIT_BIN/compute-floor.mjs" "$PROJECT_ROOT" "$AUDIT_DIMENSIONS")   # content-based scout floor, {"<dimension>": ["<path>", ...]} for every selected dimension
  FLOOR_FILES=$(orch_payments_floor "$AUDIT_DIMENSIONS" "$STRIPE_FILES" "$PROJECT_ROOT" "$FLOOR_FILES")   # same lib call as /audit Phase 2
  printf 'FLOOR_FILES=%s\n' "$FLOOR_FILES"   # pass this JSON as floorFiles in the Workflow call below
  ```

  Inlining the surface's content, back when the floor ran inline in the orchestrator, cost about
  104 KB of context in a real repo, enough to make a session bypass the whole pipeline (a second
  session then routed every dimension through `dimensionFiles` to dodge it, which starved every
  content floor and left five of fourteen dimensions skipped or incomplete). A dimension absent from
  `floorFiles` simply falls back to the scout for that dimension. One `find.js` call for every
  selected dimension, same as `audit/SKILL.md` Phase 2: when `payments` is in `AUDIT_DIMENSIONS`,
  pass `dimensionFiles: { payments: STRIPE_FILES }` and `dimensionContext: { payments: "STRIPE_MODE=" +
  STRIPE_MODE + " STRIPE_RECURRING=" + STRIPE_RECURRING }` alongside the shared `files`/`dimensions`/
  `guidelines` args, otherwise both default to `{}`.
- Phase 4 never writes `/tmp/claude-audit-passed-*` — `/full-audit` has no push gate, so the
  coverage conditions that gate `audit/SKILL.md`'s marker do not apply here. The log still must
  say the same thing they would check: any dimension that came back `skipped` or `status:
  incomplete`, and the `degradedDimensions` array from the Phase 2 `find.js` result, go in the log
  under `## Not completed` same as `audit/SKILL.md`. Everything else (log finalization,
  `run-cost.sh`, `run-log.sh --counts` with `--skill full-audit` (not the literal `--skill audit`
  that `audit/SKILL.md` writes; the ledger keys per skill and the start marker at line 41 already
  says `full-audit`), in-progress marker release, learning phase) is identical,
  plus: when `payments` ran, add `payments_head=$(git rev-parse HEAD)` to the `--counts` argument,
  same as `audit/SKILL.md` Phase 4 — this is the value the Phase 0 re-run decision reads back on
  the next run.
- `audit/SKILL.md`'s Phase 2 block also computes `HUNK_SCOPE` from `$DIFF_SIZE_RESULT` (`case
  "$DIFF_SIZE_RESULT" in SMALL|"") HUNK_SCOPE=false ;; *) HUNK_SCOPE=true ;; esac`), reused
  verbatim here even though `/full-audit`'s Phase 0 never runs `diff-size-gate.sh` and so never
  sets `DIFF_SIZE_RESULT` or `BASE_REF` (there is no diff; `SCOPE=repo` walks the whole tree). The
  unset variable matches the explicit `""` branch, so `HUNK_SCOPE` is always `false` here, which is
  the correct behavior (hunk-scoped review only makes sense against a diff); the empty-string
  branch exists precisely so an unset var here does not fall through to the catch-all `*)`, which
  since the `SMALL` result was added now means "true", not "false".

Every finding line follows the machine-parsed contract stated once in `audit/SKILL.md` Phase 4
(one physical line, `- [Severity][Dimension] file:line: description`); this file no longer
repeats the wording, since a rewording that lands in one copy and not the other is how that
contract drifted unnoticed on 2026-09-10.

`runId` for both the find and fix workflows goes into the same log-header position `audit/SKILL.md`
uses, so `Workflow({ scriptPath, resumeFromRunId })` resumes a full-audit run exactly like a
regular one across a session limit.

## Last line of every run

```
Audit: {C} Critical, {I} Important offen | Push nicht zutreffend
```
