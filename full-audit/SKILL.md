---
name: full-audit
description: "Comprehensive one-time audit of an entire codebase (not just recent changes). Auto-detects framework (Laravel, Next.js, Nuxt, Django), batches large codebases, runs up to 12 parallel subagents per batch (architecture incl. migrations and observability, security, performance, code quality, SEO, a11y, typography, UI, UX, animation, docs sync, copy), auto-fixes including Minor, runs a cross-reference pass, generates a manual test plan. Use when the user runs /full-audit, starts on a new project, asks for a comprehensive review, or wants the whole codebase checked. NOT for pre-push of recent changes — use /audit instead."
when_to_use: "/full-audit, ganzes projekt prüfen, komplette codebase auditen, gesamten code einmal durchchecken, neues projekt komplett prüfen, full codebase audit, audit whole project, starting on a new project, comprehensive review"
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
  - SendMessage   # idle watchdog re-prompts dispatched agents
---

# Full Codebase Audit

**EXECUTE IMMEDIATELY — do not explain, do not announce. Start directly with Phase 0.**

> **Architecture note:** This skill has NO worker agents of its own. It uses the definitions from `../audit/agents/*.md` (referenced in the skill via `{AUDIT_AGENTS}`). If you want to change worker configuration, edit there. prompt-template.md has two sections ("For /audit" and "For /full-audit (codebase-based)") — workers dispatch the matching section depending on the skill.

Anti-patterns (red flags) see `{AUDIT_REFS}/anti-patterns.md` (path from Phase 0) — Full-Audit additionally fixes ALL Minor findings.

## Running long

This audit runs for many turns, usually with nobody watching. Three rules for that mode:

- **Don't end a turn on an intention.** If your last paragraph is a plan, a question, a list of next steps, or a promise ("I'll now audit batch 3"), do that work now with tool calls instead. End the turn only when the batch matrix is complete or you are blocked on something only the user can decide.
- **Every progress claim needs a tool result from this turn.** "Batch 4 clean" means `status-line.sh` printed it in this turn, not that you remember fixing it. Unverified state is reported as unverified.
- **Context is not a reason to stop.** Do not summarize early, hand off, propose a fresh session, or shrink the audit scope because the session is long. The state file plus `resume-check.sh` exist exactly so a run can be picked up later, use them, don't pre-empt them.

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

# Run-ledger start marker (see run-log.sh header) — before any real work.
# Re-fires on every resumed invocation too, so a resumed run's duration
# measures that invocation's own elapsed time, not time spent paused.
bash "$AUDIT_BIN/run-log.sh" --start --skill full-audit

# Eigene Scripts + persistenter Goal-Loop-State (Format/Resume: references/state-file.md)
FULL_AUDIT_BIN="${CLAUDE_SKILL_DIR:-$HOME/.claude/skills/full-audit}/bin"
STATE_FILE="$(git rev-parse --show-toplevel)/.claude/audits/full-audit-state.md"
BATCH_DIR="$(git rev-parse --show-toplevel)/.claude/audits/full-audit-batches"

bash "$AUDIT_BIN/verify-agents.sh" "$AUDIT_AGENTS" || { echo "Full-Audit abgebrochen — fehlende Agent-Dateien."; exit 1; }

# Worktree config guard: a worktree without its own .env has no config source to rebuild from
if [ "$(git rev-parse --git-common-dir)" != ".git" ] && [ ! -f ./.env ]; then
  echo "GUARD: worktree without own .env — php artisan config:clear is FORBIDDEN for this entire run."
fi
```

**On a guard hit:** `php artisan config:clear` must never run in this session — it deletes the only configuration source the worktree has. The command is also embedded in `composer test`, so that path is equally forbidden; run scoped `php artisan test` invocations instead. A violation destroyed a test environment on 2026-08-04.

**Resume check:** If `$STATE_FILE` already exists → RESUME mode:

```bash
bash "$FULL_AUDIT_BIN/resume-check.sh" "$STATE_FILE"
```

Every `BATCH_DIRTY` line: reset the batch row to `pending` (Rounds `0/{max}`, zero C/I/M, HEAD `-`). `running` rows also reset to `pending` (half-audited batches are re-audited from scratch, never resumed mid-batch). Take over `mode`/`effort`/`dimensions` from the state header, SKIP phases 0.3-1.5, go directly to Phase 2 starting at the first `pending` batch. Detail: `references/state-file.md`.

**Coverage rescan (MANDATORY on resume, before Phase 2).** `resume-check.sh` only asks whether files ALREADY in a batch list have changed. It cannot see a file that is in no list at all, and a state file can be days or weeks old — the codebase grows in the meantime. Re-run this document's scope collection (`references/scope-context-batching.md`) and diff it against the union of the batch lists:

```bash
cat "$BATCH_DIR"/batch-*.txt | sort -u > /tmp/full-audit-covered.txt
comm -23 /tmp/full-audit-files.txt /tmp/full-audit-covered.txt > /tmp/full-audit-uncovered.txt
wc -l < /tmp/full-audit-uncovered.txt
```

Non-empty: append the uncovered files as one or more NEW batches (same size rules), add their rows as `pending`, and note the count under `## Notes` in the audit log. A resumed run that audits only its old lists reports "codebase audited" over a codebase it never fully saw. On 2026-08-06 the orchestrator happened to notice this and rebuilt the lists by hand, finding 51 files no old list covered; a smaller drift would not have caught anyone's eye.

---

**Scope argument:** `$ARGUMENTS` holds the optional directory scope (empty when none was given). Non-empty means: restrict batching and every worker's file list to that path prefix, and record it in the state-file header.
## Phases 0.3 to 0.45: Pre-flight checks

Read `references/pre-flight-phases.md` and execute all three in order:

- **0.3 Learning backlog + open issues/PRs.** Unprocessed `- [ ]` suggestions in `learning-log.md` are offered for implementation; open `audit-finding` issues can be fed into batch 1; open PRs become dedup context. Skipped with `AUDIT_SKIP_LEARNING_CHECK=1` or `FULL_AUDIT_SKIP_LEARNING_CHECK=1`.
- **0.4 Test runner streak.** A missing test runner escalates to a Critical finding once the streak reaches the threshold, because without a runner no fix agent can verify a regression.
- **0.45 Build preflight.** Compiled languages must build before the audit starts; a broken build makes every downstream finding unreliable.
## Phase 0.5: Dimension Selection

Which of the 12 dimensions run. `FULL_AUDIT_DIMENSIONS` (env) sets it non-interactively for CI;
otherwise ask via AskUserQuestion. Presets, the custom multi-select, validation and the display line
are in `references/dimension-selection.md`, read and execute it. Result: `SELECTED_DIMENSIONS`,
at least one valid dimension.

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

**Scope plausibility assert (MANDATORY, runs inside that same bash, before Phase 1.5 or any batch dispatch):** abort loudly if `TOTAL_FILES` is zero, or implausibly small against `git ls-files` — see `references/scope-context-batching.md`. A wrong scope must never produce a clean-looking audit over files nobody enumerated.

Optional pre-checks (only with a local diff): run `pre-checks.sh`.

**i18n completeness (deterministic):** `bash "$AUDIT_BIN/check-i18n-keys.sh"` — for `I18N_RESULT=MISSING` every line becomes an Important finding `[i18n]` (Full-Audit checks the entire codebase, so report all gaps).

**Dependency health (deterministic):** `bash "$AUDIT_BIN/check-outdated.sh"` (full mode) —
- `DEP_SECURITY_RESULT=VULNS` → every vulnerable dependency becomes a **Critical** finding `[Security]`
- `DEP_OUTDATED_RESULT=OUTDATED` → collect as **Minor** findings `[Dependencies]` (grouped, not one issue per package); major jumps with breaking-change risk (e.g. `stripe-php 17 → 20`) become an open point instead of an auto-update — dependency updates are NEVER done automatically by the fix agent
- `DEP_SECURITY_RESULT=TIMEOUT` → not a finding, not clean: the vulnerability check did not complete. Record a gap note (`Dependency security: skipped, network check timed out`), same class as the Phase 0.4 test-runner / Phase 0.45 build-preflight gap notes, so repeats accumulate toward the Phase 4 aged-gap escalation instead of passing as a silent all-clear.
- `DEP_OUTDATED_RESULT=TIMEOUT` → same handling, lower stakes: gap note `Dependency updates: skipped, network check timed out`.

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

Batch rules and bash logic in `references/scope-context-batching.md`. Max `BATCH_MAX` (~15) files per batch, derived from the worker tool-call budget — see reference for the arithmetic. Related files together.

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

**Step A.2 — dispatch subagents in parallel**

MANDATORY: dispatch ALL subagents contained in `SELECTED_DIMENSIONS` (from Phase 0.5) in EVERY round. Non-selected dimensions are skipped entirely — not caught up in later rounds either. Fixes can introduce issues in the selected dimensions.

Dispatch all in a single message block. Pass ARCHITEKTUR-NOTIZ + PROJECT_CONTEXT + FRAMEWORK + SOURCE_DIRS + SUPPRESSIONS + TRANSLATION_DATEIEN + **only the batch files**. Dispatch every agent whose output this turn must consume (workers, finding verifiers, fix agents, cross-ref) with `run_in_background: false`; background is the default since v2.1.198 and returns only in a later turn.

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

**Partial coverage (`COVERAGE:` trailing line, `{AUDIT_AGENTS}/prompt-template.md`).** Every worker reply ends with `COVERAGE: full` or `COVERAGE: partial | not read: {file1}, {file2}, ...`. A `partial` reply means the dimension is NOT covered for this batch round, however clean the findings look. Collect the named files per dimension into `UNCOVERED_BY_DIM`. If a round remains in this batch (`ROUND < {MAX_RUNDEN_PRO_BATCH}`), that dimension's file list for `ROUND+1` is `UNCOVERED_BY_DIM[dimension]` instead of the full `{BATCH_DATEILISTE}`, so the retry's budget goes to what was missed first — this is the manual rescoping the 2026-08-06 run did by hand, made automatic. Disposition when no round remains: see "After every round" below.

**Dispatch is rate-limited mid-run (org/session limit).** The skill assumes subagents are always
available; they are not. When `Agent` calls start failing on a usage limit, do NOT silently drop the
remaining assignments and do NOT let the orchestrator quietly become the fix agent for the whole
backlog. Decide by what is left: **few, small, already-verified fixes** -> the orchestrator applies
them directly and the audit log names every fix it applied itself (the hard "orchestrator never edits
code" rule yields to the limit, but only for findings that already passed verification). **Anything
larger** -> stop the wave, write the current state (round, confirmed findings, applied fixes, open
assignments) into the audit log, report the reset time to the user, and resume from that state when
dispatch works again. Either way the audit log gets a `## Notes: Dispatch limit` block, because a run
finished this way is not the same evidence as a run with full worker coverage (2026-08-03: the limit
hit mid-run, the final cross-ref fixes and three open-point fixes were applied by the orchestrator,
which no line of the skill covered).


**Idle rate is a run-level signal, not just a per-agent nuisance.** Count every agent that needed the re-prompt, per wave and for the run as a whole. The per-agent recovery above handles the individual case and demonstrably works — on 2026-08-06 roughly 40% of the fleet went idle without a report and every single one delivered after exactly one re-prompt. What was missing was that nobody recorded the RATE, so a systemic prompt-delivery problem read as a series of unrelated hiccups. Therefore: when the re-prompted share of a wave reaches one third or more, write one line under `## Notes` in the audit log (`Idle-without-report: K/N agents in wave {X} needed the re-prompt`) and carry it into Phase 5 as a process observation. Do not change the recovery path because of it and do not add a second re-prompt: the number is evidence for the next prompt-template revision, not a new retry budget.

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

### Unverified
[UNCERTAIN findings from Step C's verification stage, with reason]

### Coverage gaps
[dimension: not read {file1}, {file2}, ... — from `COVERAGE: partial`]
```

The `Coverage gaps` section holds this round's `UNCOVERED_BY_DIM`. Empty section → omit the heading.

**Step C — auto-fix (ALL findings).** Finding verification gate (same stage as `/audit` Step D.7, scaled by `CONFIDENCE_FLOOR`) runs before the fix wave: `CONFIRMED` → fix (with `SEVERITY_CORRECTION` if not `none`), `REFUTED` → discarded, `UNCERTAIN` → `### Unverified`. Everything confirmed gets fixed, including Minor when `FIX_MINOR=1` — the orchestrator never edits code itself, every fix goes via a parallel `fix-agent.md` subagent, grouped by file. Covers the centralization-fix and cross-finding-dependency sequencing rules, `FIX_RESULT=PARTIAL` handling, hook-blocked files, and the allowed orchestrator edits. **MANDATORY: read `references/fix-loop.md` (section "Step C") and execute it.**

**Note:** Full-Audit loops internally (while loop), NOT via the `audit-loop.sh` Stop hook. NEVER output `AUDIT_STATUS:` (hook collision) — the Full-Audit line is called `FULL_AUDIT_STATUS`. **Every turn ends with:**

```bash
bash "$FULL_AUDIT_BIN/status-line.sh" "$STATE_FILE"
```

Output the line verbatim as the last line. Completion is decided ONLY from this line of the current turn, never from memory.

### Per-round dedup sweep (after fixes, before the next round)

Runs after Step C, before the next round: a deterministic `git diff` grep for the same top-level declaration added in `>= 2` files by parallel fix agents that could not see each other's edits — the per-agent grep in `fix-agent.md` only sees one agent's own diff. **MANDATORY: read `references/fix-loop.md` (section "Per-round dedup sweep") and execute it.**

### After every round (update the state row, then:)

| Result | ROUND | Action |
|---|---|---|
| `CLEAN`, `UNCOVERED_BY_DIM` empty | — | row → clean + HEAD; next pending batch (or Phase 2.5) |
| `CLEAN`, `UNCOVERED_BY_DIM` non-empty | < {MAX_RUNDEN_PRO_BATCH} | Not actually done: ROUND+1, re-dispatch only the affected dimensions against their unread files |
| `CLEAN`, `UNCOVERED_BY_DIM` non-empty | = {MAX_RUNDEN_PRO_BATCH} | row → blocked + bullet under `## Blocked / Needs review` naming dimension + unread files (never fully covered) |
| `FIXES_APPLIED` | < {MAX_RUNDEN_PRO_BATCH} | convergence check; else ROUND+1 (carries `UNCOVERED_BY_DIM` per above if present) |
| `FIXES_APPLIED` | = {MAX_RUNDEN_PRO_BATCH} | **regression pass first** (`references/fix-loop.md` section "Regression pass after the final round"), then row → clean + HEAD; next batch (or Phase 2.5) — UNLESS `UNCOVERED_BY_DIM` or an unresolved `PARTIAL` remainder survives the pass, then row → blocked instead |
| `NO_CONVERGENCE` | — | row → blocked + bullet; open findings become open points |

### Regression pass after the final round (MANDATORY)

The batch's last round applies fixes with no following round to check them — every other round is checked by the one after it, this one would ship unchecked. **MANDATORY: read `references/fix-loop.md` (section "Regression pass after the final round") and execute it** — one worker scoped to the files the final round's fix agents touched, findings fixed like any other, row goes `blocked` (not `clean`) on anything it cannot resolve.

---

## Phase 2.5: Cross-Reference Round

**Ordering is deliberate, not incidental:** this pass runs AFTER all batches are fixed, never interleaved with or before them. A fix applied during Phase 2 can itself introduce a new cross-boundary regression (e.g. a rename fixed in one batch that a fix agent in a different batch, with a disjoint file boundary, never sees) — running cross-reference only once everything is fixed is what catches that class of problem. Do not "optimize" this by folding it into the per-batch loop or moving it earlier to save a pass; that would only check for pre-existing cross-file issues and miss the ones the audit's own fixes just created.

**Skip conditions** (check in this order):
- `SKIP_CROSS_REF=1` from Phase 0.7 (low effort) → skip entirely
- Neither `architecture` nor `code_quality` in `SELECTED_DIMENSIONS` → skip
- SINGLE mode AND `FORCE_CROSS_REF_SINGLE` not set (medium effort) → skip

Otherwise after all batches: 3 subagents in parallel:

| # | Focus | Scope |
|---|---|---|
| 1 | Cross-module dependencies | Services ↔ UI called incorrectly, Models ↔ Traits/Mixins misused, controller-view mismatches |
| 2 | Consistency | Same patterns applied uniformly? (auth checks, cache keys, error handling) |
| 3 | Trust boundaries | Follow each trust boundary end to end — input endpoint, storage, use site — across batch lines |

**Why subagent 3 exists:** file-batching creates blind spots exactly at trust boundaries. The endpoint that accepts input and the code that later uses it routinely land in different batches, so no per-batch worker ever sees the full path. Reference case: an SSRF whose endpoint sat in one batch and whose send path in another — invisible to every batch agent. Subagent 3 ignores batch lines entirely and traces each boundary from input to use.

Input: ARCHITEKTUR-NOTIZ + BEREITS_GEFIXT + summary of all batch findings.
Fixes as in Step C. No further rounds.

**This round is never shortened or skipped under time/token pressure once it is scheduled to run** (i.e. outside the skip conditions above). It is the only mechanism that catches regressions the fixes themselves introduced across disjoint fix-agent boundaries, and it did so three times in one recorded run. Cutting it to save time defeats the reason it exists.

Afterward (even on skip): in `$STATE_FILE` set `post-phases:` → `cross_ref=done:agents=3` (the 3 subagents above were dispatched), or, on skip, `cross_ref=skipped:<reason>` naming which skip condition applied (`effort_low`, `dims_excluded`, `single_no_force`). A bare `cross_ref=done` with no witness does not count as done — see `references/state-file.md` "Post-Phase Witnesses".

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
- **Open-point + gap aging:** before presenting them, compare the open points AND the recorded gap notes (test-runner, build-preflight, translation-completeness, and any other line logged as a gap rather than a fix) against previous audit logs, chronologically. Compare across ALL audit logs in `.claude/audits/*.md` — regular `/audit` logs included, not only `*-full-audit.md` — otherwise a point or gap that only ever recurs in pre-push `/audit` runs never accumulates the count needed to escalate. A point or gap that (same file/area + same core statement) already stood open in `>= 2` earlier logs of either kind gets an **`AGED`** marker in the current log and appears as a prioritized block at the very top of its section — open points at the top of the open-points section, aged gaps at the top of the "## Gaps" section (or wherever the log records gap notes, if it has no dedicated heading for them) — labelled "open/present 3x+ — decision overdue". This keeps both tradeoff decisions and infrastructure gaps from stalling audit after audit.
- Load the log via the Read tool and display it in chat as a markdown code block (MANDATORY). Afterward `post-phases:` → `log=done:written={path}` ({path} = the `.claude/audits/{datum}-full-audit.md` just written).
- Decide open points yourself, do not put them to the user: default **fix now** from the repo's own evidence, **discard** what the evidence refutes, **defer as issue** only for a point needing information outside the repo. Handle `AGED` points first. One reported line per point. Issues ONLY for deferred items (dedup per finding). Minor never gets issues — stays in the log. Afterward (even with no open points) `post-phases:` → `issues=done:presented={n}` ({n} = number of open points handled, `0` if none — still a witness, just an empty one).

---

## Phase 5: Learning

**Skip when `SKIP_LEARNING=1`** (low effort). Go directly to wrap-up.

**First, the run-ledger check (single source of truth, same as /audit):** read `../audit/references/learning-phase.md` "Step 0" and execute it against the just-written full-audit log (`$AUDIT_BIN` already resolved in Phase 0).

```
Agent(
  prompt: "Read {AUDIT_AGENTS}/learning-agent.md and execute the flow.
    PROJECT_ROOT={PROJECT_ROOT}
    AKTUELLES_LOG={Inhalt des Audit-Logs}
    AUDIT_TYPE=full-audit",
  subagent_type: general-purpose,
  model: sonnet,
  run_in_background: false
)
```

**Foreground mode matters, and it has to be requested explicitly.** Since Claude Code v2.1.198 subagents run in the background by default, so omitting `run_in_background: false` backgrounds the learning agent, its result then arrives as a completion notification in a later turn, after the orchestrator has already finished the wrap-up, and the learning pass is silently lost. On top of that, background subagents cannot write `.claude/audits/learning-log.md` themselves (hardcoded `.claude/` protection that also applies under `bypassPermissions`, and they cannot prompt the user). Foreground costs ~5-10s at the end.

---

## Wrap-up

**Completion gate (Bash decides, not memory):**

```bash
FULL_STATUS_LINE="$(bash "$FULL_AUDIT_BIN/status-line.sh" "$STATE_FILE")"
echo "$FULL_STATUS_LINE"
```

If the line does NOT show `pending=0 running=0` and `post_phases=done` → NO marker: run **Run log** below (`outcome=paused`, `gate=n/a`), output an interim digest + status line, end the turn (resume or /loop continues). `blocked>0` does not block completion (points live in the state section + log).

**Otherwise — write push marker (MANDATORY):**

```bash
# Write marker — NO git push in the same bash call!
hash=$(echo -n "$PWD" | md5 2>/dev/null || echo -n "$PWD" | md5sum 2>/dev/null | cut -d' ' -f1)
touch "/tmp/claude-audit-passed-$hash"

# Remove PreCompact marker — full audit finished
CWD_HASH=$(pwd | md5 2>/dev/null || pwd | md5sum 2>/dev/null | cut -d' ' -f1)
rm -f "/tmp/claude-audit-in-progress-${CWD_HASH}"
```

Run **Run log** below (`outcome=complete`, `gate=passed`).

**Run log (fires from both branches above):**

```bash
bash "$AUDIT_BIN/run-log.sh" --skill full-audit --outcome "{complete|paused}" \
  --counts "$(echo "$FULL_STATUS_LINE" | sed 's/^FULL_AUDIT_STATUS //; s/ /,/g')" \
  --gate "{passed|n/a}"
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
