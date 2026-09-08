---
name: audit
description: "Pre-push code audit. Runs a per-dimension audit pipeline (13 dimensions: architecture, security, performance, code quality, SEO, a11y, typography, UI, UX, animation, docs sync, copy, privacy), plus deterministic secret/lockfile/i18n/CI-hardening pre-checks, one fix wave with peer-review verification, then allows git push. Two start questions (dimensions, fix scope) replace the old argument form. Use when the user runs /audit, says 'before pushing' or 'review my changes', or has uncommitted/unpushed changes that should be checked. NOT for whole-codebase audits, use /full-audit instead."
when_to_use: "/audit, vor dem pushen prüfen, Änderungen vor dem push checken, ist das sauber genug zum pushen, kurzer check vor dem commit, diff nochmal prüfen, before pushing, git push, pre-push review, review my changes, audit uncommitted changes, check before pushing"
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
hooks:
  PreToolUse:
    - matcher: "Bash"
      hooks:
        - type: command
          command: bash -c 'for c in "$HOME/.claude/skills/audit" "$HOME/.claude/skills/claude-skills/audit"; do [ -f "$c/hooks/pretooluse-bash.sh" ] && exec bash "$c/hooks/pretooluse-bash.sh"; done; exit 0'
---

# Audit: per-dimension pipeline

## Runtime selection (before Phase 0)

Resolve `AUDIT_ROOT` from the absolute path of the **actual loaded** `audit/SKILL.md`,
not from the project directory or an assumed installation. Persist that literal in subsequent
shell calls. In Claude, `CLAUDE_SKILL_DIR` may supply this path when available.
Set `AUDIT_RUNTIME=codex` when native collaboration tools are available, otherwise
`AUDIT_RUNTIME=claude` when the native `Agent` tool is available. If neither is available,
report the missing runtime and stop without a successful audit result.

For both runtimes, read `references/codex-runtime.md` now. Its shared Node request/response
bridge executes the same `workflows/find.js` and `workflows/fix.js`; only native worker
dispatch differs. Claude uses `Agent`, Codex uses collaboration. Do not use `Workflow`
resume: nested parallel replay has redispatched completed workers. Never launch `claude`
or `codex` from a shell or require API keys. In Codex, skip Claude transcript accounting,
learning runtime instructions and hook commands; never apply Claude model prices.
Run the shared prechecks and decision/logging rules below through the native mapping.
A missing tool or agent response means incomplete, never permission to omit verification.

Use the current checkout from `git rev-parse --show-toplevel` as `PROJECT_ROOT` for both code
and state. Codex state belongs to `$PROJECT_ROOT/.codex/audits` (standard lowercase); do not
redirect it to the main checkout through `git-common-dir` or rely on legacy `.Codex` hooks.
Read the applicable `AGENTS.md` instructions and `.codex/audit-guidelines.md` in Codex;
when the latter is absent, `.claude/audit-guidelines.md` remains a supported project fallback.
Claude keeps `.claude/audits`. No Codex hook installation is assumed.

**Start directly with Phase 0.** This is a pre-push gate the user is waiting on.

## Phase 0: Pre-flight checks

Learning backlog question + open `audit-finding` issues/PR dedup context:
`references/pre-flight-checks.md`. Skip entirely when `AUDIT_SKIP_LEARNING_CHECK=1`.

## Phase 1: Scope & pre-checks

```bash
AUDIT_BIN="${AUDIT_ROOT}/bin"
AUDIT_AGENTS_DIR="${AUDIT_ROOT}/agents"
[ "$AUDIT_RUNTIME" != claude ] || bash "$AUDIT_BIN/run-log.sh" --start --skill audit
bash "$AUDIT_BIN/verify-agents.sh" "$AUDIT_AGENTS_DIR" || { echo "Audit abgebrochen, fehlende Agent-Dateien."; exit 1; }
SCOPE_OUT="$(bash "$AUDIT_BIN/collect-scope.sh")"
BASE_REF=$(printf '%s\n' "$SCOPE_OUT" | sed -n 's/^BASE_REF=//p')
ALLE_DATEIEN=$(printf '%s\n' "$SCOPE_OUT" | sed -n '/^---FILES---$/,/^---FRONTEND---$/{/^---FILES---$/d;/^---FRONTEND---$/d;p}')
echo "BASE_REF=$BASE_REF"
echo "ALLE_DATEIEN: $(printf '%s\n' "$ALLE_DATEIEN" | grep -c .) file(s)"
FW_OUT="$(bash "$AUDIT_BIN/detect-framework.sh")"
FRAMEWORK=$(printf '%s\n' "$FW_OUT" | sed -n 's/^FRAMEWORK=//p')
SOURCE_DIRS=$(printf '%s\n' "$FW_OUT" | sed -n 's/^SOURCE_DIRS=//p')
PLATFORM=$(printf '%s\n' "$FW_OUT" | sed -n 's/^PLATFORM=//p')
bash "$AUDIT_BIN/pre-checks.sh"
bash "$AUDIT_BIN/check-ci-hardening.sh" "$(git rev-parse --show-toplevel)"   # HITS become Important security findings, no specialist needed
if echo "$ALLE_DATEIEN" | grep -qE '(package(-lock)?\.json|composer\.(json|lock)|yarn\.lock|pnpm-lock\.yaml|requirements\.txt|pyproject\.toml|Podfile(\.lock)?|Package\.(swift|resolved)|pubspec\.(yaml|lock)|build\.gradle)'; then
  bash "$AUDIT_BIN/check-outdated.sh" "$(git rev-parse --show-toplevel)"
fi
bash "$AUDIT_BIN/check-i18n-keys.sh"; bash "$AUDIT_BIN/check-duplicate-array-keys.sh"
bash "$AUDIT_BIN/check-number-format-locale.sh"; bash "$AUDIT_BIN/check-swift-deprecations.sh"
bash "$AUDIT_BIN/check-token-contrast.sh"; bash "$AUDIT_BIN/check-test-count-drift.sh"
bash "$AUDIT_BIN/check-docs-path-drift.sh" "$BASE_REF"; bash "$AUDIT_BIN/check-docs-claims.sh"

PROJECT_ROOT="$(git rev-parse --show-toplevel)"
PROJECT_GUIDELINES_FILE="$PROJECT_ROOT/.claude/audit-guidelines.md"
if [ "$AUDIT_RUNTIME" = codex ] && [ -f "$PROJECT_ROOT/.codex/audit-guidelines.md" ]; then
  PROJECT_GUIDELINES_FILE="$PROJECT_ROOT/.codex/audit-guidelines.md"
fi
PROJECT_GUIDELINES=""
[ -f "$PROJECT_GUIDELINES_FILE" ] && PROJECT_GUIDELINES=$(cat "$PROJECT_GUIDELINES_FILE")
bash "$AUDIT_BIN/diff-size-gate.sh"
eval "$(bash "$AUDIT_BIN/perf-measure.sh" --detect)"
GUIDELINE_MATCHES=$(bash "$AUDIT_BIN/match-guidelines.sh" "${AUDIT_ROOT}/guidelines" 2>/dev/null)
AUDIT_BASE_HEAD=$(git rev-parse HEAD)

# In-progress marker: run-scoped (claim now, touch after find.js, touch after fix.js, release at Phase 4).
CWD_HASH=$(pwd | md5 2>/dev/null || pwd | md5sum 2>/dev/null | cut -d' ' -f1)
[ "$AUDIT_RUNTIME" != claude ] || touch "/tmp/claude-audit-in-progress-${CWD_HASH}"
```

Deterministic-check result table and derivation of `ALLE_DATEIEN`/`FRONTEND_DATEIEN`/`SUPPRESSIONS`/`PROJECT_CONTEXT`/`DECIDED_TRADEOFFS`: `references/scope-and-pre-checks.md`. Prose gate (`DIFF_CLASS=prose`, from `bin/classify-diff.sh`) limits the dimension preselection to `docs_sync`+`copy` and the fix-scope preselection to "find only": `references/prose-gate.md`.

**HUGE diff:** check the delta-scope carve-out and same-HEAD slice criteria in `references/scope-and-pre-checks.md` before aborting. Every slice uses the shared per-dimension bridge and complete coverage gates.

**WIP/stale-snapshot scope check:** does the working tree contain files that clearly do NOT belong to the current task? Clarify scope with the runtime question mechanism only when existing authorization does not resolve it: session/task changes or the entire working tree.

## Phase 1.5: Start questions (dimensions + fix scope)

**A set variable suppresses both questions.** If `AUDIT_DIMENSIONS` or `AUDIT_FIX_SCOPE` is set (CI/eval-harness/headless), skip `AskUserQuestion` entirely: the set variable takes its value, the other takes its default (all dimensions; fix-scope preselection from `CLAUDE_EFFORT` below). This guarantees a headless run never hangs on a question.

Honor explicit scope and fix authorization from the conversation first. In Codex, use the native question mapping in `references/codex-runtime.md`; do not require a missing `AskUserQuestion` tool. Otherwise ask exactly one `AskUserQuestion` round, two questions, presets from `references/dimension-selection.md`:

- **(a) Dimensions:** All (default) | Backend | Frontend | Custom (multi-select over all 13).
- **(b) Fix scope:** find & log only | fix Critical | fix Critical and Important. Preselection from `${CLAUDE_EFFORT:-medium}`: `low` → find only, `medium` → Critical, `high`/`xhigh` → Critical and Important.

Result: `AUDIT_DIMENSIONS` (comma list) and `AUDIT_FIX_SCOPE` (`none|critical|all`). A partial selection at (a) never writes the push marker (same rule as before), and the log names the dimensions not checked.

## Phase 2: Find

```bash
PROJECT_ROOT="$(git rev-parse --show-toplevel)"
if [ "$AUDIT_RUNTIME" = codex ]; then AUDIT_DIR="$PROJECT_ROOT/.codex/audits";
else AUDIT_DIR="$PROJECT_ROOT/.claude/audits"; fi
mkdir -p "$AUDIT_DIR"
LOGFILE="$AUDIT_DIR/$(date +%Y-%m-%d_%H%M%S)-$(git branch --show-current | tr '/' '-').md"
```

**Both runtimes:** initialize and step the shared bridge as specified in `references/codex-runtime.md`, with `repoRoot: PROJECT_ROOT`, `scope: "diff"`, `files: ALLE_DATEIEN`, `dimensions: AUDIT_DIMENSIONS`, `effort: CLAUDE_EFFORT`, `promptDir: AUDIT_AGENTS_DIR`, `guidelinesDir: "${AUDIT_ROOT}/guidelines"`, and `guidelines: GUIDELINE_MATCHES`. The bridge reads scope contents and persists run state. Before dispatch, write the log stub with base HEAD, scope, dimensions, the find run directory and empty Findings/Fixes sections. Persist native worker associations with `bind` before waiting. Resume with `step` on that same directory.

Claude only: refresh the in-progress marker after completion (`[ "$AUDIT_RUNTIME" != claude ] || touch "/tmp/claude-audit-in-progress-${CWD_HASH}"`, staleness 45 min). Read the bridge output JSON: `{dimensions: {[dim]: {status, files, chunks, findings, verdicts, uncovered}}, skipped}`.

**Decide per finding** (`CONFIRMED` verdicts only; `REFUTED` discarded with reason, `UNCERTAIN` never fixed, listed under `### Unverified`): fix / log / discard, following `AUDIT_FIX_SCOPE`, `none` logs everything, `critical` fixes only `severity: Critical`, `all` fixes `Critical` and `Important`. **Minor is never fixed, always logged.** Two findings that contradict each other: decide which one loses, mark it `discard: conflict with {id}` in the log. The find result must return `status: complete`. Every selected dimension must return `status: complete`, or a justified `status: skipped` from a successful empty scout with no findings or coverage gaps. Require complete finding verdict coverage and empty `uncovered`, `unverified`, and `unrefuted` lists wherever present. Any `UNCERTAIN` finding also blocks the push gate. Missing or unknown statuses/verdicts, failed requests, uncovered files, or interrupted verifiers block completion and the push gate. A dimension with `status: incomplete` gets its own `## Not completed` log section, naming the last reached stage; the other dimensions still ran to completion.

Record concrete call-site or definition evidence for every refutation in the log, with a
`file:line` actually read this run. In Claude, preserve `patterns-store.sh dismissed {pattern}`
for refuted findings. Orchestrator evidence goes to the mandatory independent verifier;
it never substitutes for a completed verifier response. If verification is unavailable or
skipped, record `Verification skipped: {reason}` under `## Incidents` and keep the run incomplete.

## Phase 3: Fix

If no fixes were selected, record `fix: not_requested` and skip the fix wave in either runtime.

Measure the test-suite baseline once: `bash "$AUDIT_BIN/test-lock.sh" {TEST_COMMAND}` → `BASELINE_FAILURES`.

**Both runtimes:** initialize a separate fix run through the shared bridge with `repoRoot: PROJECT_ROOT`, `fixes: [{file, findings}]` grouped by file, `promptDir: AUDIT_AGENTS_DIR`, `testCommand: TEST_COMMAND`, `baselineFailures: BASELINE_FAILURES`, `budget: 25`, and `auditBin: AUDIT_BIN`. Record the directory in the log before dispatch. Never skip peer verification or regression checks.

In Claude, refresh the in-progress marker after completion. In both runtimes read `{fixes, verdicts, regressions, rejected, blockingRegressions}`. A `REJECT` fix-verdict or a rejected fix stays an open point, `fix.js` runs no second round in the same pass.

A requested fix phase must return `status: complete` with empty `uncovered` and a verdict for every attempted fix and completed regression checks; otherwise the result is incomplete and blocks the gate. Unknown verdicts and missing results also block.

Run the full suite exactly once via `test-lock.sh` after the fix wave (fix-verifiers only ran filtered tests). A `blockingRegressions` entry (Critical/Important from the regression pass) becomes an open point and blocks the marker below.

## Phase 4: Log, marker, run-ledger

Finalize `LOGFILE` from `references/audit-log-template.md`: Result, Findings per dimension, Fixes, Discarded (with reason), Unverified, Not completed, Open Points. Include runtime, overall status, selected/completed dimensions, dispatched/completed/failed agent counts, verified/unverified findings, actual available usage and cost status. Codex cost is `null`/unavailable unless actual accounting is available; never claim zero or estimate it from Claude prices. Include the mechanical checks from Phase 1 and a chat display of the finished log (markdown block).

**Claude accounting/ledger only** (Codex writes the same fields directly to its log and retains bridge status):

```bash
AUDIT_BIN="${AUDIT_ROOT}/bin"
# A Claude Code session has no env var pointing at its own transcript dir:
# derive the projects dir from cwd using the same slug convention as
# ~/.claude/projects/ (every "/" becomes "-").
CLAUDE_PROJECTS_DIR="$HOME/.claude/projects/$(pwd | sed 's#/#-#g')"
bash "$AUDIT_BIN/run-cost.sh" --latest "$CLAUDE_PROJECTS_DIR" --json 2>/dev/null   # cost line for the log header + run-ledger
bash "$AUDIT_BIN/run-log.sh" --skill audit --outcome "{gate}" \
  --counts "critical={N_CRITICAL},important={N_IMPORTANT},minor={N_MINOR},usd={USD}" --gate "{blocked|partial|passed}"
```

**Claude marker only** (`/tmp/claude-audit-passed-{md5 cwd}`, never in the same Bash call as `git push`): set only when every selected dimension completed or was justifiably skipped by a successful empty scout, every requested fix phase completed, every finding/fix has a recognized verdict, all `uncovered`, `unverified`, and `unrefuted` lists are empty and no incomplete verification remains, no verdict remains `UNCERTAIN`, no Critical is open, and no new test failure exists beyond `BASELINE_FAILURES`. Codex records the same gate in its log; it does not write a Claude marker. A partial dimension selection (Phase 1.5) never sets it, print the reason instead.

```bash
hash=$(echo -n "$PWD" | md5 2>/dev/null || echo -n "$PWD" | md5sum 2>/dev/null | cut -d' ' -f1)
touch "/tmp/claude-audit-passed-$hash"   # only on the conditions above
```

Claude only: release the in-progress marker: `rm -f "/tmp/claude-audit-in-progress-${CWD_HASH}"`.

## Phase 5: Learning

In Codex, use the native runtime reference for learning; any unavailable learning step is recorded separately and never launches Claude. The remainder of this phase is Claude-only. Skipped when `CLAUDE_EFFORT=low`. Otherwise read `references/learning-phase.md`: dispatch the learning agent (`run_in_background: false`), parse its output, write learning-log/trends/suppressions.

## Phase 6: PR (after push)

`references/pr-creation.md`. Errors don't block.

## Last line of every run

```
Audit: {C} Critical, {I} Important offen | Push {frei|blockiert|nicht zutreffend}
```
