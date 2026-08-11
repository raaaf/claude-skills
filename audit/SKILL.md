---
name: audit
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
  - SendMessage   # idle watchdog re-prompts dispatched agents
hooks:
  # Nested schema per the hooks docs (matcher + hooks[].type/command). There is no
  # CLAUDE_SKILL_DIR here, only CLAUDE_PROJECT_DIR (the AUDITED project, not this skill), so we
  # still probe the known install locations and fail OPEN (exit 0) when none matches -- a missing
  # install must not block every Bash call in an unrelated project. Detail: write-a-skill/references/hooks-pitfalls.md.
  PreToolUse:
    - matcher: "Bash"
      hooks:
        - type: command
          command: bash -c 'for c in "$HOME/.claude/skills/audit" "$HOME/.claude/skills/claude-skills/audit"; do [ -f "$c/hooks/pretooluse-bash.sh" ] && exec bash "$c/hooks/pretooluse-bash.sh"; done; exit 0'
---

# Audit: Review of all open changes

**EXECUTE IMMEDIATELY — do not explain, do not announce. Start directly with Phase 0.**

Anti-patterns / common mistakes in the loop: `references/anti-patterns.md`.

## Phase 0: Pre-flight checks (learning backlog + open issues/PRs)

Both checks (learning backlog question, open `audit-finding` issues + PR dedup context) are in `references/pre-flight-checks.md` — read and execute. Result: issues as findings for round 1 if applicable, `OPEN_PRS` as dedup context for Phase 3f. **Skip the whole phase** when ENV `AUDIT_SKIP_LEARNING_CHECK=1` is set (CI/batch runs), including the issue question.

## Phase 0.5: Effort configuration

The skill scales depth by `${CLAUDE_EFFORT}` (default `medium`) and by what the diff contains. `{MAX_RUNDEN}` below always means the value set here.

```bash
CLAUDE_EFFORT="${CLAUDE_EFFORT:-medium}"
case "$CLAUDE_EFFORT" in
  low)    MAX_RUNDEN=1; FIX_MINOR=0; SKIP_LEARNING=1; CONFIDENCE_FLOOR=high ;;
  high|xhigh) MAX_RUNDEN=3; FIX_MINOR=1; SKIP_LEARNING=0; CONFIDENCE_FLOOR=low ;;
  medium|*) MAX_RUNDEN=2; FIX_MINOR=1; SKIP_LEARNING=0; CONFIDENCE_FLOOR=medium ;;
esac
eval "$(bash "${CLAUDE_SKILL_DIR}/bin/classify-diff.sh")"   # DIFF_CLASS=prose|code
PROSE_GATE=0
if [ "$DIFF_CLASS" = "prose" ]; then MAX_RUNDEN=1; FIX_MINOR=0; CONFIDENCE_FLOOR=medium; PROSE_GATE=1; fi
echo "Effort=$CLAUDE_EFFORT | Diff=$DIFF_CLASS | Runden=$MAX_RUNDEN | FixMinor=$FIX_MINOR | ConfidenceFloor=$CONFIDENCE_FLOOR"
# PROSE_GATE=1 = Stoppregel (eine Runde, keine Minor-Fixes, nur Floor-Dimensionen). Bei DIFF_CLASS=prose references/prose-gate.md lesen.
```

| Level | Rounds | Fix Minor | Learning | Floor | D.7 verification |
|---|---|---|---|---|---|
| low | 1 | no | skip | high | skipped |
| medium (default) | 2 | yes | yes | medium | `medium` + `low` confidence |
| high / xhigh | 3 | yes | yes | low | every Critical/Important |
| any, `DIFF_CLASS=prose` | 1 | no | per effort (low: skip) | medium | `medium` + `low` confidence |

## Phase 0.6: Dimension scoping via argument (optional partial audit)

`$ARGUMENTS` (empty when none was given) may select dimensions: `/audit security`, `/audit performance,a11y`, the aliases `backend`/`frontend`/`design`, or `?` for a multi-select. If it does, set `PARTIAL_AUDIT=1` + `SELECTED_DIMENSIONS`, then read `references/partial-audit.md` and apply it; a partial audit never writes the push marker. Anything else stays a free-text scope hint (`PARTIAL_AUDIT=0`).

## Phase 1: Pre-flight & scope

```bash
AUDIT_BIN="${CLAUDE_SKILL_DIR}/bin"
AUDIT_AGENTS_DIR="${CLAUDE_SKILL_DIR}/agents"

# PreCompact-Schutz: blockiert Auto-Compaction waehrend des Audit-Runs
CWD_HASH=$(pwd | md5 2>/dev/null || pwd | md5sum 2>/dev/null | cut -d' ' -f1)
touch "/tmp/claude-audit-in-progress-${CWD_HASH}"

bash "$AUDIT_BIN/verify-agents.sh" "$AUDIT_AGENTS_DIR" || { echo "Audit abgebrochen — fehlende Agent-Dateien."; exit 1; }
for h in pretooluse-bash block-unsafe-push block-worktree-wide-git; do [ -f "${CLAUDE_SKILL_DIR}/hooks/$h.sh" ] || echo "WARNING: hook script missing: ${CLAUDE_SKILL_DIR}/hooks/$h.sh (push gate / worktree guard fails open by design, not blocking)"; done
bash "$AUDIT_BIN/collect-scope.sh"
bash "$AUDIT_BIN/detect-framework.sh"
bash "$AUDIT_BIN/pre-checks.sh"

# Deterministische Checks. Ergebniscodes -> Findings: Tabelle in
# references/scope-and-pre-checks.md, Abschnitt "Deterministic checks".
# Regel ueberall gleich: Treffer im Diff wird Finding, Treffer ausserhalb nur Hinweis.
if echo "$ALLE_DATEIEN" | grep -qE '(package(-lock)?\.json|composer\.(json|lock)|yarn\.lock|pnpm-lock\.yaml|requirements\.txt|pyproject\.toml|Podfile(\.lock)?|Package\.(swift|resolved)|pubspec\.(yaml|lock)|build\.gradle)'; then
  bash "$AUDIT_BIN/check-outdated.sh" "$(git rev-parse --show-toplevel)"
fi
bash "$AUDIT_BIN/check-i18n-keys.sh"
bash "$AUDIT_BIN/check-duplicate-array-keys.sh"
bash "$AUDIT_BIN/check-number-format-locale.sh"
bash "$AUDIT_BIN/check-swift-deprecations.sh"
bash "$AUDIT_BIN/check-test-count-drift.sh"
bash "$AUDIT_BIN/check-docs-path-drift.sh" "$BASE_REF"
# Deleted test files: the rule they pinned may have a successor that nobody pins.
git diff --name-status --diff-filter=DR "$BASE_REF" -- '*[Tt]est*' 2>/dev/null || true

# Project-Specific Guidelines (Override global)
PROJECT_GUIDELINES_FILE="$(git rev-parse --show-toplevel)/.claude/audit-guidelines.md"
PROJECT_GUIDELINES=""
if [ -f "$PROJECT_GUIDELINES_FILE" ]; then
  PROJECT_GUIDELINES=$(cat "$PROJECT_GUIDELINES_FILE")
  echo "Project guidelines: $PROJECT_GUIDELINES_FILE ($(wc -l < "$PROJECT_GUIDELINES_FILE") lines)"
fi
bash "$AUDIT_BIN/diff-size-gate.sh"

eval "$(bash "$AUDIT_BIN/perf-measure.sh" --detect)"   # PERF_MEASURE_CMD: Verify-by-Measurement (opt-in, evtl. leer)
GUIDELINE_MATCHES=$(bash "$AUDIT_BIN/match-guidelines.sh" "${CLAUDE_SKILL_DIR}/guidelines" 2>/dev/null)  # Guidelines die den Diff treffen; ohne applies_to = always
AUDIT_BASE_HEAD=$(git rev-parse HEAD)   # Working-Tree-Exklusivitaet, Check in Phase 4
AUDIT_BASE_STATUS_HASH=$(git status --porcelain | { md5 2>/dev/null || md5sum | cut -d' ' -f1; })
```

**A deleted test file is a coverage question, not a cleanup.** For every test file the `--diff-filter=DR` command above reports: name the rule it pinned, then decide which case you are in. (a) The rule is gone with the code → fine, note it. (b) The rule survived in a new shape and the diff pins it somewhere else → fine, name where. (c) The rule survived and nothing pins it → **Important**, and the fix is the successor test, not restoring the old file. Case (c) is the one that happened (2026-07-27): a redesign deleted the file pinning the old layout rule and shipped the new rule, which carried the whole surface, untested. The deletion looked like housekeeping because the old test genuinely no longer applied.

**An empty `origin/$DEFAULT_BRANCH..HEAD` is not "nothing to audit."** For projects with a manual
deploy step, pushed-but-not-deployed is the normal state, not an edge case: the work sits on the
remote and production has never seen it. Auditing an empty diff certifies nothing while releasing
every commit behind it. The base to fall back to is the last commit certified by an audit, taken
from the `## Scope` block of the newest log in `.claude/audits/`, not `HEAD~20` and not the
resolved `BASE_REF`. State the substituted base in the log's own `## Scope` block, because every
finding afterwards is relative to it.

**WIP/stale-snapshot scope check (before Phase 2):** look at `git status --porcelain` + `git diff --stat`. Does the working tree contain files that clearly do NOT belong to the task currently being discussed (pre-existing WIP from another line of work, foreign uncommitted edits, stale snapshots)? Then do NOT silently audit them along with the rest — ask the user via `AskUserQuestion` about the scope: **only the session/task changes** vs. **entire working tree**. Heuristic for "doesn't belong": files in completely different modules than the rest of the diff, or files that were already `M` before the session started. When in doubt, ask — an audit on someone else's WIP produces findings on code the user isn't even working on right now.

Evaluating the script outputs (diff-size gate OK/LARGE/HUGE, pre-checks for secrets/lockfile/binary artifacts, deriving `ALLE_DATEIEN`/`FRONTEND_DATEIEN`/`UNIFIED_DIFF`/`SUPPRESSIONS`/`PROJECT_CONTEXT`, the mandatory audit-context check, and the deterministic-check result table): `references/scope-and-pre-checks.md`.

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

# Uncommitted drift, too: a parallel session editing the shared working tree changes what
# the workers read WITHOUT moving HEAD. On 2026-08-06 another session rewrote eight files
# mid-audit (including two from the commit under review) and the workers reported on a
# roving-tabindex method that existed only as an uncommitted change, calling it pre-existing.
# The HEAD check above saw nothing, because HEAD had not moved.
WAVE_STATUS_HASH=$(git status --porcelain | { md5 2>/dev/null || md5sum | cut -d' ' -f1; })
[ "$WAVE_STATUS_HASH" = "$AUDIT_BASE_STATUS_HASH" ] || echo "WARN: working-tree drift before wave (uncommitted changes appeared or vanished since Phase 1)"
git status --porcelain   # print it: the diff decides whether it is a fix agent's own work or foreign
```

On HEAD drift: re-run `collect-scope.sh` and confirm the new base BEFORE dispatching — do not wait for the Phase 4 drift check (a parallel session committing mid-audit otherwise invalidates worker findings silently).

On working-tree drift in round 1 (before any fix agent ran, so nothing of it can be yours): treat it as a foreign session in the same tree. Do NOT dispatch. Report the file list with mtimes to the user and let them decide, because every finding from that point on describes code the user is not currently working on and a fix wave would collide with theirs. From round 2 on, subtract the files your own fix agents touched before judging. Pass `WAVE_HEAD` into every worker briefing (placeholder in `agents/prompt-template.md`); workers compare it against their own `git rev-parse HEAD` first and return `WORKER_RESULT=HEAD_DRIFT` instead of findings when it differs. A `HEAD_DRIFT` response → treat like the drift warning above: re-pin, re-collect scope, re-dispatch that wave once.

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

**`PARTIAL_AUDIT=1` (Phase 0.6): skip C.0 AND C.0.5 entirely** — `ROUTING_RUN = SELECTED_DIMENSIONS`, print `Routing: lief [{list}]; uebersprungen [alle uebrigen: user-scoped]` instead. The user's explicit selection is the routing; the floor must not force skipped dimensions back on.

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

**NO UNIFIED_DIFF.** Workers read code via the Read tool if needed (max 5 files per agent per round). Dispatch every agent whose output this turn must consume (workers, finding verifiers, fix agents, fix verifiers, cross-ref) with `run_in_background: false`; background is the default since v2.1.198 and returns only in a later turn. The opt-in triage is the exception, its silence is a non-event.

**Idle watchdog (applies to ALL dispatched agents — workers, fix agents, verifiers):** an agent that goes idle WITHOUT having delivered its report (idle notification but no findings/FIX_RESULT message) gets exactly ONE automatic re-prompt via SendMessage ("You went idle without delivering your findings/report. Send it now via SendMessage to \"main\" in the requested format."). Still nothing after that → failure path per agent type: **worker** → note in the audit log, continue without the dimension; **fix agent** → check `git diff` on its files first (changes present = APPLIED + mandatory verifier), otherwise re-dispatch once; **verifier** → treat as `RECOMMEND=patch` (fix stays, finding carries to next round). Do not wait indefinitely and do not re-prompt more than once (2026-07-09: three agents needed manual nudging in one run).

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

**Liveness is a briefing contract, not a timer.** The Agent tool has no timeout, so nothing outside the agent can cut it off; the only lever is the instruction it carries. Every briefing therefore states a hard tool-call budget and the duty to send a partial report on reaching it (`agents/prompt-template.md` carries this for workers, `fix-agent.md` for fix agents). Keep that line in any briefing you write by hand. A silent agent is then a contract violation you can act on immediately via the failure paths above, instead of a wait of unknown length.

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

Check yourself (round 1 only; in `PARTIAL_AUDIT=1` only the checks whose governing dimension is selected — mapping in `references/partial-audit.md`):
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

### Unverified
- [Dimension] file:line: description. Verification inconclusive: {REASON from D.7}
```

The `Unverified` section holds the `UNCERTAIN` verdicts from Step D.7. It exists so that a finding nobody could settle stays visible instead of disappearing between "not fixed" and "not reported". Empty section → omit the heading.

**Step D.5 — Hallucination validator (MANDATORY before every fix)**

```bash
test -f "{datei}" || echo "HALLUCINATION: file missing"
[ "$(wc -l < "{datei}")" -ge "{zeile}" ] || echo "HALLUCINATION: line out of range"
```

External APIs/libraries: check with `grep -r` in the project whether imported. Filter out hallucinated findings. Output: `Validator: X/Y verified, Z hallucinated (discarded)`.

D.5 is mechanical only: it proves the file and the line exist, never that the problem does. The semantic check is D.7.
**Step D.7: finding verification (fresh context, BEFORE any fix)**

Workers report for coverage and include findings they are unsure about (see `agents/prompt-template.md`); D.7 is the stage that pays for that. Refuting happens here, by a fresh verifier that never saw the finding produced, because self-critique by the finder or the consolidating orchestrator is weaker, and refuting a wrong finding costs a fraction of applying a wrong fix and reverting it.

**Selection (scales with `CONFIDENCE_FLOOR`):**

| Floor | Effort | Goes through D.7 |
|---|---|---|
| `high` | low | nothing (step skipped entirely, fast mode) |
| `medium` | medium | every Critical/Important finding with `confidence: medium` or `low` |
| `low` | high/xhigh | every Critical/Important finding, `high` confidence included |

Minor findings never go through D.7: they are only fixed at high/medium confidence anyway, and verifying them costs more than the fix.

**At `floor=low`, confirming a finding yourself by grep is not a substitute for D.7**, however mechanical it looks ("is the key I just deleted gone?", "does that line really say what the worker claims?"). A verifier costs one grep there too, so there is no cost advantage that would justify the skip. The run that produced this rule waved five of six Important findings through on self-confirmation and sent only the one product judgement to a verifier — which is exactly where the single genuine misjudgement of the set sat. Mechanical certainty is not the property that predicts a correct finding.

**Dispatch** one `finding-verifier.md` subagent (sonnet) per finding, all in one message block, max 10 in parallel:

```
Agent(
  subagent_type: code-reviewer,
  model: sonnet,
  prompt: "Read agents/finding-verifier.md and execute it.
    FINDING: {severity} {file:line} (confidence: {level}) {description}
    DIMENSION: {dimension}
    DIFF_CONTEXT: {diff hunk of the finding, if available}
    PROJECT_GUIDELINES: {PROJECT_GUIDELINES}
    DECIDED_TRADEOFFS: {DECIDED_TRADEOFFS}",
  run_in_background: false
)
```

**Verdict handling:**

| `FINDING_VERDICT` | Action |
|---|---|
| `CONFIRMED` | goes to Step E, with `SEVERITY_CORRECTION` applied when it is not `none` + `patterns-store.sh recur {pattern}` |
| `REFUTED` | discarded before any fix + `patterns-store.sh dismissed {pattern}`, one log line with the verifier's `REASON`. Never becomes an issue. |
| `UNCERTAIN` | not fixed. Goes into the audit log under `### Unverified` with the `REASON`. A Critical `UNCERTAIN` additionally becomes an open point for the user. Never silently dropped. |

A missing or unparseable verifier reply counts as `UNCERTAIN`, never as `CONFIRMED`: an unanswered verification is not a pass.

**Feed the store DURING the run, not only at the final retro.** The `recur`/`dismissed` calls above are the orchestrator's job, right where the verdict is decided — not a step reserved for the learning agent's end-of-run pass over the finished log. At `floor=high`, D.7 is skipped entirely (see the effort table above), so there is no verdict to hang `recur` on: call it instead at Step E when the finding enters the fix queue (same `{pattern}` string used for `patterns-store.sh add`, see Step E.7). Either way, `patterns.json` should already show this run's patterns by the time the learning agent reads it — the learning agent's own trends-block pass then only reports `recurrences`, it does not populate them from scratch.

Print after the step: `Verification: {X} confirmed, {Y} refuted, {Z} uncertain (of {N})`.

**Step E — Auto-fix**

Count confirmed Critical+Important (D.7 output; without D.7, at low effort, the D.5-validated findings). Save `FINDINGS_AKTUELLE_RUNDE`. Convergence check see above.

**0 Critical and 0 Important?** → `SAUBER`. Early exit (Minor never blocks push).

**Otherwise — confidence gate (scales with `CONFIDENCE_FLOOR` from Phase 0.5):**
- `floor=high` (low effort): fix only `high`, the rest stays in the log (no issues, no verification stage, low effort is the fast mode)
- `floor=medium` (medium effort): `high` goes straight to fix, `medium`+`low` go through Step D.7 first
- `floor=low` (high/xhigh effort): every Critical/Important finding goes through Step D.7, regardless of confidence

**From here on, open points are ONLY:** genuine decision points (architecture tradeoffs, behavior changes, scope questions) that an agent is not allowed to decide. Everything else gets fixed or discarded.

**Self-regression vs. pre-existing (prioritization):** if a finding is on a line that was changed in the current branch diff (`git blame`/diff comparison), it's a **self-regression** — ALWAYS fix, never park, even if it looks like a decision point (the branch introduced the problem). Only findings on unchanged, pre-existing lines may be parked as an open point.

**HARD RULE: the orchestrator NEVER edits code files itself.** Every code fix goes through a fix agent (Sonnet). Edits by the orchestrator on Opus cost a multiple.

**Allowed orchestrator edits:** `.claude/audits/*.md`, `CLAUDE.md` audit context draft, `suppressions.json` (with user consent), changelog files.

**The worktree-wide git ban applies to the orchestrator too, not just to fix agents.** `fix-agent.md`
forbids its subagents every destructive worktree-wide git command because parallel agents share one
working tree. The orchestrator shares that same tree — and the tree also holds the user's own
uncommitted work. On 2026-08-03 the orchestrator ran exactly the command it forbids its subagents,
in a tree with parallel writers, for exactly the reason that applied to it.

When you need a clean HEAD baseline (lint comparison, render comparison, "was this red before my
fixes?"), do NOT touch the shared tree. Use a throwaway worktree instead:

```bash
TMP=$(mktemp -d)
git worktree add --detach "$TMP" HEAD
# ... measure inside "$TMP" ...
git worktree remove --force "$TMP"
```

For a single file, `git show HEAD:<path>` is enough and touches nothing. Note that
`hooks/pretooluse-bash.sh` matches on the command string, so it also blocks a Bash call that merely
*writes about* these commands — author such documentation with the Edit/Write tool.

**Verify-by-measurement (perf) — baseline:** if the round contains a `[Performance]` finding and `PERF_MEASURE_CMD` is set, measure the baseline once BEFORE the fix agent dispatch: `eval "$(bash "$AUDIT_BIN/perf-measure.sh" --run "$PERF_MEASURE_CMD")"; PERF_BASELINE="$PERF_METRIC"`. Details: `references/perf-measurement.md`.

1. Group findings by file
2. Dispatch one `fix-agent.md` subagent (Sonnet) per file, in parallel
3. Multiple findings in the same file: bundle into one fix-agent call
3a. **Centralization findings (new shared utility):** if a finding extracts a duplicated pattern into a new `lib/*.js` / helper / trait, FIRST grep all occurrences (`grep -rn "{old_pattern}" src/`, adjust the glob to the project language) and pass ALL matching files to ONE fix agent (no parallel split, otherwise file collision). Mark as a centralization fix so the fix agent migrates every occurrence (see fix-agent.md special case).
3b. **Limit fix-wave size:** a fix assignment that touches >2 templates or contains a partial extraction gets split across multiple fix agents (except the centralization fix from 3a, which stays deliberately bundled) OR gets a report checkpoint: the fix agent MUST deliver an interim report before the final edits. Large assignments without a report checkpoint tend to silently abort, based on experience.
4. Collect results: `FIX_RESULT=APPLIED` counts as fixed. **If the agent report is missing entirely** (agent finishes without a `FIX_RESULT` line), do NOT assume the fix is lost: check `git diff` on the assignment's files — if changes are present, the fix counts as APPLIED and the fix-verifier run (E.5) is MANDATORY for these files (no silent skip).

4a. **Working-tree cross-check after EVERY parallel fix wave (MANDATORY, deterministic).** Do not trust `FIX_RESULT=APPLIED`. Build the set of files you assigned across all fix agents of this wave, then compare against reality:

```bash
ACTUAL=$(mktemp)
EXPECTED=$(mktemp)

# Expected = every file assigned to a fix agent in this wave (Step E, "group findings by
# file"). Populate WAVE_ASSIGNED_FILES yourself, one path per line, BEFORE this runs --
# it is orchestrator-known state, not carried over from any earlier command.
echo "$WAVE_ASSIGNED_FILES" | sort > "$EXPECTED"
git status --porcelain | sed 's/^...//; s/^.* -> //; s/^"//; s/"$//' | sort > "$ACTUAL"   # strip status+space, rename source, and git's quoting of paths with spaces
comm -13 "$ACTUAL" "$EXPECTED"   # assigned but NOT modified -> fix lost

# Stash-Check: ein Eintrag hier heisst, ein Fix-Agent hat trotz Verbot gestasht.
# Unabhaengig von jeder Selbstauskunft — der 2026-07-22-Verstoss wurde nur durch
# die Selbstmeldung des Agents entdeckt, dieser Check findet ihn deterministisch.
git stash list | grep -q . && echo "STASH DETECTED: Welle ungueltig"
```

`STASH DETECTED` → wait until every agent of the wave is idle, `git stash pop` to restore the erased work, re-run the cross-check above, and re-dispatch any still-missing assignment ALONE.

Any assigned file that is NOT modified means the fix never landed or was destroyed by a sibling agent, regardless of what that agent reported. Re-dispatch it ALONE, with no other agent running, and state in its briefing that the previous attempt was destroyed.

5. Minor: with `FIX_MINOR=1` (medium + high/xhigh effort), fix all high/medium-confidence Minor findings, otherwise skip. Unfixed Minor findings stay ONLY in the audit log — never as an issue.
6. Not fixable because a decision is needed: as an open point with justification (see definition above). Not fixable for another reason (e.g. external system): discard + `patterns-store.sh dismissed {pattern}`
7. Add fixed issues to `BEREITS_GEFIXT`, into the learning store via `patterns-store.sh add`. At `floor=high`, also call `patterns-store.sh recur {pattern}` here (same string) — D.7 was skipped for this run, so this is the only point a self-confirmed finding gets counted.

**Step E.5 — Fix verification (MANDATORY for medium/high/xhigh effort, SKIP for low)**

For every `FIX_RESULT=APPLIED`, dispatch a fix-verifier subagent (sonnet):

```
Agent(
  subagent_type: general-purpose,
  model: sonnet,
  prompt: "Read agents/fix-verifier.md and evaluate the following fix.
    ORIGINAL_FINDING: {finding}
    FIX_DIFF: {diff_des_fix_agents}
    FIX_DATEI: {datei}
    PROJECT_GUIDELINES: {PROJECT_GUIDELINES}",
  run_in_background: false
)
```

Evaluation of `FIX_VERIFIER_RESULT`:
- `RECOMMEND=keep` → fix stays, continue
- `RECOMMEND=patch` → fix stays, but the finding stays in `FINDINGS_NAECHSTE_RUNDE` as "Fix needs improvement"
- `RECOMMEND=revert` → `git checkout {FIX_DATEI}` (revert the fix), original finding goes back into the open list

Parallelization: all verifiers in one message block, max 10 in parallel. Latency add: ~3-5s per round.

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

**Trigger:** changed files >= 3 AND `CONFIDENCE_FLOOR != high` (skipped on low effort). Read
`references/cross-reference.md` and execute it — it computes the trigger and, when it fires, dispatches
the cross-ref subagent (sonnet, cross-file problems only). Its findings run through the same confidence
gate, the same Step D.7 verification and the same fix path as worker findings.

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

**Re-fire the baseline check HERE, immediately before commit and push.** It runs between rounds, and that is where it was assumed to be enough — but every fix wave lands after the last inter-round check, so the window that matters most is the one that was never re-checked. The check below is that re-fire; do not skip it because "it was green two rounds ago".

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

**Staging: never `git add -A`, never `git add .`.** When this run commits its own fix waves, stage the verified files by name — the ones the fix agents reported and the verifier confirmed. A wildcard add sweeps in whatever else the working tree happens to hold: a file another session wrote, a scratch file, or (2026-07-27, real) a test file created seconds after the verification run, committed unseen and pushed to TestFlight without ever having been executed. `git diff --staged --stat` before the commit, and every line in it is a file this audit verified.

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

Skipped entirely when `SKIP_LEARNING=1` (low effort): go directly to Phase 6. Otherwise read `references/learning-phase.md` and execute it: dispatch the learning agent with
`run_in_background: false` (mandatory, the default has been background since v2.1.198 and a
backgrounded agent returns after this turn is over), parse its three output blocks, and write
learning-log, trends block and suppressions yourself. Subagents cannot write under `.claude/`.

## Phase 6: Create PR (after push)

```bash
# PreCompact-Marker entfernen — Audit abgeschlossen
CWD_HASH=$(pwd | md5 2>/dev/null || pwd | md5sum 2>/dev/null | cut -d' ' -f1)
rm -f "/tmp/claude-audit-in-progress-${CWD_HASH}"
```

Detail: `references/pr-creation.md`. Short version: check branch, collect commits, optional plan doc for the description, PR via `gh pr create`, print the URL. Errors don't block.
