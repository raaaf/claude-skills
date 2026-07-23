---
name: audit
disable-model-invocation: true
description: "Pre-push code audit. Routes the diff to relevant subagents (architecture incl. migrations and observability, security, performance, code quality, SEO, a11y, typography, UI, UX, animation, docs sync, copy), runs secret/lockfile/i18n pre-checks, auto-fixes via parallel fix-agents with peer-review verification, loops until clean, generates a manual test plan, then allows git push. An argument scopes to selected dimensions ('/audit security', '/audit frontend', '/audit ?' for a multi-select prompt) — partial audits fix as usual but never write the push marker. Use when the user runs /audit, says 'before pushing' or 'review my changes', or has uncommitted/unpushed changes that should be checked. NOT for whole-codebase audits — use /full-audit instead."
when_to_use: "/audit, before pushing, git push, pre-push review, review my changes, audit uncommitted changes, check before pushing"
argument-hint: "[optional: dimensions (security | performance,a11y | backend | frontend | design | ?) or scope hint]"
model: opus
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
      hook: bash "${CLAUDE_PROJECT_DIR:-$HOME/.claude/skills/audit}/hooks/block-unsafe-push.sh"
---

# Audit: Review of all open changes

**EXECUTE IMMEDIATELY — do not explain, do not announce. Start directly with Phase 0.**

Anti-patterns / common mistakes in the loop: `references/anti-patterns.md`.

## Phase 0: Pre-flight checks (learning backlog + open issues/PRs)

Both checks (learning backlog question, open `audit-finding` issues + PR dedup context) are in `references/pre-flight-checks.md` — read and execute. Result: issues as findings for round 1 if applicable, `OPEN_PRS` as dedup context for Phase 3f.

**Skip this phase if:** ENV `AUDIT_SKIP_LEARNING_CHECK=1` is set (for CI/batch runs) — then also no issue question.

## Phase 0.5: Effort configuration

The skill scales depth by `${CLAUDE_EFFORT}`. Default `medium`.

```bash
CLAUDE_EFFORT="${CLAUDE_EFFORT:-medium}"
case "$CLAUDE_EFFORT" in
  low)    MAX_RUNDEN=1; FIX_MINOR=0; SKIP_LEARNING=1; CONFIDENCE_FLOOR=high ;;
  high)   MAX_RUNDEN=3; FIX_MINOR=1; SKIP_LEARNING=0; CONFIDENCE_FLOOR=low ;;
  medium|*) MAX_RUNDEN=2; FIX_MINOR=1; SKIP_LEARNING=0; CONFIDENCE_FLOOR=medium ;;
esac
echo "Effort=$CLAUDE_EFFORT | Runden=$MAX_RUNDEN | FixMinor=$FIX_MINOR | SkipLearning=$SKIP_LEARNING | ConfidenceFloor=$CONFIDENCE_FLOOR"
```

| Level | Rounds | Fix Minor | Learning | Confidence floor |
|---|---|---|---|---|
| low | 1 | no | skip | high (safe fixes only) |
| medium (default) | 2 | yes | yes | medium |
| high | 3 | yes | yes | low (also fix unsafe ones, with warning) |

Below, `{MAX_RUNDEN}` means the value set here.

## Phase 0.6: Dimension scoping via argument (optional partial audit)

The skill argument may select dimensions explicitly (`/audit security`, `/audit performance,a11y`, group aliases `backend`/`frontend`/`design`, `?` for a multi-select prompt). If it does: `PARTIAL_AUDIT=1`, `SELECTED_DIMENSIONS={list}` — read `references/partial-audit.md` and apply it (skip triage+floor, `Routing: user-scoped`, Step-D extras only for related dimensions, Phase 4 writes NO push marker, pre-checks always run). Non-dimension arguments stay a free-text scope hint (`PARTIAL_AUDIT=0`).

## Phase 1: Pre-flight & scope

```bash
AUDIT_BIN="${CLAUDE_SKILL_DIR}/bin"
AUDIT_AGENTS_DIR="${CLAUDE_SKILL_DIR}/agents"

# PreCompact-Schutz: blockiert Auto-Compaction waehrend des Audit-Runs
CWD_HASH=$(pwd | md5 2>/dev/null || pwd | md5sum 2>/dev/null | cut -d' ' -f1)
touch "/tmp/claude-audit-in-progress-${CWD_HASH}"

bash "$AUDIT_BIN/verify-agents.sh" "$AUDIT_AGENTS_DIR" || { echo "Audit abgebrochen — fehlende Agent-Dateien."; exit 1; }
bash "$AUDIT_BIN/collect-scope.sh"
bash "$AUDIT_BIN/detect-framework.sh"
bash "$AUDIT_BIN/pre-checks.sh"

# Dependency-Health (nur wenn Manifest/Lockfile im Diff)
if echo "$ALLE_DATEIEN" | grep -qE '(package(-lock)?\.json|composer\.(json|lock)|yarn\.lock|pnpm-lock\.yaml|requirements\.txt|pyproject\.toml|Podfile(\.lock)?|Package\.(swift|resolved)|pubspec\.(yaml|lock)|build\.gradle)'; then
  bash "$AUDIT_BIN/check-outdated.sh" "$(git rev-parse --show-toplevel)"
  # DEP_SECURITY_RESULT=VULNS -> jede gemeldete Zeile wird ein Critical-Finding
  # [Security] (verwundbare Dependency blockiert Push wie jedes Critical).
  # DEP_OUTDATED_RESULT=OUTDATED -> jede gemeldete Zeile (npm/composer outdated)
  # wird ein Minor-Finding [Dependencies] (neue Version verfuegbar, kein Blocker).
  # SKIP/CLEAN/CURRENT -> nichts tun.
fi

# i18n-Vollstaendigkeit (deterministisch, kein LLM)
bash "$AUDIT_BIN/check-i18n-keys.sh"

# Doppelte Array-Keys in Lang-Files (deterministisch, php -l faengt das NICHT)
bash "$AUDIT_BIN/check-duplicate-array-keys.sh"
# DUPKEY_RESULT=DUPLICATES → jede Zeile "DUPLICATE {file}:{line} key ..." wird
# ein Critical-Finding [Correctness], sofern die Datei im Diff liegt. PHP behaelt
# beim Duplikat den LETZTEN Wert, der erste ist stumm weg — der Crash kommt erst,
# wenn ein Code-Pfad den beschatteten Key liest. Ausserhalb des Diffs: als Hinweis
# ausgeben, nicht als Finding. OK/SKIP → nichts tun.

# number_format() ohne Locale-Argumente in Views (deterministisch)
# Neue Checks nach references/writing-deterministic-checks.md bauen.
bash "$AUDIT_BIN/check-number-format-locale.sh"
# NUMFMT_RESULT=MISSING_LOCALE → jede Zeile wird ein Important-Finding
# [Correctness], sofern die Datei im Diff liegt; sonst Hinweis. Laeuft nur bei
# vorhandenem lang/de. OK/SKIP → nichts tun.
# I18N_RESULT=MISSING → jede Zeile "MISSING {locale}: {key}" wird ein
# Important-Finding [i18n] (Schritt D), sofern die betroffenen Keys/Files
# im Diff liegen. Bei /audit ausserhalb des Diffs: als Hinweis ausgeben,
# nicht als Finding. SKIP/OK → nichts tun.

# Project-Specific Guidelines (Override global)
PROJECT_GUIDELINES_FILE="$(git rev-parse --show-toplevel)/.claude/audit-guidelines.md"
PROJECT_GUIDELINES=""
if [ -f "$PROJECT_GUIDELINES_FILE" ]; then
  PROJECT_GUIDELINES=$(cat "$PROJECT_GUIDELINES_FILE")
  echo "Project guidelines: $PROJECT_GUIDELINES_FILE ($(wc -l < "$PROJECT_GUIDELINES_FILE") lines)"
fi
bash "$AUDIT_BIN/diff-size-gate.sh"

eval "$(bash "$AUDIT_BIN/perf-measure.sh" --detect)"   # PERF_MEASURE_CMD: Verify-by-Measurement (opt-in, evtl. leer)
GUIDELINE_MATCHES=$(bash "$AUDIT_BIN/match-guidelines.sh" "${CLAUDE_SKILL_DIR}/guidelines" 2>/dev/null)  # Guidelines die den Diff treffen (name+priority); ohne applies_to = always

# Working-Tree-Exklusivitaet: Basis-Zustand festhalten (Check in Phase 4)
AUDIT_BASE_HEAD=$(git rev-parse HEAD)
AUDIT_BASE_STATUS_HASH=$(git status --porcelain | { md5 2>/dev/null || md5sum | cut -d' ' -f1; })
```

**WIP/stale-snapshot scope check (before Phase 2):** look at `git status --porcelain` + `git diff --stat`. Does the working tree contain files that clearly do NOT belong to the task currently being discussed (pre-existing WIP from another line of work, foreign uncommitted edits, stale snapshots)? Then do NOT silently audit them along with the rest — ask the user via `AskUserQuestion` about the scope: **only the session/task changes** vs. **entire working tree**. Heuristic for "doesn't belong": files in completely different modules than the rest of the diff, or files that were already `M` before the session started. When in doubt, ask — an audit on someone else's WIP produces findings on code the user isn't even working on right now.

Detailed evaluation of the script outputs in `references/scope-and-pre-checks.md`:
- Diff size gate table (OK/LARGE/HUGE)
- Pre-check evaluation (secrets, lockfile, binary artifacts)
- Variable derivation (ALLE_DATEIEN, FRONTEND_DATEIEN, UNIFIED_DIFF, SUPPRESSIONS, PROJECT_CONTEXT)
- Audit context check (MANDATORY when context is missing)

Pass `PROJECT_CONTEXT`, `PROJECT_GUIDELINES`, `FRAMEWORK`, `SOURCE_DIRS`, `GUIDELINE_MATCHES`, and `DECIDED_TRADEOFFS` (intent docs/ADRs, derivation in `references/scope-and-pre-checks.md`) to all subagents. Only the **triage agent** gets the `UNIFIED_DIFF` for hotspot determination — workers get only their assigned hotspots instead of the diff (see Phase 2 Step C).

---

## Phase 2: Audit loop

Maximum **{MAX_RUNDEN} rounds** (from Phase 0.5). Convergence check: if `Critical + Important` of the current round does NOT decrease AND `RUNDE >= 2`, abort the loop with `NO_CONVERGENCE`.

Initialize: `RUNDE = 1`, `BEREITS_GEFIXT = []`, `FINDINGS_VORHERIGE_RUNDE = null`.

### Procedure AUDIT_RUNDE

**Step A — Announcement + todos**

Output: `Audit round {RUNDE}/{MAX_RUNDEN}`. TodoWrite: `Dispatch subagents` (in_progress), `Fix findings` (pending).

**Step B — Update scope (from round 2)**

`collect-scope.sh` again. `ALLE_DATEIEN` and `FRONTEND_DATEIEN` stay identical. The diff again goes only to triage if it runs again (see C.0). Workers continue to get only hotspots.

**Step B.5 — Incremental cache**

```bash
echo "$ALLE_DATEIEN" | tr '\n' '\0' | xargs -0 bash "$AUDIT_BIN/cache-check.sh"
```

`CACHED_FILES` are removed from the triage input. `CACHED_FINDINGS` are carried over. Helps mainly between audit runs.

**Step B.6 — Wave HEAD pinning (EVERY round, before dispatch)**

```bash
WAVE_HEAD=$(git rev-parse HEAD)
[ "$WAVE_HEAD" = "$AUDIT_BASE_HEAD" ] || echo "WARN: HEAD drift before wave (base $AUDIT_BASE_HEAD, now $WAVE_HEAD)"
```

On drift: re-run `collect-scope.sh` and confirm the new base BEFORE dispatching — do not wait for the Phase 4 drift check (a parallel session committing mid-audit otherwise invalidates worker findings silently). Pass `WAVE_HEAD` into every worker briefing (placeholder in `agents/prompt-template.md`); workers compare it against their own `git rev-parse HEAD` first and return `WORKER_RESULT=HEAD_DRIFT` instead of findings when it differs. A `HEAD_DRIFT` response → treat like the drift warning above: re-pin, re-collect scope, re-dispatch that wave once.

**Step C.0 — Triage agent (opt-in only, NOT the default)**

Routing comes from the deterministic floor in Step C.0.5. The LLM triage is **not dispatched** unless the run explicitly opts in (very large diffs where hotspot targeting saves real worker tokens). Reason: six recorded idle incidents, zero audit failures under floor routing — see `agents/0-triage.md`, "Routing is deterministic".

When opted in (round 1 only; from round 2 reuse `TRIAGE_RESULT`):

```
Agent(
  subagent_type: general-purpose,
  model: haiku,
  prompt: "Read agents/0-triage.md and run the triage.
    UNIFIED_DIFF: {UNIFIED_DIFF}
    FRONTEND_DATEIEN: {FRONTEND_DATEIEN}
    TRANSLATION_DATEIEN: {TRANSLATION_DATEIEN}
    FRAMEWORK: {FRAMEWORK}
    PROJECT_CONTEXT: {PROJECT_CONTEXT}
    SUPPRESSIONS: {SUPPRESSIONS}
    Return ONLY the JSON."
)
```

A JSON result refines the floor and adds hotspots (log `TRIAGE=REFINED`). Idle or malformed output changes nothing and gets NO re-prompt — the floor result already stands (log `TRIAGE=FLOOR_ONLY`).

**Step C.0.5 — Deterministic routing floor + transparency (EVERY round)**

**`PARTIAL_AUDIT=1` (Phase 0.6): skip C.0 AND C.0.5 entirely** — `ROUTING_RUN = SELECTED_DIMENSIONS`, print `Routing: user-scoped [{list}]` instead. The user's explicit selection is the routing; the floor must not force skipped dimensions back on.

This is the primary routing decision, not a safety net. It derives run/skip from git file signals alone:

```bash
printf '%s' '{TRIAGE_RESULT_JSON}' | bash "$AUDIT_BIN/check-skips.sh" "{FRAMEWORK}"
```

It derives file signals itself from git and overrides obvious wrong skips (frontend → `a11y`/`ui_design`/`ux`; translation → `copy`/`typography`; migration → `architecture`; code → `code_quality`/`security`; rules in the script) and returns `ROUTING_RUN` (the floor, plus triage additions when triage was opted into), `ROUTING_SKIPPED`, `ROUTING_OVERRIDE`, and a `Routing:` line. **MANDATORY:** print the `Routing:` line in the chat every round and add it to the audit log under `## Routing` at the end of the loop (one line per round); dispatch (Step C) uses `ROUTING_RUN`. The floor runs in EVERY round (cheap and deterministic).

**Step C — Dispatch specialized subagents in parallel**

Dispatch only agents from `ROUTING_RUN` (Step C.0.5: the deterministic floor, refined by triage only if it was opted into). Security almost always. All non-skipped agents in EVERY round.

Dispatch in **one message block** via the Agent tool. Pass ONLY:
- `TRIAGE_SUMMARY` (1-2 lines)
- `HOTSPOTS` (marked locations, exact file:line)
- `DATEILISTE` + `GUIDELINE_MATCHES` (for orientation; the worker loads only the listed guidelines, see prompt-template)

**NO UNIFIED_DIFF.** Workers read code via the Read tool if needed (max 5 files per agent per round).

**Idle watchdog (applies to ALL dispatched agents — workers, fix agents, verifiers):** an agent that goes idle WITHOUT having delivered its report (idle notification but no findings/FIX_RESULT message) gets exactly ONE automatic re-prompt via SendMessage ("You went idle without delivering your findings/report. Send it now via SendMessage to \"main\" in the requested format."). Still nothing after that → failure path per agent type: **worker** → note in the audit log, continue without the dimension; **fix agent** → check `git diff` on its files first (changes present = APPLIED + mandatory verifier), otherwise re-dispatch once; **verifier** → treat as `RECOMMEND=patch` (fix stays, finding carries to next round). Do not wait indefinitely and do not re-prompt more than once (2026-07-09: three agents needed manual nudging in one run).

The triage agent is deliberately NOT in this list: it is opt-in, gets no re-prompt, and its silence is a non-event because the deterministic floor already decided the routing (log `TRIAGE=FLOOR_ONLY`).

**Model override on escalation:** if `HEAVY_REASONING_OVERRIDE=opus` from Phase 1 is set (LARGE diff), dispatch Agent 1 (Architecture) and Agent 2 (Security) explicitly on Opus. Other agents use their `agents/*.md` default.

| # | Agent | Short name |
|---|---|---|
| 1 | `agents/1-architecture.md` | Architecture & Code Reuse |
| 2 | `agents/2-security.md` | Security |
| 3 | `agents/3-performance.md` | Performance |
| 4 | `agents/4-code-quality.md` | Code Quality |
| 5 | `agents/5-seo.md` | SEO |
| 6 | `agents/6-a11y.md` | A11y (WCAG) |
| 7 | `agents/7-typography.md` | Typography |
| 8 | `agents/8-ui-design.md` | UI Design |
| 9 | `agents/9-ux.md` | UX Patterns |
| 10 | `agents/10-animation.md` | Animation |
| 11 | `agents/11-docs-sync.md` | Docs Sync & Style |
| 12 | `agents/12-copy.md` | Copy & UX-Writing |

Prompt template: `agents/prompt-template.md`, section "For /audit (diff-based)".

**Step D — Consolidate + deduplicate**

Same location flagged by multiple subagents → one finding, strictest classification wins.

Check yourself (round 1 only):
- Public pages / changelog (see Phase 3a)
- Tests: changed logic without tests?
- Mobile apps: `bash "$AUDIT_BIN/detect-mobile.sh"` → on match, impact from `references/mobile-impact.md`

(Note: docs sync runs as Agent 11 — no separate orchestrator check needed.)

Insert own findings as Important.

Output format:
```
## Audit Round {RUNDE}/2 — X files, Y commits since origin/{branch}

### Critical
- [Critical][Dimension] file:line — Description

### Important / Minor / Sauber
[same structure, tag matching the header]
```

**Step D.5 — Hallucination validator (MANDATORY before every fix)**

```bash
test -f "{datei}" || echo "HALLUCINATION: file missing"
[ "$(wc -l < "{datei}")" -ge "{zeile}" ] || echo "HALLUCINATION: line out of range"
```

External APIs/libraries: check with `grep -r` in the project whether imported. Filter out hallucinated findings. Output: `Validator: X/Y verified, Z hallucinated (discarded)`.

**Step E — Auto-fix**

Count verified Critical+Important. Save `FINDINGS_AKTUELLE_RUNDE`. Convergence check see above.

**0 Critical and 0 Important?** → `SAUBER`. Early exit (Minor never blocks push).

**Otherwise — confidence gate (scales with `CONFIDENCE_FLOOR` from Phase 0.5):**
- `floor=high` (low effort): fix only `high`, the rest stays in the log (no issues, no re-verification — low effort is the fast mode)
- `floor=medium` (medium effort): fix `high`+`medium`. `low` → **re-verification** (see below)
- `floor=low` (high effort): fix all, `low` fixes get the warning marker `(LOW CONFIDENCE FIX)`

**Re-verification for low-confidence (medium effort):** the orchestrator reads the affected location specifically (Read tool). Finding confirmed → treat like `medium` (fix). Not confirmable → discard + `patterns-store.sh dismissed` — an unconfirmed finding does NOT belong in the issue tracker.

**From here on, open points are ONLY:** genuine decision points (architecture tradeoffs, behavior changes, scope questions) that an agent is not allowed to decide. Everything else gets fixed or discarded.

**Self-regression vs. pre-existing (prioritization):** if a finding is on a line that was changed in the current branch diff (`git blame`/diff comparison), it's a **self-regression** — ALWAYS fix, never park, even if it looks like a decision point (the branch introduced the problem). Only findings on unchanged, pre-existing lines may be parked as an open point.

**HARD RULE: the orchestrator NEVER edits code files itself.** Every code fix goes through a fix agent (Sonnet). Edits by the orchestrator on Opus cost a multiple.

**Allowed orchestrator edits:** `.claude/audits/*.md`, `CLAUDE.md` audit context draft, `suppressions.json` (with user consent), changelog files.

**Verify-by-measurement (perf) — baseline:** if the round contains a `[Performance]` finding and `PERF_MEASURE_CMD` is set, measure the baseline once BEFORE the fix agent dispatch: `eval "$(bash "$AUDIT_BIN/perf-measure.sh" --run "$PERF_MEASURE_CMD")"; PERF_BASELINE="$PERF_METRIC"`. Details: `references/perf-measurement.md`.

1. Group findings by file
2. Dispatch one `fix-agent.md` subagent (Sonnet) per file, in parallel
3. Multiple findings in the same file: bundle into one fix-agent call
3a. **Centralization findings (new shared utility):** if a finding extracts a duplicated pattern into a new `lib/*.js` / helper / trait, FIRST grep all occurrences (`grep -rn "{old_pattern}" src/`, adjust the glob to the project language) and pass ALL matching files to ONE fix agent (no parallel split, otherwise file collision). Mark as a centralization fix so the fix agent migrates every occurrence (see fix-agent.md special case).
3b. **Limit fix-wave size:** a fix assignment that touches >2 templates or contains a partial extraction gets split across multiple fix agents (except the centralization fix from 3a, which stays deliberately bundled) OR gets a report checkpoint: the fix agent MUST deliver an interim report before the final edits. Large assignments without a report checkpoint tend to silently abort, based on experience.
4. Collect results: `FIX_RESULT=APPLIED` counts as fixed. **If the agent report is missing entirely** (agent finishes without a `FIX_RESULT` line), do NOT assume the fix is lost: check `git diff` on the assignment's files — if changes are present, the fix counts as APPLIED and the fix-verifier run (E.5) is MANDATORY for these files (no silent skip).

4a. **Working-tree cross-check after EVERY parallel fix wave (MANDATORY, deterministic).** Do not trust `FIX_RESULT=APPLIED`. Build the set of files you assigned across all fix agents of this wave, then compare against reality:

```bash
git status --porcelain | awk '{print $2}' | sort > /tmp/audit-wave-actual.txt
# expected = every file assigned in this wave, plus files already modified before it
comm -13 /tmp/audit-wave-actual.txt /tmp/audit-wave-expected.txt   # assigned but NOT modified -> fix lost
```

Any assigned file that is NOT modified means the fix never landed or was destroyed by a sibling agent, regardless of what that agent reported. Re-dispatch it ALONE, with no other agent running, and state in its briefing that the previous attempt was destroyed.

Rationale (2026-07-22): a fix agent ran `git stash` + `git stash pop`, wiped a sibling's fix for the run's only Critical, and reported `APPLIED`. Only this cross-check surfaced it. Agent reports are a claim; `git status` is the evidence.
5. Minor: with `FIX_MINOR=1` (medium + high effort), fix all high/medium-confidence Minor findings, otherwise skip. Unfixed Minor findings stay ONLY in the audit log — never as an issue.
6. Not fixable because a decision is needed: as an open point with justification (see definition above). Not fixable for another reason (e.g. external system): discard + `patterns-store.sh dismissed {pattern}`
7. Add fixed issues to `BEREITS_GEFIXT`, into the learning store via `patterns-store.sh add`

**Step E.5 — Fix verification (MANDATORY for medium/high effort, SKIP for low)**

For every `FIX_RESULT=APPLIED`, dispatch a fix-verifier subagent (sonnet):

```
Agent(
  subagent_type: code-reviewer,
  model: sonnet,
  prompt: "Read agents/fix-verifier.md and evaluate the following fix.
    ORIGINAL_FINDING: {finding}
    FIX_DIFF: {diff_des_fix_agents}
    FIX_DATEI: {datei}
    PROJECT_GUIDELINES: {PROJECT_GUIDELINES}"
)
```

Evaluation of `FIX_VERIFIER_RESULT`:
- `RECOMMEND=keep` → fix stays, continue
- `RECOMMEND=patch` → fix stays, but the finding stays in `FINDINGS_NAECHSTE_RUNDE` as "Fix needs improvement"
- `RECOMMEND=revert` → `git checkout {FIX_DATEI}` (revert the fix), original finding goes back into the open list

Parallelization: all verifiers in one message block, max 10 in parallel. Latency add: ~3-5s per round.

**Token cost:** the verifier is Sonnet, costs about a third of a worker. For N fixes that's +N*0.3 worker cost. Worth it because wrong fixes are expensive later.

**Performance fixes — verify-by-measurement (when `PERF_MEASURE_CMD` is set and a baseline was taken in Step E):** re-measure after all fixes of the round: `eval "$(bash "$AUDIT_BIN/perf-measure.sh" --run "$PERF_MEASURE_CMD")"; PERF_AFTER="$PERF_METRIC"`. Deterministic verdict: `AFTER <= BASELINE` → perf fixes `keep` (log: `Verification: measured {BASELINE}->{AFTER}`); `AFTER > BASELINE` → regression, perf fixes as an open point + fix-verifier to narrow it down; `NA` → fallback to fix-verifier. Correctness/regression of other dimensions is still checked by the fix-verifier. Details: `references/perf-measurement.md`.

**MANDATORY — status line at the end of every round:**

```
AUDIT_STATUS: SAUBER | RUNDE {RUNDE}/{MAX_RUNDEN}
AUDIT_STATUS: FIXES_APPLIED | RUNDE {RUNDE}/{MAX_RUNDEN}
AUDIT_STATUS: NO_CONVERGENCE | RUNDE {RUNDE}/{MAX_RUNDEN}
```

### After each round

| Result | Action |
|---|---|
| `SAUBER` | Loop ends → Phase 2.5 (if multi-file) → Phase 3 |
| `FIXES_APPLIED` + RUNDE < {MAX_RUNDEN} | `RUNDE += 1`, repeat procedure. No user wait. |
| `FIXES_APPLIED` + RUNDE = {MAX_RUNDEN} | Loop ends → Phase 2.5 (if multi-file) → Phase 3 |
| `NO_CONVERGENCE` | Loop ends → Phase 3. Warning. |

---

## Phase 2.5: Cross-reference (multi-file features)

**Trigger:** number of changed files >= 3 AND `CONFIDENCE_FLOOR != high` (skip on low effort).

```bash
FILES_CHANGED_COUNT=$(echo "$ALLE_DATEIEN" | wc -l)
if [ "$FILES_CHANGED_COUNT" -ge 3 ] && [ "$CONFIDENCE_FLOOR" != "high" ]; then
  RUN_CROSS_REF=1
else
  RUN_CROSS_REF=0
  echo "Cross-Ref skipped (files=$FILES_CHANGED_COUNT, floor=$CONFIDENCE_FLOOR)"
fi
```

If `RUN_CROSS_REF=1`: dispatch a cross-ref subagent (sonnet):

```
Agent(
  subagent_type: code-reviewer,
  model: sonnet,
  prompt: "Cross-reference check of the changed files.
    DATEILISTE: {ALLE_DATEIEN}
    BEREITS_GEFIXT: {BEREITS_GEFIXT}
    PROJECT_GUIDELINES: {PROJECT_GUIDELINES}

    Check ONLY cross-file problems:
    - Services <-> UI: called incorrectly, signatures don't match
    - Models <-> Traits/Mixins: used incorrectly
    - Controller <-> View: mismatches (e.g. variable not passed to the view)
    - Consistency: same pattern project-wide (auth checks, cache keys, error handling)
    - A fix in file A could break file B (e.g. method rename)

    Output format like worker findings. Max 50 words per finding."
)
```

Findings are treated like Critical/Important (same confidence gate). Auto-fix follows the same rules (fix agent).

---

### Write audit log (after loop ends)

```bash
AUDIT_DIR="$(git rev-parse --show-toplevel)/.claude/audits"
mkdir -p "$AUDIT_DIR"
LOGFILE="$AUDIT_DIR/$(date +%Y-%m-%d_%H%M%S)-$(git branch --show-current | tr '/' '-').md"
```

Format template: `references/audit-log-template.md`. This way, multiple audits on the same day/branch don't overwrite each other.

**Update cache** (after loop ends):
```bash
echo '{"files": [...], "findings": [...]}' | bash "$AUDIT_BIN/cache-write.sh"
```
Only files that are clean after all fixes. Do NOT cache files with open points.

---

## Phase 3: Post-loop (changelog, tests, test plan, issues, display)

**MANDATORY:** now read `references/post-loop.md` and run 3a-3f sequentially. None of these subphases are optional. If a step doesn't apply (e.g. no visual files for 3d), log "n/a" explicitly instead of skipping.

| Subphase | What | Skip condition |
|---|---|---|
| 3a | Draft changelog entry (if user-facing) | only docs/tests/refactor without behavior change |
| 3b | Linter + static analysis | never |
| 3c | Diff-scoped tests | never |
| 3d | Manual test plan | when `VISUELL_RELEVANTE_DATEIEN` is empty |
| 3e | Show audit log in chat (markdown block) | never |
| 3f | **Open points: user decides → fix / issue / discard** | when there are no open points |

**3f:** open points (decision points only, see Phase 2 Step E) are presented to the user via AskUserQuestion — per point: **decide + fix now** / **defer as issue** / **discard**. Issues are created ONLY for what's explicitly deferred (with dedup). Minor findings NEVER get issues. Details in `references/post-loop.md` Section 3f.

---

## Phase 4: Pre-push behavior

**Check working-tree exclusivity (before marker):**

```bash
# Drift-Check gegen Basis aus Phase 1. Eigene Audit-Fixes zaehlen nicht als
# Drift (sie sind im Status-Hash erwartbar) — verglichen wird HEAD und ob
# Aenderungen auftauchen, die weder Basis noch Fix-Agents zuzuordnen sind.
[ "$(git rev-parse HEAD)" = "$AUDIT_BASE_HEAD" ] || echo "WARN: Fremd-Commit waehrend Audit, Diff-Basis instabil."
```

On deviation: warn (`Fremd-Commit/Index-Drift waehrend Audit, Diff-Basis instabil`), re-collect scope via `collect-scope.sh` and decide whether the findings still match the diff base. No automatic abort, but push only after deliberate confirmation of the new base.

**Hard block (never push):**
- `SECRET_SCAN_RESULT=FINDINGS` → abort push, remove secrets + clean history (BFG / `git filter-repo`).
- Unfixable Critical/Important, linter errors, tests red → `BLOCKED: Push aborted.` + list. NO marker file.

**`PARTIAL_AUDIT=1`: STOP here — no marker, no push.** Print: `Teilaudit ({SELECTED_DIMENSIONS}) — kein Push-Gate. Fuer den Push /audit ohne Argument ausfuehren.` Then continue with Phase 5 (learning runs normally).

**Everything fixed, tests green:**

**CRITICAL — marker and push NEVER in the same bash command.** The pre-push hook checks the command string for `git push` and blocks BEFORE the marker is written.

```bash
# Schritt 1 — Marker (kein `git push` im Befehl):
hash=$(echo -n "$PWD" | md5 2>/dev/null || echo -n "$PWD" | md5sum 2>/dev/null | cut -d' ' -f1)
touch "/tmp/claude-audit-passed-$hash"
```

```bash
# Schritt 2 — Push (separater Bash-Aufruf):
git push
# Multi-Repo: git -C /pfad push
```

Marker: TTL 30 min, is not deleted (multiple hooks check sequentially). Hash comes from `cwd` of the tool JSON. Multi-repo: `git -C /pfad push`, never `cd /pfad && git push`.

Then: print `Audit passed.`, continue with Phase 5 + 6.

---

## Phase 5: Learning

**Skip if `SKIP_LEARNING=1`** (low effort). Go directly to Phase 6.

The learning agent returns a **structured output**. **Subagents cannot write to `.claude/` paths** (hardcoded protection, even in the foreground and with bypassPermissions). The orchestrator parses the output and writes it itself — `.claude/audits/*.md` and `.claude/audits/suppressions.json` are among the allowed orchestrator edits.

**Step 1: dispatch the learning agent**

```
Agent(
  subagent_type: general-purpose,
  model: sonnet,
  prompt: "Read agents/learning-agent.md and run the process.
    PROJECT_ROOT={PROJECT_ROOT}
    AKTUELLES_LOG={Inhalt des gerade geschriebenen Audit-Logs}
    AUDIT_TYPE=audit",
  mode: bypassPermissions
)
```

Foreground (5-10s, not push-blocking).

**Step 2: parse the output**

The agent returns three blocks between `LEARNING_RESULT_START` and `LEARNING_RESULT_END`: `SUPPRESSIONS_TO_ADD` (JSON array), `LEARNING_LOG_ENTRY` (markdown up to `LEARNING_LOG_ENTRY_END`), and `TRENDS_BLOCK` (markdown between `TRENDS_BLOCK_START` and `TRENDS_BLOCK_END`). The suggestions for guideline/agent changes are included as `- [ ]` checkboxes in the `Vorgeschlagene Verbesserungen` section of the `LEARNING_LOG_ENTRY`.

**Step 3: the orchestrator writes**

- append `LEARNING_LOG_ENTRY` to `.claude/audits/learning-log.md` (or create it if this is the first audit)
- insert `TRENDS_BLOCK` at the top of `learning-log.md` or replace the existing block (do not append — it should stay a top snapshot)
- merge `SUPPRESSIONS_TO_ADD` into `.claude/audits/suppressions.json`. **If the file does not exist, create it first** (`{"suppressions": []}`) — any audit run, log, or finding that references a suppression MUST leave a valid `suppressions.json` behind; a dangling reference without the file is an orchestrator bug. **Dedup rule:** run the pattern of every new suppression through `bash "$AUDIT_BIN/normalize-suppression.sh"`, same normalization for existing suppressions. If both produce the same key → keep the existing one, discard the new one. This way "[Security] LIKE injection in scope" and "Like-wildcard injection (security)" are recognized as the same.
- show in the chat: number of new suppressions and number of new open backlog points. The user knows they'll be asked at the next `/audit` (or `/full-audit`).

---

## Phase 6: Create PR (after push)

```bash
# PreCompact-Marker entfernen — Audit abgeschlossen
CWD_HASH=$(pwd | md5 2>/dev/null || pwd | md5sum 2>/dev/null | cut -d' ' -f1)
rm -f "/tmp/claude-audit-in-progress-${CWD_HASH}"
```

Detail: `references/pr-creation.md`. Short version: check branch, collect commits, optional plan doc for the description, PR via `gh pr create`, print the URL. Errors don't block.
