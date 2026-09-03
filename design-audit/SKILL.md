---
name: design-audit
description: "Purely visual design audit that dissects the entire frontend surface (or a scoped path) file by file: typography, UI visual design incl. OKLCH color system, visual UX patterns, animation, visual a11y (contrast, focus, target sizes). Reports defects AND gated elevation opportunities (consistency, distinctiveness, polish; optional Mobbin reference grounding), then lets the user pick what gets fixed — nothing is changed without selection. Use when the user runs /design-audit or wants the existing UI made better, more consistent, more distinctive. NOT for ARIA/semantics/copy/SEO (use /audit), NOT a push gate, NOT a live-site check (code only)."
when_to_use: "/design-audit, Design-Audit, UI-Qualitaet pruefen, Design konsistenter machen, Frontend polieren, UI einzigartiger machen"
argument-hint: "[optional: path scope, e.g. resources/views/checkout]"
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
  - Skill         # optional second opinion from design skills in Phase 3
---

# Design Audit: Elevate the Existing Frontend

**Start directly with Phase 0; there is nothing to confirm first.**

> **Architecture note:** This skill has NO worker agents of its own. It uses the definitions from `../audit/agents/*.md` and the guidelines from `../audit/guidelines/*.md` (single source of truth — edit there). Unlike /audit it is NOT diff-scoped and NOT a push gate: it sweeps the whole frontend surface, reports, and fixes only what the user selects.

**Mission:** make the existing UI better, more consistent, more distinctive, smarter. This skill is **100% visual**: layout, spacing, type, color, surfaces, motion, visual hierarchy, visual consistency. Non-visual concerns (ARIA/semantics, copy wording, SEO, performance, security) are out of scope here — /audit and /full-audit cover them. And it **dissects**: every file in scope is read and taken apart against the checklists; sampling or skimming is a failed run, "this view is fine" is only valid after the view was actually dissected.

Two finding classes, kept strictly separate:

- **[Defect]** — violates a guideline or is internally inconsistent (wrong contrast math, mixed spacing scales, missing reduced-motion, three button variants for one function). Objective, checkable.
- **[Elevation]** — nothing is broken, but a concrete opportunity exists to make the product feel more crafted or more distinctive (optical alignment, materials/translucency, micro-interaction on a rare high-emotion moment, replacing generic AI-slop patterns with something ownable). Subjective, must survive the Gate (below).

## Phase 0: Pre-flight — paths + effort

```bash
# Resolve audit skill root — same candidate logic as full-audit.
AUDIT_ROOT=""
for candidate in \
  "$(dirname "${CLAUDE_SKILL_DIR:-/nonexistent}")/audit" \
  "$HOME/.claude/skills/audit" \
  "$HOME/.claude/skills/claude-skills/audit"; do
  [ -n "$candidate" ] && [ -d "$candidate/agents" ] && { AUDIT_ROOT="$candidate"; break; }
done
[ -z "$AUDIT_ROOT" ] && { echo "ERROR: audit skill not found. Install audit alongside design-audit."; exit 1; }

AUDIT_AGENTS="$AUDIT_ROOT/agents"
AUDIT_BIN="$AUDIT_ROOT/bin"
AUDIT_GUIDELINES="$AUDIT_ROOT/guidelines"

bash "$AUDIT_BIN/verify-agents.sh" "$AUDIT_AGENTS" || { echo "ERROR: missing agent files in $AUDIT_AGENTS."; exit 1; }

# PreCompact protection is WAVE-scoped (same marker family as /audit): no marker here. Claimed at
# the Phase 2 dispatch, released once Phase 3 has written the report to .claude/audits/ — from
# there the selection/fix phases can survive a compaction. Rationale + the first attempt's
# defects: $AUDIT_ROOT/references/context-budget.md. Hash inline at every site (defect 1).
AUDIT_TMP="${TMPDIR:-/tmp}/claude-audit-$(pwd | md5 2>/dev/null || pwd | md5sum 2>/dev/null | cut -d' ' -f1)"
if mkdir -p "$AUDIT_TMP" 2>/dev/null && [ -w "$AUDIT_TMP" ]; then
  echo "AUDIT_TMP=$AUDIT_TMP"
else
  # Fallback = run-scoped: Marker EINMAL jetzt claimen, Release erst am Run-Ende-Cleanup.
  echo "WARN: AUDIT_TMP nicht beschreibbar — wave-shared-Datei auslassen, Konstanten inline briefen, Marker laeuft run-scoped"
  touch "/tmp/claude-audit-in-progress-$(pwd | md5 2>/dev/null || pwd | md5sum 2>/dev/null | cut -d' ' -f1)"
fi

# Run-ledger start marker (see run-log.sh header) — before any real work
bash "$AUDIT_BIN/run-log.sh" --start --skill design-audit

CLAUDE_EFFORT="${CLAUDE_EFFORT:-high}"
case "$CLAUDE_EFFORT" in
  # BATCH_SIZE == the worker's file-read budget (BATCH_MAX 15, scope-context-batching.md).
  # It used to be 40-60 when five dimension agents shared a batch; ONE w3 worker per batch
  # cannot read more files than its budget allows — a bigger number here silently becomes
  # sampling, which this skill explicitly forbids. More files => more parallel batches.
  low)    MAX_ELEVATION=3;  BATCH_SIZE=15; VERIFY_FIXES=0 ;;
  medium) MAX_ELEVATION=5;  BATCH_SIZE=15; VERIFY_FIXES=1 ;;
  high|*) MAX_ELEVATION=7;  BATCH_SIZE=15; VERIFY_FIXES=1 ;;
esac
echo "Effort=$CLAUDE_EFFORT | MaxElevation=$MAX_ELEVATION | BatchSize=$BATCH_SIZE"
```

## Phase 1: Scope — the frontend surface

```bash
PROJECT_ROOT=$(git rev-parse --show-toplevel 2>/dev/null || pwd)
# Capture and parse rather than just printing: the native scope filter below
# BRANCHES on $PLATFORM, and an unset variable there would apply the native
# path narrowing to a web project and gut its scope. SOURCE_DIRS is a
# per-directory %q-quoted, space-joined list and stays unused here, so pull the
# keys out individually instead of eval'ing the whole output.
FW_OUT="$(bash "$AUDIT_BIN/detect-framework.sh")"
FRAMEWORK=$(printf '%s\n' "$FW_OUT" | sed -n 's/^FRAMEWORK=//p')
PLATFORM=$(printf '%s\n' "$FW_OUT" | sed -n 's/^PLATFORM=//p')
echo "FRAMEWORK=$FRAMEWORK PLATFORM=$PLATFORM"

# Frontend surface: whole repo (tracked files), NOT the diff.
# Optional argument narrows to a path prefix.
SCOPE_PREFIX="$ARGUMENTS"
# Visual surface only — no lang/i18n files (copy is out of scope here).
FRONTEND_FILES=$(git -C "$PROJECT_ROOT" ls-files -- ${SCOPE_PREFIX:+"$SCOPE_PREFIX"} \
  | grep -E '\.(css|scss|sass|less|styl|html|blade\.php|vue|svelte|astro|jsx|tsx|swift|kt|dart)$|tailwind\.config' \
  | grep -vE '(^|/)(node_modules|vendor|dist|build|\.next|storage)/' \
  | grep -vE '(^|/)audit/evals/fixtures/')
# Native projects: the extension list is not a scope.
#
# In a web framework a frontend extension IS the surface — nothing but a view
# ever ends in .vue, .blade.php or .tsx. Swift, Kotlin and Dart have no such
# split: services, models, providers and tests share one extension with the
# views, so the glob above hands a "frontend" audit the entire source tree. On
# 2026-08-13 that was 197 files where the visual surface was 59, and the
# orchestrator narrowed it by hand. Narrow it here instead, by path.
if [ "$PLATFORM" != "web" ]; then
  FRONTEND_FILES=$(printf '%s\n' "$FRONTEND_FILES" \
    | grep -E '(^|/)(Views?|Components?|Screens?|UI|Widgets?|DesignSystem|Theme|Styles?)/|(^|/)[A-Za-z]+(App|View|Screen|Widget)\.(swift|kt|dart)$' \
    | grep -vE '(^|/)([Tt]ests?|Models?|Services?|Repositories|Networking|Persistence|Data)/' || true)
fi

FRONTEND_COUNT=$(echo "$FRONTEND_FILES" | grep -c . || echo 0)
echo "Frontend surface: $FRONTEND_COUNT files"
[ "$FRONTEND_COUNT" -eq 0 ] && { echo "Keine Frontend-Dateien im Scope — nichts zu auditieren."; exit 0; }   # kein Marker-Cleanup noetig: geclaimt wird erst in Phase 2
```

The path filter is a heuristic, not a contract: a project that keeps views somewhere else loses them here. Print the resulting list and eyeball it before Phase 2 — a count that collapses to a handful on a real app means the convention did not match, and the fix is to widen the pattern for that project, not to audit five files and call the surface covered.

**Context for all workers (assemble now):**

- `PROJECT_CONTEXT`: `## Audit Context` from the project's CLAUDE.md (awk extract, same as /audit).
- `PROJECT_GUIDELINES`: `.claude/audit-guidelines.md` if present (overrides globals).
- `DECIDED_TRADEOFFS`: intent docs glob per `$AUDIT_ROOT/references/scope-and-pre-checks.md`. A documented design decision is never a Defect; drifting from it is.
- `SUPPRESSIONS`: `.claude/audits/suppressions.json` patterns if present.
- `DESIGN_GUIDELINES`: fixed list, no matcher needed (the dimension set is fixed): `typography.md`, `ui-visual-design.md`, `color.md`, `ui-animation.md`, `ui-ux-patterns.md`, `atomic-design.md`, `accessibility.md` (visual sections only — contrast, focus visibility, target size, preference queries); plus `native-mobile.md` when `PLATFORM != web`; plus `theme-fork.md` if referenced by the project. Deliberately NOT loaded: `copywriting.md`, `ui-audio.md`, `seo.md` — not visual.

**Batching:** if `FRONTEND_COUNT > BATCH_SIZE`, split `FRONTEND_FILES` into chunks of `BATCH_SIZE` (group by directory so views stay together) and run Phase 2 once per chunk, carrying `BEREITS_GEFUNDEN` (consolidated findings so far) into later chunks to avoid duplicates. Consistency checks (tokens, component variants) always get the FULL file list regardless of chunk.

## Phase 1.5: Surface coverage (fail-open)

The worker wave sees only files that exist — a missing 404 page, empty state, or cancel flow is invisible to it by construction. This phase asks the completeness question once, before dissection.

`SURFACE_TAXONOMY` = `${CLAUDE_SKILL_DIR:-$HOME/.claude/skills/design-audit}/references/surface-taxonomy.md`. If the file is missing, skip this phase silently — same report structure without it.

Dispatch ONE mapping agent (`subagent_type: general-purpose`, `model: sonnet`, `run_in_background: false`; no dedicated agent file, the briefing below is the full contract). Input: the frontend file list, the taxonomy file, and an instruction to read the project's route/navigation definitions itself (route files, app-router directories, nav components). Briefing rules: the taxonomy's "Expectation rules" section is binding — a surface is missing only when the domain clearly calls for it, uncertain entries are omitted. Output contract, one line each:

```
SURFACES_PRESENT: {taxonomy name} -> {entry files}
SURFACES_MISSING: {taxonomy name} -> {one line why this app's domain expects it}
```

Consumption:

- `SURFACES_PRESENT` becomes worker context: append the map to every Phase 2 briefing (which views form which surface — grounds cross-view consistency), and it selects the Mobbin core surfaces in Phase 2.5.
- Every `SURFACES_MISSING` entry is an **Elevation candidate** with purpose `completeness` (valid for surface-coverage candidates only), anchored `file:line` to the route/navigation file where the surface would attach — a missing surface has no file of its own, and the Phase 3 hallucination validator requires an existing anchor. It passes the normal Gate and competes for the `MAX_ELEVATION` cap. Never a Defect.

## Phase 2: Worker wave (fixed dimensions, no triage)

**Claim the compaction block (inline hash, released after the Phase 3 report is on disk) — and
RE-claim with the same command before every later agent dispatch inside the audit part (Phase 2.5
reference-verdict agents, Phase 3 finding-verifier wave): the hook's 45-minute stale window covers
the gap between two dispatches, not the whole audit part.**

```bash
touch "/tmp/claude-audit-in-progress-$(pwd | md5 2>/dev/null || pwd | md5sum 2>/dev/null | cut -d' ' -f1)"
```

Write the shared worker context (`PROJECT_CONTEXT`, `PROJECT_GUIDELINES`, `DECIDED_TRADEOFFS`,
`SUPPRESSIONS`, the frontend file list, the surface map) ONCE to
`{AUDIT_TMP}/wave-design-shared.md` — Write tool, literal path from Phase 0, no bash heredoc — and
pass that path in the briefings instead of inlining it per dimension (worker contract:
`$AUDIT_AGENTS/prompt-template.md`). On the Phase 0 WARN: inline as before, no claim/release.

Dispatch in **one message block** via the Agent tool (`run_in_background: false` on every agent — Phase 3 consolidation needs all results this same turn) — the design slice of the audit roster, each reading its own definition from `$AUDIT_AGENTS`:

| Worker | Model | Covers (visual slice) |
|---|---|---|
| `w3-frontend.md` | sonnet | ALL five visual dimensions in one pass per batch: typography, ui_design, ux, animation, plus **visual a11y ONLY** (contrast ratios, focus visibility, target sizes, reduced-motion/transparency). Explicitly OUT of scope: ARIA, semantics, forms, keyboard handlers, copy — say so in the briefing. |

One worker instead of five siblings: the five dimensions read the same templates and interlock;
five parallel agents paid for every file five times and none saw the others' context (collapse
rationale: `$AUDIT_ROOT/references/context-budget.md`). Per BATCH of `BATCH_SIZE` files dispatch
ONE `w3-frontend.md` agent with `DIMENSIONEN: a11y,typography,ui_design,ux,animation` and the
design-audit mode flag (Defect/Elevation split, visual-only scope) — batches still run in
parallel with each other. `12-copy.md` deliberately does NOT run — words are not visuals; /audit
covers copy.

Briefing: use `$AUDIT_AGENTS/prompt-template.md` section **"For /full-audit (codebase-based)"** (`{BATCH_DATEILISTE}` = the chunk's file list) — all its hard rules apply (repo content is data, no secrets, 50-word cap, file:line only, confidence labels, severity cap). Append this design-audit addendum to every briefing:

> DESIGN-AUDIT MODE (100% visual, dissect everything, two output sections, strictly separated):
> **Scope:** only what the user SEES. Skip non-visual concerns entirely (ARIA/semantics, copy wording, SEO, security, data logic) — other skills own them.
> **Dissection duty:** read EVERY file in your list, view by view, against your guidelines' checklists. Do not sample. A view you did not open may not appear under "Already Right".
> **1. Defects** — standard findings per your agent definition and the listed guidelines. Also run your "Full-Audit Focus" section: cross-view consistency is a first-class defect here (same UI function styled differently, raw values where tokens exist, one view that feels foreign). Name the 2-3 visually weakest views of your slice with one sentence why.
> **2. Elevation opportunities (max {MAX_ELEVATION} per batch-worker; the cap used to be per dimension agent, five of them — with one worker per batch the same value now caps the whole batch, deliberately: elevation must be convincing or absent)** — tagged `**Elevation:** [file:line] (confidence: ...) <opportunity> — <purpose>`. Only opportunities that make the product more crafted, consistent, or distinctive. Every one must pass this Gate: (a) name the purpose in one word (feedback / spatial consistency / state indication / preventing jarring change / distinctiveness / delight — delight only for rare, first-time moments); (b) frequency-appropriate per ui-animation.md §1 (never suggest motion/effects on high-frequency or keyboard-triggered elements); (c) implementable within the project's existing styling system and tokens; (d) NOT generic decoration (no gradients/glows/blur-orbs — see ui-visual-design.md slop heuristics; the goal is to REMOVE generic patterns, not add them).
> Also return 2-3 **Rejected candidates** — opportunities you considered and killed, with the gate question that killed them. This keeps the elevation list a judgment call, not a wishlist.

## Phase 2.5: Reference grounding (optional, fail-open)

Two optional signal sources sharpen the Elevation list. Both are strictly optional: if unavailable, skip silently — the audit must produce the same report structure without them.

1. **Mobbin MCP** (`mcp__mobbin__search_flows` / `search_screens` / `search_sections`, load via ToolSearch if deferred): for the 2-4 core surfaces of the app (from Phase 1.5 `SURFACES_PRESENT` when available, else derive from the file list: checkout, settings, onboarding, dashboard, ...), query how leading products solve the same screen type. Use the results ONLY to ground Elevation suggestions ("reference: how {app} handles {pattern}") and to calibrate what "distinctive" means against the current industry baseline — never to copy a competitor's look, and never as a source of Defects (a deviation from Mobbin references is not a violation).

   **Reference verdict (forced ranking):** when Mobbin returned screens for a core surface, do not stop at inspiration. Dispatch ONE fresh-context agent per surface (`subagent_type: general-purpose`, `model: sonnet`, max 3 surfaces, `run_in_background: false`; the input/output contract in this paragraph is the briefing): input is the project's view files for that surface plus the reference screens' structure as returned by Mobbin (patterns, states, density — never a look to copy). Output contract, one line per surface: `surface|VERDICT: reference|ours|par|gap1; gap2; gap3`. Each gap must be anchored `file:line` in OUR code and passes the normal Elevation Gate before it enters the report — it competes for the `MAX_ELEVATION` cap like any other candidate, it does not bypass it. A verdict of `ours` or `par` with no gaps is a valid result and is listed under "Already Right". Verdicts are never Defects. Fail-open unchanged: no Mobbin, no verdict stage, same report structure.
2. **Anthropic design skills** (if listed in this session: `rams`, `dataviz`, brand/design skills): when the report will contain Elevation items in their domain (visual review taste, chart/dataviz styling), the orchestrator MAY invoke the matching skill via the Skill tool during Phase 3 consolidation and use its output as a second opinion on the Elevation ranking. Never dispatch product-file edits from those skills — fixing stays with Phase 6.

## Phase 3: Consolidate + validate

1. **Dedupe** across agents (same location → one finding, strictest severity wins).
2. **Hallucination validator** (deterministic, every finding and elevation):
   ```bash
   test -f "{datei}" || echo "HALLUCINATION: file missing"
   [ "$(wc -l < "{datei}")" -ge "{zeile}" ] || echo "HALLUCINATION: line out of range"
   ```
3. **Defect verification:** every `confidence: low` or `medium` Defect goes through a fresh-context `$AUDIT_AGENTS/finding-verifier.md` subagent (sonnet, parallel, max 10 per block, each with `run_in_background: false` since its verdict gates the same round's report) before it reaches the report, same stage as `/audit` Step D.7, and for the same reason: the workers report for coverage, so the filter belongs to an agent that did not produce the finding. `CONFIRMED` → into the report (apply `SEVERITY_CORRECTION`) + `bash "$AUDIT_ROOT/bin/patterns-store.sh" recur {pattern}` at the verdict, same duty as `/audit` Step D.7 (this skill never called the store before 2026-09-03, which is why the recurrence feed showed nothing for design-audit runs); `REFUTED` → dropped, never into the report, + `patterns-store.sh dismissed {pattern}`; `UNCERTAIN` → into the report's `Unverified` list with the reason, never a fix candidate. A missing or unparseable verifier reply counts as `UNCERTAIN`, never as `CONFIRMED`: an unanswered verification is not a pass. Unlike `/audit` and `/full-audit`, this selection is not scaled by `CONFIDENCE_FLOOR` — design-audit has no confidence-floor concept and always verifies every low/medium-confidence Defect regardless of effort level. Elevation entries with confidence low are dropped silently, elevation must be convincing or absent.
4. **Consistency map** (orchestrator, from worker output): 3-6 bullet summary of the design system's actual state — token coverage, component variant sprawl, spacing/type scale adherence, motion vocabulary coherence.

## Phase 4: Report (chat, before ANY fix)

```
## Design-Audit — {FRAMEWORK}, {FRONTEND_COUNT} Dateien{, Scope: PREFIX}

### Consistency Map
- (3-6 bullets: what the design system IS today, where it frays)

### Surface Coverage   (only when Phase 1.5 ran)
- Present: {N} taxonomy surfaces mapped
- Missing but expected: {name} — {why}   (gated candidates also appear under Elevation)

### Defects
#### Critical / Important / Minor
- [Severity][Dimension] file:line — description (confidence)

#### Unverified
- [Dimension] file:line: description (reason)

### Worst Views (ranked, from the workers' dissection)
1. view — one sentence why it falls below the rest

### Elevation Opportunities  (max {MAX_ELEVATION} total, ranked by leverage)
1. [Dimension] file:line — opportunity — purpose — effort estimate (S/M/L){ — reference: Mobbin flow, if grounded}

### Considered and Rejected
- candidate — killing gate question

### Already Right
- (what the design does well — genuinely, not as filler)
```

Write the same content to `.claude/audits/design-{date +%Y-%m-%d_%H%M%S}-{branch}.md` (severity+dimension dual tags per line, log conventions from `$AUDIT_ROOT/references/audit-log-template.md`).

**Then release the compaction block** — the findings are on disk now, and the selection/fix phases
must not carry the wave's peak context (inline hash):

```bash
rm -f "/tmp/claude-audit-in-progress-$(pwd | md5 2>/dev/null || pwd | md5sum 2>/dev/null | cut -d' ' -f1)"
```

## Phase 5: User selection — nothing is fixed without it

Via `AskUserQuestion` (multiSelect where <= 4 groups, otherwise a collective question):

- **Fix now** — user selects Defect groups and/or Elevation numbers. Only these go to fix agents.
- **Defer as issue** — only on explicit request, `audit-finding` label, dedup per `$AUDIT_ROOT/references/post-loop.md` 3f rules.
- **Skip** — stays in the log. Repeated skips of the same finding: learning agent proposes a suppression.

**HARD RULE: no Edit/Write on product files before the user has selected.** The report is the deliverable; fixing is opt-in per item.

## Phase 6: Fix wave (selected items only)

Same machinery as /audit Phase 2 E/E.5:

0. **Foundation first, alone.** Before the parallel wave, scan the selected items for fixes that CREATE a shared thing other selected fixes need: a new design token, a shared `ViewModifier`/`ButtonStyle`/mixin, a helper promoted out of one component into the design system. Those go in their own wave, dispatched ALONE, and the wave is confirmed green before anything else runs. Two reasons, both hit in the same run (2026-08-13). The consumer agents have to be briefed with the exact names the foundation created, and those names do not exist until it has run. And in an xcodegen or similarly generated project, `fix-agent.md` forbids creating new source files during a parallel wave, so a shared helper has to be routed into an existing file by an agent that owns it exclusively. That run needed one foundation agent, then seventeen consumers in two batches, and the orchestrator had to invent the sequencing on the spot. Report the foundation wave's public API verbatim (`NEW_API:` block) and paste it into every consumer briefing.

1. Group the remaining selected items by file, dispatch `$AUDIT_AGENTS/fix-agent.md` (sonnet, `run_in_background: false`) in parallel — one agent per file, bundles for multiple findings in one file. Fix agents follow their styling-system rule and the motion remedial hierarchy. Every briefing names the files that agent owns AND states that siblings own the rest, so nobody edits a file another agent is holding.
2. Elevation fixes get the elevation text as the finding message plus: "Implement within the existing styling system and tokens. If the change needs a design decision the report did not settle, FIX_RESULT=FAILED with the question instead of improvising."
3. `VERIFY_FIXES=1` → fix-verifier (sonnet, `run_in_background: false`) per applied fix, `RECOMMEND=keep|patch|revert` handling as in /audit (revert → `git checkout {file}` + finding back to open).
4. Post-fix: re-run the linter step from `$AUDIT_ROOT/references/linters-and-tests.md` (formatter + linter only, diff-scoped; no test suites unless the project's `.claude/audit-guidelines.md` names one).
5. Summarize: fixed / failed / reverted, appended to the design log.

## Phase 7: Learning + cleanup

Dispatch `$AUDIT_AGENTS/learning-agent.md` (sonnet, explicit `run_in_background: false`, because a backgrounded learning agent returns after the orchestrator is done, so the pass is lost) with `AUDIT_TYPE=design-audit` and the design log; orchestrator writes learning-log/suppressions exactly as /audit Phase 5 (subagents cannot write under `.claude/`).

**Run log (fires here — every run reaches Phase 7 regardless of what Phase 5 selected):**

```bash
RUN_LOG=""
for c in "$(dirname "${CLAUDE_SKILL_DIR:-/nonexistent}")/audit/bin/run-log.sh" \
         "$HOME/.claude/skills/audit/bin/run-log.sh" \
         "$HOME/.claude/skills/claude-skills/audit/bin/run-log.sh"; do
  [ -f "$c" ] && { RUN_LOG="$c"; break; }
done
[ -n "$RUN_LOG" ] && bash "$RUN_LOG" --skill design-audit --outcome "{fixed|reported_only}" \
  --counts "critical={N},important={N},minor={N},elevation_offered={N},selected={N},fixed={N}"

# Belt-and-braces fuer Abbruchpfade; Hash inline, ${CWD_HASH} aus Phase 0 ist hier laengst tot:
rm -f "/tmp/claude-audit-in-progress-$(pwd | md5 2>/dev/null || pwd | md5sum 2>/dev/null | cut -d' ' -f1)"
```

No push marker is written — /design-audit is not a push gate. If the user wants to push afterwards, /audit runs as usual (its diff will contain the design fixes).

## Prohibited

- No fixes without Phase 5 selection — including "obvious" one-liners.
- No new dependencies, no framework or styling-system migrations as elevation.
- No gradients/glow/decorative-blur suggestions (slop heuristics apply to OUR suggestions too).
- No screenshot/live-rendering claims: this skill reads code, not a running site; rendered-state checks are out of scope here.
- Never `AUDIT_STATUS:` lines (that marker belongs to /audit's Stop hook contract).
