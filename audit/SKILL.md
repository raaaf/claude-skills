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
          command: bash -c 'for c in "$HOME/.claude/skills/audit"; do [ -f "$c/hooks/pretooluse-bash.sh" ] && exec bash "$c/hooks/pretooluse-bash.sh"; done; exit 0'
---

# Audit: per-dimension pipeline

**Start directly with Phase 0.** This is a pre-push gate the user is waiting on.

## Phase 0: Pre-flight checks

Learning backlog question + open `audit-finding` issues/PR dedup context:
`references/pre-flight-checks.md`. Skip entirely when `AUDIT_SKIP_LEARNING_CHECK=1`.

## Phase 1: Scope & pre-checks

```bash
# Shared prologue: audit root, helpers, marker, run log (audit/bin/lib-orchestrator.sh).
# Finding the lib is the one loop that stays inline; here it is this skill's own bin/.
for c in "${CLAUDE_SKILL_DIR}/bin/lib-orchestrator.sh" "$HOME/.claude/skills/audit/bin/lib-orchestrator.sh"; do
  [ -f "$c" ] && { . "$c"; break; }
done
type orch_resolve_audit_root >/dev/null 2>&1 || { echo "Abgebrochen — lib-orchestrator.sh nicht gefunden (audit/bin/ fehlt oder ist nicht verlinkt; sync-skills.sh ausführen)."; exit 1; }
orch_resolve_audit_root || { echo "Abgebrochen — audit-Root nicht gefunden."; exit 1; }
orch_run_log --start --skill audit
orch_verify_agents || { echo "Abgebrochen — fehlende Agent-Dateien."; exit 1; }
SCOPE_OUT="$(bash "$AUDIT_BIN/collect-scope.sh")"
BASE_REF=$(printf '%s\n' "$SCOPE_OUT" | sed -n 's/^BASE_REF=//p')
ALLE_DATEIEN=$(printf '%s\n' "$SCOPE_OUT" | sed -n '/^---FILES---$/,/^---FRONTEND---$/{/^---FILES---$/d;/^---FRONTEND---$/d;p;}')
echo "BASE_REF=$BASE_REF"
echo "ALLE_DATEIEN: $(printf '%s\n' "$ALLE_DATEIEN" | grep -c .) file(s)"
FW_OUT="$(bash "$AUDIT_BIN/detect-framework.sh")"
FRAMEWORK=$(printf '%s\n' "$FW_OUT" | sed -n 's/^FRAMEWORK=//p')
SOURCE_DIRS=$(printf '%s\n' "$FW_OUT" | sed -n 's/^SOURCE_DIRS=//p')
PLATFORM=$(printf '%s\n' "$FW_OUT" | sed -n 's/^PLATFORM=//p')
PRECHECK_OUT="$(bash "$AUDIT_BIN/pre-checks.sh")"; printf '%s\n' "$PRECHECK_OUT"   # SECRET_SCAN_RESULT=FINDINGS: every `SECRET file:line: type` line is a [Critical][security] finding in the log and blocks the marker (Phase 4); LOCKFILE_DRIFT_RESULT=FINDINGS: [Important][security]
bash "$AUDIT_BIN/check-ci-hardening.sh" "$(git rev-parse --show-toplevel)"   # HITS become Important security findings, no specialist needed
orch_parse_stripe "$(git rev-parse --show-toplevel)"   # sets STRIPE, STRIPE_MODE, STRIPE_RECURRING, STRIPE_FILES
if echo "$ALLE_DATEIEN" | grep -qE '(package(-lock)?\.json|composer\.(json|lock)|yarn\.lock|pnpm-lock\.yaml|requirements\.txt|pyproject\.toml|Podfile(\.lock)?|Package\.(swift|resolved)|pubspec\.(yaml|lock)|build\.gradle)'; then
  bash "$AUDIT_BIN/check-outdated.sh" "$(git rev-parse --show-toplevel)"
fi
bash "$AUDIT_BIN/check-i18n-keys.sh"; bash "$AUDIT_BIN/check-duplicate-array-keys.sh"
bash "$AUDIT_BIN/check-number-format-locale.sh"; bash "$AUDIT_BIN/check-swift-deprecations.sh"
bash "$AUDIT_BIN/check-token-contrast.sh"; bash "$AUDIT_BIN/check-test-count-drift.sh"
bash "$AUDIT_BIN/check-silencing.sh"   # HITS: a check silenced instead of satisfied. Re-run after the fix wave (Phase 3c), fix agents are the likeliest source
bash "$AUDIT_BIN/check-docs-path-drift.sh" "$BASE_REF"; bash "$AUDIT_BIN/check-docs-claims.sh"
bash "$AUDIT_BIN/check-workflow-dupes.sh"   # HITS: find.js/fix.js shared helpers drifted; Important code_quality, no specialist needed
bash "$AUDIT_BIN/check-fresh-shell.sh"      # HITS: a SKILL.md bash block calls orch_* without sourcing the lib; Critical architecture (the function is undefined there), no specialist needed

PROJECT_GUIDELINES_FILE="$(git rev-parse --show-toplevel)/.claude/audit-guidelines.md"
PROJECT_GUIDELINES=""
[ -f "$PROJECT_GUIDELINES_FILE" ] && PROJECT_GUIDELINES=$(cat "$PROJECT_GUIDELINES_FILE")
bash "$AUDIT_BIN/diff-size-gate.sh"
eval "$(bash "$AUDIT_BIN/perf-measure.sh" --detect)"
GUIDELINE_MATCHES=$(bash "$AUDIT_BIN/match-guidelines.sh" "${CLAUDE_SKILL_DIR}/guidelines" 2>/dev/null)

# In-progress marker: run-scoped (claim now, touch after find.js, touch after fix.js, release at Phase 4).
orch_progress_claim   # progress-family hash (pwd WITH newline); touched after each Notification, released in Phase 4
orch_state_save ALLE_DATEIEN BASE_REF FRAMEWORK SOURCE_DIRS PLATFORM PRECHECK_OUT STRIPE STRIPE_MODE STRIPE_RECURRING STRIPE_FILES PROJECT_GUIDELINES GUIDELINE_MATCHES   # later blocks read these back with orch_state_load (fresh shell per block, lib header); after the claim, which clears the state
```

Deterministic-check result table and derivation of `ALLE_DATEIEN`/`FRONTEND_DATEIEN`/`SUPPRESSIONS`/`PROJECT_CONTEXT`/`DECIDED_TRADEOFFS`: `references/scope-and-pre-checks.md`. Prose gate (`DIFF_CLASS=prose`, from `bin/classify-diff.sh`) limits the dimension preselection to `docs_sync`+`copy` and the fix-scope preselection to "find only": `references/prose-gate.md`.

**WIP/stale-snapshot scope check:** does the working tree contain files that clearly do NOT belong to the current task? Ask via `AskUserQuestion`: only the session/task changes vs. the entire working tree.

## Phase 1.5: Start questions (dimensions + fix scope)

**A set variable suppresses both questions.** If `AUDIT_DIMENSIONS` or `AUDIT_FIX_SCOPE` is set (CI/eval-harness/headless), skip `AskUserQuestion` entirely: the set variable takes its value, the other takes its default (all dimensions; fix-scope preselection from `CLAUDE_EFFORT` below). This guarantees a headless run never hangs on a question.

Otherwise ask exactly one `AskUserQuestion` round, two questions, presets from `references/dimension-selection.md`:

- **(a) Dimensions:** Everything (default) | Backend only | Frontend only | Custom (multi-select over all 13, plus payments when the repo has a Stripe integration).
- **(b) Fix scope:** find & log only | fix Critical | fix Critical and Important. Preselection from `${CLAUDE_EFFORT:-medium}`: `low` → find only, `medium` → Critical, `high`/`xhigh` → Critical and Important.

Result: `AUDIT_DIMENSIONS` (comma list) and `AUDIT_FIX_SCOPE` (`none|critical|all`). A partial selection at (a) never writes the push marker (same rule as before), and the log names the dimensions not checked.

**`payments` (CONDITIONAL 14th dimension):** joins `AUDIT_DIMENSIONS` only when BOTH hold:
`STRIPE=yes` (from Phase 1) AND the changed-file set intersects `STRIPE_FILES`. The intersection is
computed against `STRIPE_FILES`, the precomputed Stripe surface `detect-stripe.sh` already found,
never by grepping the diff text for "stripe": half of a payments checklist is about an *absent*
guard (a webhook route with no signature check, a client secret logged instead of masked), and an
absence never shows up as a line in a diff — a diff-text grep would silently miss exactly the class
of defect this dimension exists to catch.

```bash
for c in "${CLAUDE_SKILL_DIR}/bin/lib-orchestrator.sh" "$HOME/.claude/skills/audit/bin/lib-orchestrator.sh"; do [ -f "$c" ] && { . "$c"; break; }; done   # fresh shell per block: source the lib again
orch_state_load   # ALLE_DATEIEN, STRIPE, STRIPE_FILES, GUIDELINE_MATCHES from Phase 1
AUDIT_DIMENSIONS="${AUDIT_DIMENSIONS:-{comma list from question (a); all 13 ids when the answer was All}}"   # a set env var (headless) wins, else the answer, substituted here: the question's result exists nowhere in this shell
[ "$AUDIT_DIMENSIONS" = all ] && AUDIT_DIMENSIONS="architecture,security,performance,code_quality,seo,a11y,typography,ui_design,ux,animation,docs_sync,copy,privacy"   # the headless spelling; find.js accepts dimension ids only
AUDIT_FIX_SCOPE="${AUDIT_FIX_SCOPE:-{none|critical|all from question (b)}}"
if [ "${STRIPE:-no}" = "yes" ]; then
  STRIPE_TOUCHED=$(comm -12 <(printf '%s\n' "$ALLE_DATEIEN" | sort -u) <(printf '%s\n' "$STRIPE_FILES" | sort -u))
  if [ -n "$STRIPE_TOUCHED" ]; then
    AUDIT_DIMENSIONS="${AUDIT_DIMENSIONS:+$AUDIT_DIMENSIONS,}payments"   # no leading comma on an empty selection; the SAME variable Phase 2 splits for find.js; a separate SELECTED_DIMENSIONS was appended here until 2026-09-16 and never reached the dispatch
    GUIDELINE_MATCHES=$(orch_payments_guidelines "$GUIDELINE_MATCHES")   # payments.md always applies once the dimension runs (lib)
  else
    echo "payments: skipped, diff did not touch the payment surface"
  fi
fi
echo "AUDIT_DIMENSIONS=$AUDIT_DIMENSIONS AUDIT_FIX_SCOPE=$AUDIT_FIX_SCOPE"
orch_state_save AUDIT_DIMENSIONS AUDIT_FIX_SCOPE GUIDELINE_MATCHES   # Phase 2 and Phase 4 load these; a hand-substituted copy in Phase 4 was the previous mechanism
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
for c in "${CLAUDE_SKILL_DIR}/bin/lib-orchestrator.sh" "$HOME/.claude/skills/audit/bin/lib-orchestrator.sh"; do [ -f "$c" ] && { . "$c"; break; }; done   # fresh shell per block: source the lib again
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
orch_state_save PROJECT_ROOT AUDIT_DIR LOGFILE
```

The orchestrator does not read scope files at all — `find.js` has no filesystem access and the scout
and specialist subagents read the audited repo themselves, so there is nothing content-based left for
the orchestrator to inline. Before dispatch, the block below computes the content-based scout floor
with the helper and prints it. `STRIPE_FILES` is deliberately NOT unioned into `ALLE_DATEIEN`: it is
not part of the diff scope, and unioning it in would widen what every other dimension audits. It IS
passed to the helper, in a second invocation, because the helper reads files from disk itself, so
handing it the surface costs the orchestrator nothing, and `payments` should get a deterministic
floor over the surface it actually scouts, not just whatever of that surface the diff happened to
touch:

```bash
for c in "${CLAUDE_SKILL_DIR}/bin/lib-orchestrator.sh" "$HOME/.claude/skills/audit/bin/lib-orchestrator.sh"; do [ -f "$c" ] && { . "$c"; break; }; done   # fresh shell per block: source the lib again
orch_resolve_audit_root || { echo "Abgebrochen — audit-Root nicht gefunden."; orch_progress_release; exit 1; }
orch_state_load   # ALLE_DATEIEN, AUDIT_DIMENSIONS, STRIPE_FILES, PROJECT_ROOT from the blocks above
FLOOR_FILES=$(printf '%s\n' "$ALLE_DATEIEN" | node "$AUDIT_BIN/compute-floor.mjs" "$PROJECT_ROOT" "$AUDIT_DIMENSIONS")   # content-based scout floor, {"<dimension>": ["<path>", ...]} for every selected dimension
FLOOR_FILES=$(orch_payments_floor "$AUDIT_DIMENSIONS" "$STRIPE_FILES" "$PROJECT_ROOT" "$FLOOR_FILES")   # merges the payments floor over STRIPE_FILES; unchanged when payments is not selected (lib)
printf 'FLOOR_FILES=%s\n' "$FLOOR_FILES"   # pass this JSON as floorFiles in the Workflow call below

# Optional Jev routing. The global default is `assist`; set `AUDIT_JEV_MODE=off`
# to disable Jev. `shadow` only records a comparison;
# `assist` may provide bounded priority hints to file scouts. `prune` is
# explicit and requires bounded code context; find.js independently limits it
# to complete-context, non-floor, low-risk file-scout pairs.
AUDIT_JEV_MODE="${AUDIT_JEV_MODE:-assist}"
AUDIT_JEV_CONTEXT_MODE="${AUDIT_JEV_CONTEXT_MODE:-paths}"   # code upload is opt-in; paths remains the default
JEV_DIMENSION_FILES='{}'
if [ "${AUDIT_DIMENSIONS#*payments}" != "$AUDIT_DIMENSIONS" ]; then
  JEV_DIMENSION_FILES=$(printf '%s\n' "$STRIPE_FILES" | node -e 'const fs=require("fs"); console.log(JSON.stringify({payments:fs.readFileSync(0,"utf8").split("\n").filter(Boolean)}))')
fi
JEV_ROUTER=$(printf '%s\n' "$ALLE_DATEIEN" | node "$AUDIT_BIN/compute-jev-routes.mjs" "$PROJECT_ROOT" "$AUDIT_JEV_MODE" "$AUDIT_DIMENSIONS" "$JEV_DIMENSION_FILES" diff "$AUDIT_JEV_CONTEXT_MODE")
printf 'JEV_ROUTER=%s\n' "$JEV_ROUTER"   # pass this JSON unchanged as jevRouter below
```

This matters because two real sessions hit the old inline-content approach's cost directly: one
repo's scope was 132 KB, another session refused to inline 104 KB and bypassed the whole pipeline,
and a follow-up session routed every dimension through `dimensionFiles` to dodge it, which starved
every content floor and left five of fourteen dimensions skipped or incomplete.

`files` and `dimensions` are JSON ARRAYS, not the newline/comma strings the shell variables hold:
the `args.dimensions` guard at the top of `find.js`'s `args` block (search for the message, line
numbers in that file move) validates `dimensions` with `Array.isArray` and throws `args.dimensions
must be an array of supported dimension ids` before dispatching anything, and `files` is used as an array
throughout (`files.slice`, `files.filter`). Split `ALLE_DATEIEN` on newlines and `AUDIT_DIMENSIONS`
on commas when building the call. A real run on 2026-09-15 failed here in 14ms because this line
read as if the shell values could be passed through unchanged.

Before making the call, estimate its total size: `printf '%s' "$ALLE_DATEIEN" | wc -c` plus the
byte length of `FLOOR_FILES` and `JEV_ROUTER`. At roughly 40 KB and above, do not pass these args
to `Workflow` inline; a real run hit 57 KB there and the call failed. Instead copy `find.js` into
the scratchpad, embed the resolved args object as a constant near the top of the copy (`const
ARGS2 = {...}`), replace every place the script reads `args` with `ARGS2`, and pass that copy's
path as `scriptPath`. See `.claude/audits/2026-09-21_040559-main.md` (Incidents) for the origin of
this workaround.

Start the find workflow: `Workflow({ scriptPath: "${CLAUDE_SKILL_DIR}/workflows/find.js", args: { repoRoot: PROJECT_ROOT, scope: "diff", files: [...ALLE_DATEIEN split on newlines...], dimensions: [...AUDIT_DIMENSIONS split on commas...], effort: CLAUDE_EFFORT, promptDir: AUDIT_AGENTS_DIR, guidelinesDir: "${CLAUDE_SKILL_DIR}/guidelines", guidelines: GUIDELINE_MATCHES, projectGuidelines: PROJECT_GUIDELINES, floorFiles: FLOOR_FILES, dimensionFiles: PAYMENTS_SELECTED ? { payments: STRIPE_FILES } : {}, dimensionContext: PAYMENTS_SELECTED ? { payments: "STRIPE_MODE=" + STRIPE_MODE + " STRIPE_RECURRING=" + STRIPE_RECURRING } : {}, jevRouter: JSON.parse(JEV_ROUTER) } })`,
where `PAYMENTS_SELECTED` is whether `payments` is in `AUDIT_DIMENSIONS`. One call, one `runId`,
`payments` scouts `STRIPE_FILES` while every other dimension scouts `ALLE_DATEIEN` as before.

`JEV_ROUTER` is an optional path-and-metadata-only Jev router. Its default mode is `assist`; set
`AUDIT_JEV_MODE=off` to disable it. A
missing key, response failure, invalid result, or scope over 64 complete file-dimension pairs returns
observable fallback metadata and leaves the existing pipeline identical. `shadow` leaves scout
briefings unchanged. `assist` adds only a normalized `JEV_ASSIST_PRIORITY_HINT` to file-scout
briefings; all `SCOPE_FILES` and `FLOOR_FILES` remain eligible and no route is pruned. `prune` is
only effective with `AUDIT_JEV_CONTEXT_MODE=code` and may remove a file only for `seo`, `a11y`,
`typography`, `ui_design`, `ux`, `animation`, or `copy`, when Jev returns `not_relevant`, context is
complete, and no deterministic floor covers that file. `docs_sync` remains cluster-only and is not
pruned. Architecture, security, performance, code quality, privacy, and payments never prune. A
fallback, invalid response, uncertain response, unsafe context, or incomplete context preserves full scope. Read
`references/jev-shadow-router.md` before changing this pilot. Routing agreement is not bug recall.
`AUDIT_JEV_CONTEXT_MODE=code` is an explicit opt-in that sends bounded, safe source context for the
supported routing dimensions. It falls back before the API call for unsafe context. The assist hint is
advisory and is omitted for fallback, incomplete, or invalid Jev results. When `AUDIT_JEV_MODE=prune`,
record `jevRouter.prune.prunedCount`, `preservedCount`, and per-dimension counts alongside the usual
scope and coverage results. When `AUDIT_JEV_MODE` is `shadow`, `assist`, or `prune`, record `jevRouter.status`, fallback `reason`, candidate count, latency,
cache status, usage, and comparison totals from the Workflow result in the audit log. Set the
optional `JEV_ROUTER_CACHE_DIR` only to a private directory when repeated code-context runs should
reuse normalized routes. The cache stores no source content and is disabled by default. Never log
the key or API body.

**Immediately after the tool returns a `runId`** (before waiting for the completion Notification), write the log stub to `LOGFILE` with the Write tool: `## Scope` (base HEAD, changed files, dimensions), `runId`, empty `## Findings`/`## Fixes` sections. This makes the run resumable across a session limit: `Workflow({ scriptPath, resumeFromRunId: runId })` replays completed agents from cache.

Once the Notification arrives, touch the in-progress marker (staleness 45 min):

```bash
for c in "${CLAUDE_SKILL_DIR}/bin/lib-orchestrator.sh" "$HOME/.claude/skills/audit/bin/lib-orchestrator.sh"; do [ -f "$c" ] && { . "$c"; break; }; done   # fresh shell per block: source the lib again
orch_progress_touch
```

Then read the returned JSON: `{dimensions: {[dim]: {status, files, chunks, findings, verdicts, uncovered}}, skipped, degradedDimensions}`.

**Feed the recurrence store NOW, before deciding anything.** Write one normalized pattern per
`CONFIRMED` verdict to a file (Write tool, one per line: short, no file or line, so the same problem
elsewhere in the codebase collapses onto the same key) and hand it to the store:

```bash
for c in "/Users/rafael/.claude/skills/audit/bin/lib-orchestrator.sh" "$HOME/.claude/skills/audit/bin/lib-orchestrator.sh"; do [ -f "$c" ] && { . "$c"; break; }; done   # fresh shell per block: source the lib again
orch_resolve_audit_root || { echo "Abgebrochen — audit-Root nicht gefunden."; exit 1; }
orch_patterns_from_file recur {path of the file you just wrote}   # a pattern is finding text and never goes on a command line
```

This step runs after EVERY `find.js` call of the run, including a re-run of single dimensions (a copy/ux re-run on 2026-09-20 produced 5 confirmed findings that reached the store only via the Phase 5 back-fill). It belongs HERE, at the verdicts, and not in the fix wave: `AUDIT_FIX_SCOPE=none` is the common
case, `Minor` is never fixed at any scope, and a fix wave that never runs cannot feed a counter.
Until 2026-09-18 this duty was documented in `references/learning-phase.md` and
`agents/learning-agent.md` as living in `workflows/fix.js` and `agents/fix-agent.md`, and it was in
neither: 192 audit logs on disk had produced 36 store entries, so `patterns.json` had effectively
never been fed by the loop, and every retro reasoned about recurrence from a counter that did not
move. Phase 5 Step 0.5 still checks the count and back-fills, but that is the repair, not the path.

**Decide per finding** (`CONFIRMED` verdicts only; `REFUTED` discarded with reason, `UNCERTAIN` never fixed, listed under `### Unverified`): fix / log / discard, following `AUDIT_FIX_SCOPE` — `none` logs everything, `critical` fixes only `severity: Critical`, `all` fixes `Critical` and `Important`. **Minor is never fixed, always logged.** Two findings that contradict each other: decide which one loses, mark it `discard: conflict with {id}` in the log. A dimension with `status: incomplete` gets its own `## Not completed` log section, naming the last reached stage; the other dimensions still ran to completion.

## Phase 3: Fix

Derive `TEST_COMMAND` first; nothing earlier in this file sets it. `orch_test_command` reads `.claude/ship.md`
`test-command:` with the same parser `/ship` uses (two hand-written parsers disagreed until 2026-09-16), then
falls back to the manifest, then to none:

```bash
for c in "${CLAUDE_SKILL_DIR}/bin/lib-orchestrator.sh" "$HOME/.claude/skills/audit/bin/lib-orchestrator.sh"; do [ -f "$c" ] && { . "$c"; break; }; done   # fresh shell per block
orch_state_load   # PROJECT_ROOT from Phase 2
TEST_COMMAND=$(orch_test_command "$PROJECT_ROOT") || TEST_COMMAND=""   # declared test-command:, else the manifest's own; one parser shared with /ship
echo "TEST_COMMAND=${TEST_COMMAND:-<none>}"
orch_state_save TEST_COMMAND
```

`TEST_COMMAND` empty: skip the baseline, pass `testCommand: ""` to `fix.js` (it tells fixers and
verifiers there is no suite rather than handing them `test-lock.sh undefined`), and the fix wave's
verification rests on the fix-verifier's read alone. This repo is that case.

**An empty `TEST_COMMAND` does not exempt the orchestrator from the lock.** Every test command YOU
run yourself, at any phase, goes through `bash "$AUDIT_BIN/test-lock.sh" <command...>`, including an
`xcodebuild test` you assembled by hand because the repo declares no `test-command:`. The lock keys
on the repo plus the `-destination` id, so runs against one simulator serialize and runs against
different simulators still go in parallel. Skipping it is how two concurrent `xcodebuild test` runs
land on one booted simulator and kill each other: the loser exits with "Early unexpected exit,
operation never finished bootstrapping ... Test crashed with signal kill", which reads like a
product crash. That cost a session three wasted re-runs and one wrong diagnosis on 2026-09-19, with
the lock sitting unused in this very directory. `test-lock.sh` now prints `TEST_LOCK_COLLISION` when
it sees that signature, so a run that slipped past the lock at least names itself.

Otherwise measure the test-suite baseline once: `bash "$AUDIT_BIN/test-lock.sh" $TEST_COMMAND` → `BASELINE_FAILURES`.

Start the fix workflow: `Workflow({ scriptPath: "${CLAUDE_SKILL_DIR}/workflows/fix.js", args: { repoRoot: PROJECT_ROOT, fixes: [...findings selected to fix, grouped by file...], testCommand: TEST_COMMAND, baselineFailures: BASELINE_FAILURES, budget: 25, auditBin: AUDIT_BIN } })`. Record this second `runId` in the log stub too.

Every `fixes[]` entry names exactly ONE file. When a fix needs its own test file too, send the test as a second entry (or a second `fix.js` call), never as a hint inside the first: `fix.js`'s ownership check (`hasOwnedChange`) treats a fixer that touched two files as not-owned, skips the fix-verifier and returns `incomplete` for a fix that was fine (2026-09-20, the orchestrator had to verify by hand).

Hold back any finding that rewrites an intent doc (`DESIGN.md`, `PRODUCT.md`, or any doc whose job is to state current product/architecture status) out of this round: send it through its own later `fix.js` call after the rest of the fix wave above has landed and been verified, not in the same batch. Rewriting the doc in parallel with the code it describes leaves it stale before the round even finishes (2nd confirmed occurrence, 2026-09-17).

Touch the in-progress marker again after the Notification:

```bash
for c in "${CLAUDE_SKILL_DIR}/bin/lib-orchestrator.sh" "$HOME/.claude/skills/audit/bin/lib-orchestrator.sh"; do [ -f "$c" ] && { . "$c"; break; }; done   # fresh shell per block: source the lib again
orch_progress_touch
```

Read `{fixes, verdicts, regressions, rejected, blockingRegressions}`. A `REJECT` fix-verdict or a rejected fix stays an open point — `fix.js` runs no second round in the same pass.

Run the full suite exactly once via `test-lock.sh` after the fix wave (fix-verifiers only ran filtered tests). A `blockingRegressions` entry (Critical/Important from the regression pass) becomes an open point and blocks the marker below.

Re-run `pre-checks.sh`, `check-silencing.sh` and `check-test-count-drift.sh` now (each as `bash "$AUDIT_BIN/<script>"` in a sourced block after `orch_resolve_audit_root`), against the diff the fix wave just produced. A green suite is exactly what a silenced check looks like: a fix agent that added `@ts-ignore`, skipped a failing test or lowered a threshold makes the tests pass without the finding being fixed, and no other stage in the pipeline looks for that. A `SILENCING_HIT` on a line a fix agent wrote is an open point and blocks the marker; a hit that was already in the diff before the fix wave is an ordinary Phase 1 finding. A `SECRET` line from this second `pre-checks.sh` run blocks the marker exactly like a Phase 1 one: a fix agent can paste a credential as easily as a human, and the marker binds to the post-fix tree, so the scan must cover it (run 13, 2026-09-16).

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
for c in "${CLAUDE_SKILL_DIR}/bin/lib-orchestrator.sh" "$HOME/.claude/skills/audit/bin/lib-orchestrator.sh"; do [ -f "$c" ] && { . "$c"; break; }; done   # fresh shell per block: source the lib again
orch_resolve_audit_root || { echo "Abgebrochen — audit-Root nicht gefunden."; orch_progress_release; exit 1; }   # sets AUDIT_BIN with the same fallbacks as Phase 1
orch_state_load   # AUDIT_DIMENSIONS as Phase 1.5 saved it, payments included when it was appended
# A Claude Code session has no env var pointing at its own transcript dir:
# derive the projects dir from cwd using the same slug convention as
# ~/.claude/projects/ (every "/" becomes "-").
CLAUDE_PROJECTS_DIR="$HOME/.claude/projects/$(pwd | sed 's#/#-#g')"
bash "$AUDIT_BIN/run-cost.sh" --latest "$CLAUDE_PROJECTS_DIR" --json 2>/dev/null   # cost line for the log header + run-ledger
COUNTS="critical={N_CRITICAL},important={N_IMPORTANT},minor={N_MINOR},usd={USD}"
if [ "${AUDIT_DIMENSIONS#*payments}" != "$AUDIT_DIMENSIONS" ]; then
  COUNTS="$COUNTS,payments_head=$(git rev-parse HEAD)"
fi
orch_run_log --skill audit --outcome "{gate}" --counts "$COUNTS" --gate "{blocked|partial|passed}"
```

**Marker** (`/tmp/claude-audit-passed-{md5 cwd}`, never in the same Bash call as `git push`): set only when ALL of these hold, all derived from the Phase 2 `find.js` result. The marker records the tree it certified (tracked working-tree content via `git stash create`), not just a time: `/ship`'s gate refuses a marker whose tree is not the one being shipped, so an edit made after the audit inside the 30-minute window no longer ships as audited (run 11, 2026-09-16).

- no Critical is open, including every `SECRET ...` line either `pre-checks.sh` run (Phase 1, and again after the fix wave in Phase 3) printed (a secret in the diff is a Critical by this repo's own rule; until 2026-09-16 the scan ran and nothing read its result),
- no new test failure beyond `BASELINE_FAILURES`,
- no selected dimension has `status: incomplete`. Since 2026-09-16 an `UNCERTAIN` verdict makes a
  dimension `incomplete` only for a Critical or Important finding (decided after runs 5 and 7: a
  Minor is never fixed whatever its verdict, so an unverified Minor changes no action and is only
  listed under `### Unverified`; an unverified Critical/Important is a possible push-blocker nobody
  has ruled on and blocks until re-verified or decided),
- a single dimension with `status: skipped` does NOT block: `find.js`'s `runDimension` (search for `'incomplete' : 'skipped'`; line numbers in that file move) only reaches `skipped` when
  both scouts ran without failing and returned zero files and zero clusters, so it means the
  dimension had nothing in scope. A failed scout puts `scout:files`/`scout:clusters` into
  `uncovered`, which makes the status `incomplete` instead, and that still blocks. Print the skipped
  dimensions and the reason (`no relevant files`) in the log either way. This was corrected on
  2026-09-15: the rule previously demanded `complete` for every dimension, which made the marker
  unreachable on any repo without a frontend, since `ui_design` and `copy` report `skipped` on every
  single run there and no re-run can change that.
- **but MORE THAN HALF the selected dimensions `skipped` DOES block.** One empty dimension is a
  repo without a frontend; most of them empty is a broken run, and the two are indistinguishable
  from the result alone. On 2026-09-17 three runs passed their args by pointer instead of by value,
  so every scout got `REPO_ROOT=undefined` and an empty file list; 13 of 14 dimensions came back
  `skipped`, the run reported `complete`, and the marker was written. 119 agents produced a green
  gate over an unexamined diff. Compute it as `skipped > selected / 2` and name the count in the
  refusal, so the next such run stops at the gate instead of shipping.
- `degradedDimensions` is empty.

Coverage gates the marker because a run where dimensions did not finish is not a pre-push gate: a
real run selected all 14 dimensions and set the marker while 5 of them were `skipped` or
`incomplete`, which is exactly what this rule exists to stop. A partial dimension selection (Phase
1.5) never sets it either — print the reason instead. When any condition fails, do not set the
marker and print which dimensions were incomplete, skipped, or degraded.

The `skipped` half of that original rule was too broad and is no longer part of the gate, see the
condition above. The whole distinction rests on `find.js` keeping `skipped` to mean "both scouts
ran and found nothing": if a future change ever lets a failure produce `skipped` instead of adding
to `uncovered`, this rule has to be revisited in the same commit, because the gate would then pass
on exactly the state it exists to catch.

```bash
for c in "${CLAUDE_SKILL_DIR}/bin/lib-orchestrator.sh" "$HOME/.claude/skills/audit/bin/lib-orchestrator.sh"; do [ -f "$c" ] && { . "$c"; break; }; done   # fresh shell per block: source the lib again
# Counts from the Phase 2 find.js result: how many dimensions were selected, and how many came
# back skipped / incomplete / degraded. They are mandatory, and the helper refuses on its own if
# they do not hold, so the gate no longer depends on this prose being read correctly.
orch_marker_write "$N_SELECTED" "$N_SKIPPED" "$N_INCOMPLETE" "$N_DEGRADED"   # writes the audited tree id (orch_tree_hash) into the passed-family marker, /ship compares it after its own commit
```

Release the in-progress marker, unconditionally (the block above only runs when the gate passed):

```bash
for c in "${CLAUDE_SKILL_DIR}/bin/lib-orchestrator.sh" "$HOME/.claude/skills/audit/bin/lib-orchestrator.sh"; do [ -f "$c" ] && { . "$c"; break; }; done   # fresh shell per block: source the lib again
orch_progress_release
```

## Phase 5: Learning

Skipped when `CLAUDE_EFFORT=low`. Otherwise read `references/learning-phase.md`: dispatch the learning agent (`run_in_background: false`), parse its output, write learning-log/trends/suppressions.

## Phase 6: PR (after push)

`references/pr-creation.md`. Errors don't block.

## Last line of every run

```
Audit: {C} Critical, {I} Important offen | Push {frei|blockiert|nicht zutreffend}
```
