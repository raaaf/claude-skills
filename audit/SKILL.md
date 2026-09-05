---
name: audit
description: "Pre-push code audit. Runs a per-dimension Workflow pipeline (13 dimensions: architecture, security, performance, code quality, SEO, a11y, typography, UI, UX, animation, docs sync, copy, privacy), plus deterministic secret/lockfile/i18n/CI-hardening pre-checks, one fix wave with peer-review verification, then allows git push. Two start questions (dimensions, fix scope) replace the old argument form. Use when the user runs /audit, says 'before pushing' or 'review my changes', or has uncommitted/unpushed changes that should be checked. NOT for whole-codebase audits — use /full-audit instead."
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
  - Workflow
hooks:
  PreToolUse:
    - matcher: "Bash"
      hooks:
        - type: command
          command: bash -c 'for c in "$HOME/.claude/skills/audit" "$HOME/.claude/skills/claude-skills/audit"; do [ -f "$c/hooks/pretooluse-bash.sh" ] && exec bash "$c/hooks/pretooluse-bash.sh"; done; exit 0'
---

# Audit: per-dimension pipeline

**Start directly with Phase 0.** This is a pre-push gate the user is waiting on.

## Phase 0: Pre-flight checks

Learning backlog question + open `audit-finding` issues/PR dedup context:
`references/pre-flight-checks.md`. Skip entirely when `AUDIT_SKIP_LEARNING_CHECK=1`.

## Phase 1: Scope & pre-checks

```bash
AUDIT_BIN="${CLAUDE_SKILL_DIR}/bin"
AUDIT_AGENTS_DIR="${CLAUDE_SKILL_DIR}/agents"
bash "$AUDIT_BIN/run-log.sh" --start --skill audit
bash "$AUDIT_BIN/verify-agents.sh" "$AUDIT_AGENTS_DIR" || { echo "Audit abgebrochen — fehlende Agent-Dateien."; exit 1; }
bash "$AUDIT_BIN/collect-scope.sh"
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

PROJECT_GUIDELINES_FILE="$(git rev-parse --show-toplevel)/.claude/audit-guidelines.md"
PROJECT_GUIDELINES=""
[ -f "$PROJECT_GUIDELINES_FILE" ] && PROJECT_GUIDELINES=$(cat "$PROJECT_GUIDELINES_FILE")
bash "$AUDIT_BIN/diff-size-gate.sh"
eval "$(bash "$AUDIT_BIN/perf-measure.sh" --detect)"
GUIDELINE_MATCHES=$(bash "$AUDIT_BIN/match-guidelines.sh" "${CLAUDE_SKILL_DIR}/guidelines" 2>/dev/null)
AUDIT_BASE_HEAD=$(git rev-parse HEAD)

# In-progress marker: run-scoped (claim now, touch after find.js, touch after fix.js, release at Phase 4).
CWD_HASH=$(pwd | md5 2>/dev/null || pwd | md5sum 2>/dev/null | cut -d' ' -f1)
touch "/tmp/claude-audit-in-progress-${CWD_HASH}"
```

Deterministic-check result table and derivation of `ALLE_DATEIEN`/`FRONTEND_DATEIEN`/`SUPPRESSIONS`/`PROJECT_CONTEXT`/`DECIDED_TRADEOFFS`: `references/scope-and-pre-checks.md`. Prose gate (`DIFF_CLASS=prose`, from `bin/classify-diff.sh`) limits the dimension preselection to `docs_sync`+`copy` and the fix-scope preselection to "find only": `references/prose-gate.md`.

**WIP/stale-snapshot scope check:** does the working tree contain files that clearly do NOT belong to the current task? Ask via `AskUserQuestion`: only the session/task changes vs. the entire working tree.

## Phase 1.5: Start questions (dimensions + fix scope)

**A set variable suppresses both questions.** If `AUDIT_DIMENSIONS` or `AUDIT_FIX_SCOPE` is set (CI/eval-harness/headless), skip `AskUserQuestion` entirely: the set variable takes its value, the other takes its default (all dimensions; fix-scope preselection from `CLAUDE_EFFORT` below). This guarantees a headless run never hangs on a question.

Otherwise ask exactly one `AskUserQuestion` round, two questions, presets from `references/dimension-selection.md`:

- **(a) Dimensions:** All (default) | Backend | Frontend | Custom (multi-select over all 13).
- **(b) Fix scope:** find & log only | fix Critical | fix Critical and Important. Preselection from `${CLAUDE_EFFORT:-medium}`: `low` → find only, `medium` → Critical, `high`/`xhigh` → Critical and Important.

Result: `AUDIT_DIMENSIONS` (comma list) and `AUDIT_FIX_SCOPE` (`none|critical|all`). A partial selection at (a) never writes the push marker (same rule as before), and the log names the dimensions not checked.

## Phase 2: Find

```bash
GIT_COMMON_DIR="$(git rev-parse --path-format=absolute --git-common-dir)"
case "$GIT_COMMON_DIR" in
  */.git) PROJECT_ROOT="${GIT_COMMON_DIR%/.git}" ;;
  *) PROJECT_ROOT="$(git rev-parse --show-toplevel)" ;;
esac
AUDIT_DIR="$PROJECT_ROOT/.claude/audits"; mkdir -p "$AUDIT_DIR"
LOGFILE="$AUDIT_DIR/$(date +%Y-%m-%d_%H%M%S)-$(git branch --show-current | tr '/' '-').md"
```

Start the find workflow: `Workflow({ scriptPath: "${CLAUDE_SKILL_DIR}/workflows/find.js", args: { repoRoot: PROJECT_ROOT, scope: "diff", files: ALLE_DATEIEN, dimensions: AUDIT_DIMENSIONS, effort: CLAUDE_EFFORT, promptDir: AUDIT_AGENTS_DIR, guidelines: GUIDELINE_MATCHES } })`.

**Immediately after the tool returns a `runId`** (before waiting for the completion Notification), write the log stub to `LOGFILE` with the Write tool: `## Scope` (base HEAD, changed files, dimensions), `runId`, empty `## Findings`/`## Fixes` sections. This makes the run resumable across a session limit: `Workflow({ scriptPath, resumeFromRunId: runId })` replays completed agents from cache.

Touch the in-progress marker again (`touch "/tmp/claude-audit-in-progress-${CWD_HASH}"`, staleness 45 min) once the Notification arrives, then read the returned JSON: `{dimensions: {[dim]: {status, files, chunks, findings, verdicts, uncovered}}, skipped}`.

**Decide per finding** (`CONFIRMED` verdicts only; `REFUTED` discarded with reason, `UNCERTAIN` never fixed, listed under `### Unverified`): fix / log / discard, following `AUDIT_FIX_SCOPE` — `none` logs everything, `critical` fixes only `severity: Critical`, `all` fixes `Critical` and `Important`. **Minor is never fixed, always logged.** Two findings that contradict each other: decide which one loses, mark it `discard: conflict with {id}` in the log. A dimension with `status: incomplete` gets its own `## Not completed` log section, naming the last reached stage; the other dimensions still ran to completion.

## Phase 3: Fix

Measure the test-suite baseline once: `bash "$AUDIT_BIN/test-lock.sh" {TEST_COMMAND}` → `BASELINE_FAILURES`.

Start the fix workflow: `Workflow({ scriptPath: "${CLAUDE_SKILL_DIR}/workflows/fix.js", args: { repoRoot: PROJECT_ROOT, fixes: [...findings selected to fix, grouped by file...], testCommand: TEST_COMMAND, baselineFailures: BASELINE_FAILURES, budget: 25, auditBin: AUDIT_BIN } })`. Record this second `runId` in the log stub too.

Touch the in-progress marker again after the Notification. Read `{fixes, verdicts, regressions, rejected, blockingRegressions}`. A `REJECT` fix-verdict or a rejected fix stays an open point — `fix.js` runs no second round in the same pass.

Run the full suite exactly once via `test-lock.sh` after the fix wave (fix-verifiers only ran filtered tests). A `blockingRegressions` entry (Critical/Important from the regression pass) becomes an open point and blocks the marker below.

## Phase 4: Log, marker, run-ledger

Finalize `LOGFILE` from `references/audit-log-template.md`: Result, Findings per dimension, Fixes, Discarded (with reason), Unverified, Not completed, Open Points. Include the mechanical checks from Phase 1 and a chat display of the finished log (markdown block).

```bash
bash "$AUDIT_BIN/run-cost.sh" --json "$CLAUDE_TRANSCRIPT_DIR" 2>/dev/null   # cost line for the log header + run-ledger
bash "$AUDIT_BIN/run-log.sh" --skill audit --outcome "{gate}" \
  --counts "critical={N_CRITICAL},important={N_IMPORTANT},minor={N_MINOR},usd={USD}" --gate "{blocked|partial|passed}"
```

**Marker** (`/tmp/claude-audit-passed-{md5 cwd}`, never in the same Bash call as `git push`): set only when no Critical is open AND no new test failure beyond `BASELINE_FAILURES`. A partial dimension selection (Phase 1.5) never sets it — print the reason instead.

```bash
hash=$(echo -n "$PWD" | md5 2>/dev/null || echo -n "$PWD" | md5sum 2>/dev/null | cut -d' ' -f1)
touch "/tmp/claude-audit-passed-$hash"   # only on the conditions above
```

Release the in-progress marker: `rm -f "/tmp/claude-audit-in-progress-${CWD_HASH}"`.

## Phase 5: Learning

Skipped when `CLAUDE_EFFORT=low`. Otherwise read `references/learning-phase.md`: dispatch the learning agent (`run_in_background: false`), parse its output, write learning-log/trends/suppressions.

## Phase 6: PR (after push)

`references/pr-creation.md`. Errors don't block.

## Last line of every run

```
Audit: {C} Critical, {I} Important offen | Push {frei|blockiert|nicht zutreffend}
```
