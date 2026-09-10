---
name: audit
description: "Pre-push code audit. Runs a per-dimension Workflow pipeline (13 dimensions: architecture, security, performance, code quality, SEO, a11y, typography, UI, UX, animation, docs sync, copy, privacy; plus a conditional 14th, payments, on repos with a Stripe integration), plus deterministic secret/lockfile/i18n/CI-hardening pre-checks, one fix wave with peer-review verification, then allows git push. Two start questions (dimensions, fix scope) replace the old argument form. Use when the user runs /audit, says 'before pushing' or 'review my changes', or has uncommitted/unpushed changes that should be checked. NOT for whole-codebase audits — use /full-audit instead."
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
SCOPE_OUT="$(bash "$AUDIT_BIN/collect-scope.sh")"
BASE_REF=$(printf '%s\n' "$SCOPE_OUT" | sed -n 's/^BASE_REF=//p')
ALLE_DATEIEN=$(printf '%s\n' "$SCOPE_OUT" | sed -n '/^---FILES---$/,/^---FRONTEND---$/{/^---FILES---$/d;/^---FRONTEND---$/d;p;}')
echo "BASE_REF=$BASE_REF"
echo "ALLE_DATEIEN: $(printf '%s\n' "$ALLE_DATEIEN" | grep -c .) file(s)"
FW_OUT="$(bash "$AUDIT_BIN/detect-framework.sh")"
FRAMEWORK=$(printf '%s\n' "$FW_OUT" | sed -n 's/^FRAMEWORK=//p')
SOURCE_DIRS=$(printf '%s\n' "$FW_OUT" | sed -n 's/^SOURCE_DIRS=//p')
PLATFORM=$(printf '%s\n' "$FW_OUT" | sed -n 's/^PLATFORM=//p')
bash "$AUDIT_BIN/pre-checks.sh"
bash "$AUDIT_BIN/check-ci-hardening.sh" "$(git rev-parse --show-toplevel)"   # HITS become Important security findings, no specialist needed
STRIPE_OUT="$(bash "$AUDIT_BIN/detect-stripe.sh" "$(git rev-parse --show-toplevel)")"
STRIPE=$(printf '%s\n' "$STRIPE_OUT" | sed -n 's/^STRIPE=//p')
STRIPE_MODE=$(printf '%s\n' "$STRIPE_OUT" | sed -n 's/^STRIPE_MODE=//p')
STRIPE_RECURRING=$(printf '%s\n' "$STRIPE_OUT" | sed -n 's/^STRIPE_RECURRING=//p')
STRIPE_FILES=$(printf '%s\n' "$STRIPE_OUT" | sed -n '/^STRIPE_FILES<<END$/,/^END$/{/^STRIPE_FILES<<END$/d;/^END$/d;p;}')
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

- **(a) Dimensions:** All (default) | Backend | Frontend | Custom (multi-select over all 13, plus payments when the repo has a Stripe integration).
- **(b) Fix scope:** find & log only | fix Critical | fix Critical and Important. Preselection from `${CLAUDE_EFFORT:-medium}`: `low` → find only, `medium` → Critical, `high`/`xhigh` → Critical and Important.

Result: `AUDIT_DIMENSIONS` (comma list) and `AUDIT_FIX_SCOPE` (`none|critical|all`). A partial selection at (a) never writes the push marker (same rule as before), and the log names the dimensions not checked.

**`payments` (CONDITIONAL 14th dimension):** joins `SELECTED_DIMENSIONS` only when BOTH hold:
`STRIPE=yes` (from Phase 1) AND the changed-file set intersects `STRIPE_FILES`. The intersection is
computed against `STRIPE_FILES`, the precomputed Stripe surface `detect-stripe.sh` already found,
never by grepping the diff text for "stripe": half of a payments checklist is about an *absent*
guard (a webhook route with no signature check, a client secret logged instead of masked), and an
absence never shows up as a line in a diff — a diff-text grep would silently miss exactly the class
of defect this dimension exists to catch.

```bash
if [ "${STRIPE:-no}" = "yes" ]; then
  STRIPE_TOUCHED=$(comm -12 <(printf '%s\n' "$ALLE_DATEIEN" | sort -u) <(printf '%s\n' "$STRIPE_FILES" | sort -u))
  if [ -n "$STRIPE_TOUCHED" ]; then
    SELECTED_DIMENSIONS="$SELECTED_DIMENSIONS,payments"
    if ! printf '%s\n' "$GUIDELINE_MATCHES" | grep -q '^payments\.md'; then
      GUIDELINE_MATCHES=$(printf '%s\npayments.md\tmandatory\tscoped' "$GUIDELINE_MATCHES")
    fi
  else
    echo "payments: skipped, diff did not touch the payment surface"
  fi
fi
```

`guidelines/payments.md` carries an `applies_to` path regex, so a diff that only touches a generic
file in the payment surface (`bootstrap/app.php`, a middleware file) may not match it and
`match-guidelines.sh` would then omit the guideline from `GUIDELINE_MATCHES`, even though the
dimension only runs once the detector has already established the repo is a Stripe integration, so
the guideline always applies when `payments` runs. The block above appends the line only when
`match-guidelines.sh` did not already emit it.

When `payments` runs, its scope is the FULL `STRIPE_FILES` surface (not just `STRIPE_TOUCHED`): pass
it as `dimensionFiles: { payments: STRIPE_FILES }` for that dimension when invoking `find.js` in
Phase 2, and thread `STRIPE_MODE` and `STRIPE_RECURRING` through `dimensionContext: { payments:
"STRIPE_MODE=" + STRIPE_MODE + " STRIPE_RECURRING=" + STRIPE_RECURRING }` so the specialist applies
mode-dependent rules (cashier/sdk/client/hosted/http) and gates the dashboard checklist on whether
the integration does recurring billing at all.

## Phase 2: Find

```bash
GIT_COMMON_DIR="$(git rev-parse --path-format=absolute --git-common-dir)"
case "$GIT_COMMON_DIR" in
  */.git) PROJECT_ROOT="${GIT_COMMON_DIR%/.git}" ;;
  *) PROJECT_ROOT="$(git rev-parse --show-toplevel)" ;;
esac
AUDIT_DIR="$PROJECT_ROOT/.claude/audits"; mkdir -p "$AUDIT_DIR"
# The filename is a contract, not a preference: audit/evals/run-evals.sh matches
# `YYYY-MM-DD_HHMMSS-<branch>.md` to find the log it scores, and a name outside that
# shape makes the fixture UNMEASURED rather than a miss. `git branch --show-current`
# is EMPTY on a detached HEAD, which would produce a trailing `-.md` and fail the
# match, so fall back to the short SHA. Do not rename this file by hand.
AUDIT_BRANCH=$(git branch --show-current | tr '/' '-')
[ -n "$AUDIT_BRANCH" ] || AUDIT_BRANCH="detached-$(git rev-parse --short HEAD 2>/dev/null || echo unknown)"
LOGFILE="$AUDIT_DIR/$(date +%Y-%m-%d_%H%M%S)-${AUDIT_BRANCH}.md"
```

The orchestrator does not read scope files at all — `find.js` has no filesystem access and the scout
and specialist subagents read the audited repo themselves, so there is nothing content-based left for
the orchestrator to inline. Before dispatch, compute the content-based scout floor with the helper
instead of reading files: `FLOOR_FILES=$(printf '%s\n' "$ALLE_DATEIEN" | node "$AUDIT_BIN/compute-floor.mjs" "$PROJECT_ROOT" "$AUDIT_DIMENSIONS")`, which prints `{"<dimension>": ["<path>", ...], ...}`
on stdout for every dimension in `AUDIT_DIMENSIONS`. `STRIPE_FILES` is deliberately NOT unioned into
`ALLE_DATEIEN`: it is not part of the diff scope, and unioning it in would widen what every other
dimension audits. It IS passed to the helper, in a second invocation, because the helper reads files
from disk itself, so handing it the surface costs the orchestrator nothing, and `payments` should get
a deterministic floor over the surface it actually scouts, not just whatever of that surface the diff
happened to touch:

```bash
if [ "${AUDIT_DIMENSIONS#*payments}" != "$AUDIT_DIMENSIONS" ]; then
  if command -v jq >/dev/null 2>&1; then
    PAYMENTS_FLOOR=$(printf '%s\n' "$STRIPE_FILES" | node "$AUDIT_BIN/compute-floor.mjs" "$PROJECT_ROOT" "payments")
    FLOOR_FILES=$(jq -s '.[0] * .[1]' <(printf '%s' "$FLOOR_FILES") <(printf '%s' "$PAYMENTS_FLOOR"))
  else
    echo "payments floor: skipped (jq unavailable), payments floor computed over diff scope only"
  fi
fi
```

This matters because two real sessions hit the old inline-content approach's cost directly: one
repo's scope was 132 KB, another session refused to inline 104 KB and bypassed the whole pipeline,
and a follow-up session routed every dimension through `dimensionFiles` to dodge it, which starved
every content floor and left five of fourteen dimensions skipped or incomplete.

Start the find workflow: `Workflow({ scriptPath: "${CLAUDE_SKILL_DIR}/workflows/find.js", args: { repoRoot: PROJECT_ROOT, scope: "diff", files: ALLE_DATEIEN, dimensions: AUDIT_DIMENSIONS, effort: CLAUDE_EFFORT, promptDir: AUDIT_AGENTS_DIR, guidelinesDir: "${CLAUDE_SKILL_DIR}/guidelines", guidelines: GUIDELINE_MATCHES, floorFiles: FLOOR_FILES, dimensionFiles: PAYMENTS_SELECTED ? { payments: STRIPE_FILES } : {}, dimensionContext: PAYMENTS_SELECTED ? { payments: "STRIPE_MODE=" + STRIPE_MODE + " STRIPE_RECURRING=" + STRIPE_RECURRING } : {} } })`,
where `PAYMENTS_SELECTED` is whether `payments` is in `AUDIT_DIMENSIONS`. One call, one `runId`,
`payments` scouts `STRIPE_FILES` while every other dimension scouts `ALLE_DATEIEN` as before.

**Immediately after the tool returns a `runId`** (before waiting for the completion Notification), write the log stub to `LOGFILE` with the Write tool: `## Scope` (base HEAD, changed files, dimensions), `runId`, empty `## Findings`/`## Fixes` sections. This makes the run resumable across a session limit: `Workflow({ scriptPath, resumeFromRunId: runId })` replays completed agents from cache.

Touch the in-progress marker again (`touch "/tmp/claude-audit-in-progress-${CWD_HASH}"`, staleness 45 min) once the Notification arrives, then read the returned JSON: `{dimensions: {[dim]: {status, files, chunks, findings, verdicts, uncovered}}, skipped, degradedDimensions}`.

**Decide per finding** (`CONFIRMED` verdicts only; `REFUTED` discarded with reason, `UNCERTAIN` never fixed, listed under `### Unverified`): fix / log / discard, following `AUDIT_FIX_SCOPE` — `none` logs everything, `critical` fixes only `severity: Critical`, `all` fixes `Critical` and `Important`. **Minor is never fixed, always logged.** Two findings that contradict each other: decide which one loses, mark it `discard: conflict with {id}` in the log. A dimension with `status: incomplete` gets its own `## Not completed` log section, naming the last reached stage; the other dimensions still ran to completion.

## Phase 3: Fix

Measure the test-suite baseline once: `bash "$AUDIT_BIN/test-lock.sh" {TEST_COMMAND}` → `BASELINE_FAILURES`.

Start the fix workflow: `Workflow({ scriptPath: "${CLAUDE_SKILL_DIR}/workflows/fix.js", args: { repoRoot: PROJECT_ROOT, fixes: [...findings selected to fix, grouped by file...], testCommand: TEST_COMMAND, baselineFailures: BASELINE_FAILURES, budget: 25, auditBin: AUDIT_BIN } })`. Record this second `runId` in the log stub too.

Touch the in-progress marker again after the Notification. Read `{fixes, verdicts, regressions, rejected, blockingRegressions}`. A `REJECT` fix-verdict or a rejected fix stays an open point — `fix.js` runs no second round in the same pass.

Run the full suite exactly once via `test-lock.sh` after the fix wave (fix-verifiers only ran filtered tests). A `blockingRegressions` entry (Critical/Important from the regression pass) becomes an open point and blocks the marker below.

## Phase 4: Log, marker, run-ledger

Finalize `LOGFILE` from `references/audit-log-template.md`: Result, Findings per dimension, Fixes, Discarded (with reason), Unverified, Not completed, Open Points. Include the mechanical checks from Phase 1 and a chat display of the finished log (markdown block).

Every finding line, in every section listed above, MUST be exactly `- [Severity][Dimension]
file:line: description` on one physical line, e.g. `- [Critical][payments] app/Jobs/Charge.php:27:
PaymentIntent::create has no idempotency_key, a queue retry double-charges the customer.` Do not
wrap the file:line or description onto a continuation line, and do not substitute a numbered list,
a bold-bullet header, or a table. `audit/evals/run-evals.sh`'s `normalize_findings()` parses exactly
this shape to score recall; any other shape makes every finding on it unparseable, which reads as a
capability regression (recall collapsed to zero) rather than what it actually is, a formatting slip.

```bash
AUDIT_BIN="${CLAUDE_SKILL_DIR}/bin"
# A Claude Code session has no env var pointing at its own transcript dir:
# derive the projects dir from cwd using the same slug convention as
# ~/.claude/projects/ (every "/" becomes "-").
CLAUDE_PROJECTS_DIR="$HOME/.claude/projects/$(pwd | sed 's#/#-#g')"
bash "$AUDIT_BIN/run-cost.sh" --latest "$CLAUDE_PROJECTS_DIR" --json 2>/dev/null   # cost line for the log header + run-ledger
COUNTS="critical={N_CRITICAL},important={N_IMPORTANT},minor={N_MINOR},usd={USD}"
if [ "${SELECTED_DIMENSIONS#*payments}" != "$SELECTED_DIMENSIONS" ]; then
  COUNTS="$COUNTS,payments_head=$(git rev-parse HEAD)"
fi
bash "$AUDIT_BIN/run-log.sh" --skill audit --outcome "{gate}" \
  --counts "$COUNTS" --gate "{blocked|partial|passed}"
```

**Marker** (`/tmp/claude-audit-passed-{md5 cwd}`, never in the same Bash call as `git push`): set only when ALL of these hold, all derived from the Phase 2 `find.js` result:

- no Critical is open,
- no new test failure beyond `BASELINE_FAILURES`,
- every selected dimension has `status: complete` (none `skipped`, none `incomplete`),
- `degradedDimensions` is empty.

Coverage gates the marker because a run where dimensions did not finish is not a pre-push gate: a
real run selected all 14 dimensions and set the marker while 5 of them were `skipped` or
`incomplete`, which is exactly what this rule exists to stop. A partial dimension selection (Phase
1.5) never sets it either — print the reason instead. When any condition fails, do not set the
marker and print which dimensions were incomplete, skipped, or degraded.

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
