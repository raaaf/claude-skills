---
name: full-audit
disable-model-invocation: true
description: "Comprehensive one-time audit of an entire codebase (not just recent changes). Auto-detects framework (Laravel, Next.js, Nuxt, Django), batches large codebases, runs up to 12 parallel subagents per batch (architecture incl. migrations and observability, security, performance, code quality, SEO, a11y, typography, UI, UX, animation, docs sync, copy), auto-fixes including Minor, runs a cross-reference pass, generates a manual test plan. Use when the user runs /full-audit, starts on a new project, asks for a comprehensive review, or wants the whole codebase checked. NOT for pre-push of recent changes — use /audit instead."
when_to_use: "/full-audit, full codebase audit, audit whole project, starting on a new project, comprehensive review"
argument-hint: "[optional: directory scope]"
model: opus
effort: xhigh
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

**EXECUTE IMMEDIATELY — do not explain, do not announce. Start directly with Phase 0.**

> **Architecture note:** This skill has NO worker agents of its own. It uses the definitions from `../audit/agents/*.md` (referenced in the skill via `{AUDIT_AGENTS}`). If you want to change worker configuration, edit there. prompt-template.md has two sections ("For /audit" and "For /full-audit (codebase-based)") — workers dispatch the matching section depending on the skill.

Anti-patterns (red flags) see `{AUDIT_REFS}/anti-patterns.md` (path from Phase 0) — Full-Audit additionally fixes ALL Minor findings.

---

## Phase 0: Pre-Flight — Audit Paths + Agent Verification

```bash
# Resolve audit skill root — try multiple known locations.
AUDIT_ROOT=""
for candidate in \
  "$(dirname "${CLAUDE_SKILL_DIR:-/nonexistent}")/audit" \
  "${CLAUDE_PROJECT_DIR:+${CLAUDE_PROJECT_DIR%/full-audit}/audit}" \
  "$HOME/.claude/skills/audit" \
  "$HOME/.claude/skills/claude-skills/audit"; do
  [ -n "$candidate" ] && [ -d "$candidate/agents" ] && { AUDIT_ROOT="$candidate"; break; }
done

if [ -z "$AUDIT_ROOT" ]; then
  echo "ERROR: audit skill not found. Install audit alongside full-audit."
  exit 1
fi

AUDIT_AGENTS="$AUDIT_ROOT/agents"
AUDIT_BIN="$AUDIT_ROOT/bin"
AUDIT_REFS="$AUDIT_ROOT/references"

# PreCompact-Schutz: blockiert Auto-Compaction waehrend des Full-Audit-Runs
CWD_HASH=$(pwd | md5 2>/dev/null || pwd | md5sum 2>/dev/null | cut -d' ' -f1)
touch "/tmp/claude-audit-in-progress-${CWD_HASH}"

# Eigene Scripts + persistenter Goal-Loop-State (Format/Resume: references/state-file.md)
FULL_AUDIT_BIN="${CLAUDE_SKILL_DIR:-$HOME/.claude/skills/full-audit}/bin"
STATE_FILE="$(git rev-parse --show-toplevel)/.claude/audits/full-audit-state.md"
BATCH_DIR="$(git rev-parse --show-toplevel)/.claude/audits/full-audit-batches"

bash "$AUDIT_BIN/verify-agents.sh" "$AUDIT_AGENTS" || { echo "Full-Audit abgebrochen — fehlende Agent-Dateien."; exit 1; }
```

**Resume check:** If `$STATE_FILE` already exists → RESUME mode:

```bash
bash "$FULL_AUDIT_BIN/resume-check.sh" "$STATE_FILE"
```

Every `BATCH_DIRTY` line: reset the batch row to `pending` (Rounds `0/{max}`, zero C/I/M, HEAD `-`). `running` rows also reset to `pending` (half-audited batches are re-audited from scratch, never resumed mid-batch). Take over `mode`/`effort`/`dimensions` from the state header, SKIP phases 0.3-1.5, go directly to Phase 2 starting at the first `pending` batch. Detail: `references/state-file.md`.

---

## Phase 0.3: Learning Backlog Check

Identical to `/audit` Phase 0. Check whether unprocessed learning suggestions from earlier audits are still open:

```bash
LOG="$(git rev-parse --show-toplevel)/.claude/audits/learning-log.md"
[ -f "$LOG" ] && grep -c "^- \[ \] " "$LOG" 2>/dev/null || echo 0
```

If `>= 1`: ask the user via `AskUserQuestion` with options:
- **Implement suggestions now** → list the suggestions, user picks which ones, orchestrator dispatches matching changes to `audit/guidelines/*.md` or `audit/agents/*.md` (these are the GLOBAL skill files affecting all projects). **IMPORTANT — edit in the source repo:** `~/.claude/skills/*` can be a sync target (symlink or unpacked `.skill` bundle) whose content gets overwritten. Before the first edit, resolve the source: check `readlink` or find the skill source repo (e.g. `~/Local Sites/claude-skills`) and edit THERE. Edits in the unpacked copy are lost on the next sync. After implementing: change `[ ]` to `[x]` in learning-log.md. Then continue Full-Audit with Phase 0.5.
- **Later, run Full-Audit now** → start Phase 0.5, suggestions stay open.
- **Never ask again for these items** → append a `[skip]` marker to the affected rows, they no longer count.

If `0`: continue without asking.

**Additionally — open audit issues & PRs** (identical to `/audit` Phase 0.2):

```bash
if gh repo view >/dev/null 2>&1 && git remote get-url origin 2>/dev/null | grep -q github.com; then
  OPEN_AUDIT_ISSUES=$(gh issue list --state open --label audit-finding --json number,title --jq '.[] | "#\(.number) \(.title)"' 2>/dev/null || true)
  OPEN_PRS=$(gh pr list --state open --json number,title,headRefName --jq '.[] | "#\(.number) \(.title) [\(.headRefName)]"' 2>/dev/null || true)
fi
```

Open `audit-finding` issues → AskUserQuestion: **Fix now too** (feed in as verified findings in batch 1, after the fix `gh issue close` with a comment) / **Leave open**. `OPEN_PRS` as context: Phase 4 dedup checks against it, PR file overlaps go into the log as a note.

**Skip this phase when:** ENV `AUDIT_SKIP_LEARNING_CHECK=1` OR `FULL_AUDIT_SKIP_LEARNING_CHECK=1` is set (for CI/batch runs).

---

## Phase 0.4: Test Runner Streak Check

Hard check: if a configured test runner is missing across multiple full audits, the gap escalates to a Critical finding (instead of just a gap note). Without a runner, no fix agent can verify regressions.

```bash
ROOT=$(git rev-parse --show-toplevel)
STREAK_FILE="$ROOT/.claude/audits/no-test-runner-streak"
HAS_RUNNER=0
# JS/TS runner in package.json or config files
if [ -f "$ROOT/package.json" ] && grep -Eq '"(vitest|jest|mocha)"|node:test|node --test' "$ROOT/package.json" 2>/dev/null; then HAS_RUNNER=1; fi
# find instead of glob — zsh aborts on non-matching globs
[ -n "$(find "$ROOT" -maxdepth 1 \( -name 'vitest.config.*' -o -name 'jest.config.*' \) 2>/dev/null)" ] && HAS_RUNNER=1
# PHP / Python
{ [ -f "$ROOT/phpunit.xml" ] || [ -f "$ROOT/phpunit.xml.dist" ]; } && HAS_RUNNER=1
[ -f "$ROOT/pytest.ini" ] && HAS_RUNNER=1
grep -q "\[tool.pytest" "$ROOT/pyproject.toml" 2>/dev/null && HAS_RUNNER=1

if [ "$HAS_RUNNER" -eq 1 ]; then
  rm -f "$STREAK_FILE"; TEST_RUNNER_ESCALATE=0
  echo "Test-Runner: vorhanden (Streak zurueckgesetzt)"
else
  STREAK=$(( $(cat "$STREAK_FILE" 2>/dev/null || echo 0) + 1 ))
  echo "$STREAK" > "$STREAK_FILE"
  if [ "$STREAK" -ge 3 ]; then TEST_RUNNER_ESCALATE=1; else TEST_RUNNER_ESCALATE=0; fi
  echo "Test-Runner: FEHLT (Streak=$STREAK, Escalate=$TEST_RUNNER_ESCALATE)"
fi
```

`TEST_RUNNER_ESCALATE=1` → in Phase 3c record the missing test infrastructure as **Critical** in the audit log and as a GitHub issue (Phase 4), not as a gap note. `=0` → gap note as before.

**Skip when:** ENV `FULL_AUDIT_SKIP_TESTRUNNER_CHECK=1`.

---

## Phase 0.45: Build Preflight (compiled languages)

Before the first batch, verify the unchanged HEAD actually builds. A broken build discovered only at the end (Phase 3b linter/tests) means an entire audit run's worth of fixes gets applied on top of code nobody could have compiled in the first place.

```bash
BUILD_PREFLIGHT_RESULT=SKIP
if [ -f "$ROOT/Package.swift" ] || ls "$ROOT"/*.xcodeproj >/dev/null 2>&1 || ls "$ROOT"/*.xcworkspace >/dev/null 2>&1; then
  command -v xcodebuild >/dev/null 2>&1 && BUILD_PREFLIGHT_RESULT=RUN || BUILD_PREFLIGHT_RESULT=NO_TOOLCHAIN
elif [ -f "$ROOT/Cargo.toml" ]; then
  command -v cargo >/dev/null 2>&1 && BUILD_PREFLIGHT_RESULT=RUN || BUILD_PREFLIGHT_RESULT=NO_TOOLCHAIN
elif [ -f "$ROOT/go.mod" ]; then
  command -v go >/dev/null 2>&1 && BUILD_PREFLIGHT_RESULT=RUN || BUILD_PREFLIGHT_RESULT=NO_TOOLCHAIN
elif [ -f "$ROOT/pom.xml" ] || [ -f "$ROOT/build.gradle" ] || [ -f "$ROOT/build.gradle.kts" ]; then
  { command -v gradle >/dev/null 2>&1 || command -v mvn >/dev/null 2>&1; } && BUILD_PREFLIGHT_RESULT=RUN || BUILD_PREFLIGHT_RESULT=NO_TOOLCHAIN
fi
echo "Build preflight: $BUILD_PREFLIGHT_RESULT"
```

`RUN` → run the project's normal build command against the unchanged HEAD (narrowest scope available, e.g. a single scheme/package — not a full clean build), before any fix agent has touched anything. Build fails → log it immediately as a **Critical** finding `[Build]` in batch 1; do not wait for Phase 3b to surface it. Build succeeds → continue silently, no log entry needed.

`SKIP` (no known compiled-language manifest) or `NO_TOOLCHAIN` (manifest present, toolchain missing) → gap note only, same as the Phase 0.4 test-runner gap note, not a finding.

**Skip when:** ENV `FULL_AUDIT_SKIP_BUILD_PREFLIGHT=1`.

---

## Phase 0.5: Dimension Selection

Before scope is collected, clarify which dimensions should be checked. Saves tokens and time when the user e.g. only wants Security checked.

**Skip via ENV (for CI/batch):**

```bash
if [ -n "${FULL_AUDIT_DIMENSIONS:-}" ]; then
  case "$FULL_AUDIT_DIMENSIONS" in
    all|"") SELECTED_DIMENSIONS="architecture,security,performance,code_quality,seo,a11y,typography,ui_design,ux,animation,docs_sync,copy" ;;
    *)      SELECTED_DIMENSIONS="$FULL_AUDIT_DIMENSIONS" ;;
  esac
  echo "Dimensions via ENV: $SELECTED_DIMENSIONS"
fi
```

**Otherwise via AskUserQuestion (1 or 2 questions):**

Question 1 — preset:

| Option | Dimensions |
|---|---|
| Everything (default) | architecture, security, performance, code_quality, seo, a11y, typography, ui_design, ux, animation, docs_sync, copy |
| Backend only | architecture, security, performance, code_quality, docs_sync |
| Frontend only | seo, a11y, typography, ui_design, ux, animation, copy |
| Custom | (triggers question 2) |

Question 2 (only for Custom) — multi-select across all 12 dimensions. User picks any combination.

**Validation:** `SELECTED_DIMENSIONS` must contain at least 1 valid dimension. Discard invalid values.

**Display:** `Full-Audit Scope: {N}/12 dimensions — {list}`.

---

## Phase 0.7: Effort Configuration

Scales depth by `${CLAUDE_EFFORT}`. Default `xhigh` (Full-Audit is thorough by definition, no `medium`).

```bash
CLAUDE_EFFORT="${CLAUDE_EFFORT:-xhigh}"
case "$CLAUDE_EFFORT" in
  low)
    MAX_RUNDEN_PRO_BATCH=1; FIX_MINOR=0; SKIP_LEARNING=1
    SKIP_CROSS_REF=1; CONFIDENCE_FLOOR=high
    ;;
  medium)
    MAX_RUNDEN_PRO_BATCH=2; FIX_MINOR=1; SKIP_LEARNING=0
    SKIP_CROSS_REF=0; CONFIDENCE_FLOOR=medium
    ;;
  high|xhigh|*)
    MAX_RUNDEN_PRO_BATCH=3; FIX_MINOR=1; SKIP_LEARNING=0
    SKIP_CROSS_REF=0; CONFIDENCE_FLOOR=low
    FORCE_CROSS_REF_SINGLE=1   # auch im SINGLE-Modus Cross-Ref durchfuehren
    ;;
esac
echo "Effort=$CLAUDE_EFFORT | Runden=$MAX_RUNDEN_PRO_BATCH | FixMinor=$FIX_MINOR | Cross-Ref=$([ $SKIP_CROSS_REF -eq 1 ] && echo skip || echo run)"
```

| Level | Rounds/Batch | Fix Minor | Cross-Ref | Learning | Confidence Floor |
|---|---|---|---|---|---|
| low | 1 | no | skip | skip | high |
| medium | 2 | yes | BATCHED only | yes | medium |
| high / xhigh (default) | 3 | yes | always (also SINGLE) | yes | low |

From here on, `{MAX_RUNDEN_PRO_BATCH}` refers to the value set here.

---

## Phase 1: Scope & Context

Bash logic (framework detection, ALLE_DATEIEN, frontend list, translation list, PROJECT_CONTEXT, SUPPRESSIONS, intent docs/ADRs) and ARCHITEKTUR-NOTIZ creation in `references/scope-context-batching.md`. Resulting variables: `TOTAL_FILES`, `ALLE_DATEIEN`, `VISUELL_RELEVANTE_DATEIEN`, `TRANSLATION_DATEIEN`, `PROJECT_CONTEXT`, `FRAMEWORK`, `SOURCE_DIRS`, `SUPPRESSIONS`, `DECIDED_TRADEOFFS`, `ARCHITEKTUR-NOTIZ`. `DECIDED_TRADEOFFS` is passed to all workers (prompt-template placeholder).

Optional pre-checks (only with a local diff): run `pre-checks.sh`.

**i18n completeness (deterministic):** `bash "$AUDIT_BIN/check-i18n-keys.sh"` — for `I18N_RESULT=MISSING` every line becomes an Important finding `[i18n]` (Full-Audit checks the entire codebase, so report all gaps).

**Dependency health (deterministic):** `bash "$AUDIT_BIN/check-outdated.sh"` (full mode) —
- `DEP_SECURITY_RESULT=VULNS` → every vulnerable dependency becomes a **Critical** finding `[Security]`
- `DEP_OUTDATED_RESULT=OUTDATED` → collect as **Minor** findings `[Dependencies]` (grouped, not one issue per package); major jumps with breaking-change risk (e.g. `stripe-php 17 → 20`) become an open point instead of an auto-update — dependency updates are NEVER done automatically by the fix agent

**Project-Specific Guidelines:**

```bash
PROJECT_GUIDELINES_FILE="$(git rev-parse --show-toplevel)/.claude/audit-guidelines.md"
PROJECT_GUIDELINES=""
if [ -f "$PROJECT_GUIDELINES_FILE" ]; then
  PROJECT_GUIDELINES=$(cat "$PROJECT_GUIDELINES_FILE")
  echo "Project guidelines: $PROJECT_GUIDELINES_FILE ($(wc -l < "$PROJECT_GUIDELINES_FILE") lines)"
fi
```

Pass `PROJECT_GUIDELINES` through to all workers (see prompt-template).

**Project context (MANDATORY, check `CONTEXT_FALLBACK`):** `references/scope-context-batching.md` sets `CONTEXT_FALLBACK` to `NONE`, `WHOLE_FILE` or `NO_FILE`. Act on it before the first dispatch:

- `WHOLE_FILE` (a `CLAUDE.md` exists but has no `## Audit Context` heading) → pass the whole file as `PROJECT_CONTEXT` **and** instruct every worker and every fix agent to read `CLAUDE.md` in full themselves. Do NOT ask the user; the rules already exist, they just live under other headings.
- `NO_FILE` → ask via `AskUserQuestion` exactly as `/audit` does, marker `.claude/audit-no-context.flag` included.

The failure this prevents: on a project whose headings are `## Sprache` and `## Design`, the literal-heading match returns nothing, `PROJECT_CONTEXT` silently becomes "no project-specific context", and every subagent runs blind to the file's bans. Most `CLAUDE.md` files in the wild do not use the heading.

**Concurrent tree check (baseline):** two things move independently, so pin both:

```bash
AUDIT_BASE_HEAD=$(git rev-parse HEAD)
AUDIT_TREE_HASH=$(git diff HEAD | { md5 2>/dev/null || md5sum | cut -d' ' -f1; })
```

Re-check BOTH after EVERY batch. The hash alone is not enough: if a parallel session commits exactly the dirty tree, `git diff HEAD` goes empty against the *new* HEAD and the hash can match the old baseline while the diff base has moved underneath the audit. `/audit` already pins `AUDIT_BASE_HEAD` for this reason (`../audit/SKILL.md`).

Deviation in either → warning into the audit log (`## Notes: Tree changed during audit`, naming the foreign commits), re-collect scope for the next batch, re-pin both values, discard findings on overwritten lines. Detail: `references/scope-context-batching.md`.

---

## Phase 1.5: Batching Decision

| TOTAL_FILES | Mode |
|---|---|
| ≤ 80 | `SINGLE` |
| > 80 | `BATCHED` |

Batch rules and bash logic in `references/scope-context-batching.md`. Max ~30-40 files per batch, related files together.

**Create state file (MANDATORY, before Phase 2):** additionally copy batch file lists to `$BATCH_DIR/batch-NN.txt` (repo-root-relative — /tmp is ephemeral). Then write `$STATE_FILE`: header (`mode`, `effort`, `dimensions`, `batch-dir`, `post-phases` all pending, `started`) plus one table row per batch with status `pending` (SINGLE mode = exactly one row). Format: `references/state-file.md`.

---

## Phase 2: Audit Loop

**Loop state lives in `$STATE_FILE`, not in context.** Only `BEREITS_GEFIXT` and `FINDINGS_VORHERIGE_RUNDE` stay round-local (reset per batch). **MANDATORY after EVERY round:** update the batch row (rounds consumed, C/I/M accumulated) — crash-safe, a session death costs at most the batch in progress.

**Non-determinism:** findings are LLM judgments, not reproducible tests. `clean` means "audited and fixed in this run", never "re-verifiably green". Clean batches are NEVER re-audited for confirmation — re-audit only via `resume-check.sh` when files changed.

**Convergence check:** per batch after every round. If Critical+Important do NOT decrease AND ROUND >= 2 → `NO_CONVERGENCE`, remaining findings become open points.

### Loop (SINGLE = 1 batch row, BATCHED = N rows)

```
while $STATE_FILE has pending rows:
    BATCH = first pending row → status running (write state file)
    ROUND = 1
    while ROUND <= {MAX_RUNDEN_PRO_BATCH} AND NOT CLEAN:
        AUDIT_RUNDE with {BATCH_DATEILISTE} = content of $BATCH_DIR/batch-{ID}.txt (fills the prompt-template full-audit section)
        Update batch row (rounds, C/I/M)
        if not CLEAN: ROUND += 1
    CLEAN          → row: clean + HEAD short SHA
    NO_CONVERGENCE → row: blocked + checkbox bullet under "## Blocked / Needs review"
```

### Procedure AUDIT_RUNDE

**Step A — Announcement**

BATCHED: `Full-Audit — Batch {AKTUELLER_BATCH}/{N} ({BATCH_VERZEICHNIS}) — {X} files — Round {RUNDE}/{MAX_RUNDEN_PRO_BATCH}`
SINGLE: `Full-Audit Round {RUNDE}/{MAX_RUNDEN_PRO_BATCH} — {TOTAL_FILES} files`

TodoWrite: `Round {RUNDE} — dispatch subagents` (in_progress), `Round {RUNDE} — fix findings` (pending).

**Step A — dispatch subagents in parallel**

MANDATORY: dispatch ALL subagents contained in `SELECTED_DIMENSIONS` (from Phase 0.5) in EVERY round. Non-selected dimensions are skipped entirely — not caught up in later rounds either. Fixes can introduce issues in the selected dimensions.

Dispatch all in a single message block. Pass ARCHITEKTUR-NOTIZ + PROJECT_CONTEXT + FRAMEWORK + SOURCE_DIRS + SUPPRESSIONS + TRANSLATION_DATEIEN + **only the batch files**.

Agent definitions: `{AUDIT_AGENTS}/*.md`.

| # | Agent | Short name |
|---|---|---|
| 1 | `1-architecture.md` | Architecture & Code Reuse |
| 2 | `2-security.md` | Security |
| 3 | `3-performance.md` | Performance |
| 4 | `4-code-quality.md` | Code Quality |
| 5 | `5-seo.md` | SEO |
| 6 | `6-a11y.md` | Accessibility (WCAG) |
| 7 | `7-typography.md` | Typography |
| 8 | `8-ui-design.md` | UI Visual Design |
| 9 | `9-ux.md` | UX Patterns |
| 10 | `10-animation.md` | Animation |
| 11 | `11-docs-sync.md` | Docs Sync & Style |
| 12 | `12-copy.md` | Copy & UX-Writing |

Prompt template: `{AUDIT_AGENTS}/prompt-template.md` → section "For /full-audit (codebase-based)".

**Idle watchdog (applies to ALL dispatched agents in this phase — workers, fix agents, verifiers; adopted from `../audit/SKILL.md`):** an agent that goes idle WITHOUT having delivered its report (idle notification but no findings/FIX_RESULT message) gets exactly ONE automatic re-prompt via SendMessage ("You went idle without delivering your findings/report. Send it now via SendMessage to \"main\" in the requested format."). Still nothing after that: dispatch ONE fresh agent for the same dimension/assignment before falling back further — a single idle event is not enough evidence to skip a dimension outright. Only if that fresh agent ALSO fails to deliver → failure path per agent type: **worker** → note in the audit log, continue without the dimension for this batch; **fix agent** → check `git diff HEAD` on its files first (changes present = APPLIED + mandatory verifier), otherwise re-dispatch once more; **verifier** → treat as `RECOMMEND=patch` (fix stays, finding carries to next round). Do not wait indefinitely and do not re-prompt more than once per agent.

**Skip rules:**
- Dimension NOT in `SELECTED_DIMENSIONS` → don't dispatch the agent at all
- **5 (SEO): skip project-wide if the project has no web frontend at all.** Check once per Full-Audit: `find . -path ./node_modules -prune -o \( -name '*.html' -o -name '*.tsx' -o -name '*.jsx' -o -name '*.vue' -o -name '*.svelte' -o -name '*.astro' -o -name '*.blade.php' \) -print -quit` returns nothing → pure native/CLI/JSON-API project (e.g. only Swift + bun backend), SEO has no attack surface → never dispatch agent 5 (no wasted tokens). On a hit, decide normally per batch content.
- 5 (SEO), 6 (A11y), 8 (UI Design), 9 (UX), 10 (Animation): no frontend files in the batch
- 7 (Typography), 12 (Copy): neither frontend nor translation files in the batch
- 11 (Docs Sync): runs exactly once per Full-Audit (in the first batch or as its own final pass after Phase 2.5) — not per batch.

Agents 5-10 run for ALL frontend files — including app-internal views.

**Step B — consolidate**

Deduplication: same spot flagged by multiple subagents → one finding, strictest rating.

**Step B.5 — hallucination validator (MANDATORY)**

Before every fix:
1. `test -f "{datei}"` — no → discard
2. `wc -l "{datei}"` — line > file length → discard
3. External APIs/libraries: verify via context7 or grep in `vendor/`/`node_modules/`. Not verifiable → `low confidence`.

Log discarded ones as `HALLUCINATED: ...`, do not fix.

Check YOURSELF (round 1, batch 1 only):
- Tests: important services/commands without tests?
- Mobile apps: `bash "$AUDIT_BIN/detect-mobile.sh"` — on a hit, impact matrix from `{AUDIT_REFS}/mobile-impact.md`.

(Note: documentation runs as agent 11 — its own pass, no orchestrator check.)

Output:
```
## Full Audit — Batch {AKTUELLER_BATCH}/{N} Round {RUNDE}/3 — X Critical, Y Important, Z Minor

### Critical / Important / Minor / Clean
[same structure]
```

**Step C — auto-fix (ALL findings)**

TodoWrite: `Round {RUNDE} — fix findings` (in_progress).

**Base rule:** everything gets fixed — except `low confidence`.

Confidence gate (scales with `CONFIDENCE_FLOOR` from Phase 0.7):
- `floor=high` (low effort): fix only `high`, rest stays in the log
- `floor=medium` (medium effort): fix `high`+`medium`. `low` → re-verification: read the spot specifically; confirmed → fix, otherwise discard (no open point, no issue)
- `floor=low` (high/xhigh effort, default): fix everything, `low` gets a warning marker

Fix Minor findings when `FIX_MINOR=1` (medium/high/xhigh). Unfixed Minor findings stay ONLY in the log.

**Open points are ONLY genuine decision points** (architecture tradeoffs, behavior changes) — everything else gets fixed or discarded.

**HARD RULE: the orchestrator NEVER edits code files itself.** Every fix, no matter how trivial, goes via a parallel fix subagent (Sonnet). Orchestrator edits on Opus cost a multiple.

**Allowed orchestrator edits:** `.claude/audits/*.md` (log + state file), `.claude/audits/full-audit-batches/*.txt`, `CLAUDE.md` context draft, `suppressions.json`, changelog files.

- 0 findings → `CLEAN`
- Otherwise: fix all high/medium via fix subagent. Group findings by file, bundle multiple findings per file into one fix-agent call.
- **Centralization findings (new shared utility / helper / trait):** if a finding extracts a duplicated pattern into a new `lib/*.js` (or similar), FIRST grep all occurrences (`grep -rn "{altes_pattern}" src/`, adjust the glob to the project language) and hand ALL matching files to ONE single fix agent (no parallel split, or file collision results). Mark as a centralization fix so the fix agent applies the extended file boundary (see `fix-agent.md` special case) and migrates every occurrence.
- Add each fix to `BEREITS_GEFIXT`. Increment C/I/M in the batch row of the state file.
- Unclear fix → ask briefly. No "open point" without explicit user consent.
- **Hook-blocked files** (e.g. `.env.example` blocked by a write-protection hook): not a plain open point. Present a ready diff/copy-paste block in the chat and actively offer to apply it yourself via `!` command, not just list it.
- Result: `FIXES_APPLIED`.

**Note:** Full-Audit loops internally (while loop), NOT via the `audit-loop.sh` Stop hook. NEVER output `AUDIT_STATUS:` (hook collision) — the Full-Audit line is called `FULL_AUDIT_STATUS`. **Every turn ends with:**

```bash
bash "$FULL_AUDIT_BIN/status-line.sh" "$STATE_FILE"
```

Output the line verbatim as the last line. Completion is decided ONLY from this line of the current turn, never from memory.

### After every round (update the state row, then:)

| Result | ROUND | Action |
|---|---|---|
| `CLEAN` | — | row → clean + HEAD; next pending batch (or Phase 2.5) |
| `FIXES_APPLIED` | < {MAX_RUNDEN_PRO_BATCH} | convergence check; else ROUND+1 |
| `FIXES_APPLIED` | = {MAX_RUNDEN_PRO_BATCH} | **regression pass first** (below), then row → clean + HEAD; next batch (or Phase 2.5) |

### Regression pass after the final round (MANDATORY)

The last round applies fixes and no round is left to look at them. Every other round is checked by the one after it; this one would ship unchecked.

Dispatch ONE worker, scoped to the files the final round's fix agents actually touched (`git diff --name-only` against the round's starting state), not a full dimension sweep. Its brief is the seam, not the dimension:

- Fixes applied by parallel agents that could not see each other's edits: contradictions, half-applied changes, a comment that now describes something else, an import that no longer matches.
- State a fix forgot to reset, a lifecycle a fix left half-torn-down, a check a fix moved but did not re-verify from the other side.
- Anything the round's own fix reports flagged as "skipped" or "outside my boundary".

Findings from this pass are fixed like any other. It does NOT open a new round and does not extend `{MAX_RUNDEN_PRO_BATCH}`; on findings it cannot resolve, the row goes `blocked` rather than `clean`.

Why this is not optional: in the run that produced this rule, two of six Critical findings were regressions introduced by the audit's own fixes, and both were caught only because the orchestrator improvised exactly this pass. Parallel fix agents with disjoint file boundaries are fast and blind to each other; something has to look at the seam.
| `NO_CONVERGENCE` | — | row → blocked + bullet; open findings become open points |

---

## Phase 2.5: Cross-Reference Round

**Ordering is deliberate, not incidental:** this pass runs AFTER all batches are fixed, never interleaved with or before them. A fix applied during Phase 2 can itself introduce a new cross-boundary regression (e.g. a rename fixed in one batch that a fix agent in a different batch, with a disjoint file boundary, never sees) — running cross-reference only once everything is fixed is what catches that class of problem. Do not "optimize" this by folding it into the per-batch loop or moving it earlier to save a pass; that would only check for pre-existing cross-file issues and miss the ones the audit's own fixes just created.

**Skip conditions** (check in this order):
- `SKIP_CROSS_REF=1` from Phase 0.7 (low effort) → skip entirely
- Neither `architecture` nor `code_quality` in `SELECTED_DIMENSIONS` → skip
- SINGLE mode AND `FORCE_CROSS_REF_SINGLE` not set (medium effort) → skip

Otherwise after all batches: 2 subagents in parallel:

| # | Focus | Scope |
|---|---|---|
| 1 | Cross-module dependencies | Services ↔ UI called incorrectly, Models ↔ Traits/Mixins misused, controller-view mismatches |
| 2 | Consistency | Same patterns applied uniformly? (auth checks, cache keys, error handling) |

Input: ARCHITEKTUR-NOTIZ + BEREITS_GEFIXT + summary of all batch findings.
Fixes as in Step C. No further rounds.

Afterward (even on skip): in `$STATE_FILE` set `post-phases:` → `cross_ref=done`.

---

## Phase 3: Changelog, Linter, Tests, Test Plan

### 3a. Changelog

Search for `CHANGELOG.md`, `changelog.md`, `release-notes/next.md`, `resources/changelog.md`, `CHANGES.md`. User-facing fixes (UI, API, routing, translations) → draft an entry.

### 3b. Linter & Static Analysis

See `{AUDIT_REFS}/linters-and-tests.md`. In Full-Audit mode all linters/formatters run globally (not file-scoped). On errors: fix manually, re-run.

### 3c. Tests

See `{AUDIT_REFS}/linters-and-tests.md` (test runner table). Run all detected runners. Fix failures. Unfixable ones become an open point.

**No test runner configured:** with `TEST_RUNNER_ESCALATE=1` (Phase 0.4, streak >= 3) record the missing test infrastructure as **Critical** in the audit log and as a GitHub issue (Phase 4). Otherwise just a gap note (`Tests: skipped — no runner configured`).

### 3d. Manual test plan

If `VISUELL_RELEVANTE_DATEIEN` is not empty: max 15 steps (more than /audit, because Full-Audit covers the entire codebase). Format as in /audit, see `{AUDIT_REFS}/testplan.md`.

---

## Phase 4: Audit Log + GitHub Issues

Detail in `references/audit-log-and-issues.md`. Briefly:

- Write the audit log to `.claude/audits/{datum}-full-audit.md` (format template in the reference). Record `SELECTED_DIMENSIONS` in the header so later audits know which dimensions were not checked.
- **Open-point aging:** before presenting them, compare the open points against previous `.claude/audits/*-full-audit.md` files (chronologically). A point that (same file + same core statement) already stood open in `>= 2` earlier audit logs gets an **`AGED`** marker in the current log and appears as a prioritized block at the very top of the open-points section ("open 3x+ — decision overdue"). This keeps tradeoff decisions from stalling audit after audit.
- Load the log via the Read tool and display it in chat as a markdown code block (MANDATORY). Afterward `post-phases:` → `log=done`.
- Present open points to the user (AskUserQuestion): **Decide + fix now / Defer as issue / Discard**. Present `AGED` points first. Issues ONLY for deferred items (dedup per finding). Minor never gets issues — stays in the log. Afterward (even with no open points) `post-phases:` → `issues=done`.

---

## Phase 5: Learning

**Skip when `SKIP_LEARNING=1`** (low effort). Go directly to wrap-up.

```
Agent(
  prompt: "Read {AUDIT_AGENTS}/learning-agent.md and execute the flow.
    PROJECT_ROOT={PROJECT_ROOT}
    AKTUELLES_LOG={Inhalt des Audit-Logs}
    AUDIT_TYPE=full-audit",
  subagent_type: general-purpose,
  model: sonnet,
  mode: bypassPermissions
)
```

**Foreground mode matters:** background subagents cannot write `.claude/audits/learning-log.md` (hardcoded `.claude/` protection that also applies under `bypassPermissions`, and background subagents cannot prompt the user). Foreground works around this at a cost of ~5-10s extra at the end.

---

## Wrap-up

**Completion gate (Bash decides, not memory):**

```bash
bash "$FULL_AUDIT_BIN/status-line.sh" "$STATE_FILE"
```

If the line does NOT show `pending=0 running=0` and `post_phases=done` → NO marker: output an interim digest + status line, end the turn (resume or /loop continues). `blocked>0` does not block completion (points live in the state section + log).

**Otherwise — write push marker (MANDATORY):**

```bash
# Write marker — NO git push in the same bash call!
hash=$(echo -n "$PWD" | md5 2>/dev/null || echo -n "$PWD" | md5sum 2>/dev/null | cut -d' ' -f1)
touch "/tmp/claude-audit-passed-$hash"

# Remove PreCompact marker — full audit finished
CWD_HASH=$(pwd | md5 2>/dev/null || pwd | md5sum 2>/dev/null | cut -d' ' -f1)
rm -f "/tmp/claude-audit-in-progress-${CWD_HASH}"
```

The state file stays in place (history + dirty-check basis for the next run). Fresh restart: delete the state file + `$BATCH_DIR`.

Marker: TTL 30 min, is not deleted (multiple hooks check sequentially).

```
Full Audit completed.
- Scope: {N}/12 dimensions — {SELECTED_DIMENSIONS}
- Mode: {BATCH_MODE} ({N} batches, {TOTAL_ROUNDS} rounds)
- {TOTAL_CRITICAL} Critical, {TOTAL_IMPORTANT} Important, {TOTAL_MINOR} Minor found and fixed
- Log: .claude/audits/{DATUM}-full-audit.md
- Learning: .claude/audits/learning-log.md
```
