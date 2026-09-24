---
name: screens
description: "Builds and maintains a complete, current screenshot catalog of every view in every applicable state (data/viewport/theme/role) for a project, plus App-Store-ready marketing renders. First run discovers views via an agent and scaffolds a demo seeder + capture drivers; later runs are scripted and incremental (only new/changed views recapture). NOT for before/after capture of one change (that is /delegate, which reuses this catalog when `.screens/` exists). Use when the user runs /screens, wants a full visual inventory of the app, or needs App-Store screenshots."
when_to_use: "/screens, alle Screens aufnehmen, Screenshots aktualisieren, Screens-Katalog, Screenshot-Katalog, App-Store-Screenshots, App-Store-Screens erstellen"
argument-hint: "[web|ios|android|macos] [--full]"
model: inherit
effort: medium
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

# /screens: Screenshot Catalog of Every View in Every State

> **Architecture note:** Discovery is agent work (`agents/screens-view-discoverer.md`, worker spec
> `screens/agents/view-discoverer.md`), capture is scripted (`screens/bin/screens.mjs`). Per-project
> files live under `.screens/` and `screenshots/` in the TARGET project, never under `.claude/`
> (subagents cannot write there: orchestrator writes, subagents return). The web/iOS/Android
> drivers this phase 5 loop invokes (`screens/references/platform-*.md`,
> `screens/templates/*`) are added in later delivery stages; this stage wires the phases that will
> call them and reports `SKIP` where a driver does not exist yet.

## Phase 0: Preflight

```bash
for c in "$(dirname "${CLAUDE_SKILL_DIR:-/nonexistent}")/audit/bin/lib-orchestrator.sh" \
         "$HOME/.claude/skills/audit/bin/lib-orchestrator.sh"; do
  [ -f "$c" ] && { . "$c"; break; }
done
type orch_run_log >/dev/null 2>&1 || echo "lib-orchestrator.sh not found; run log and helpers unavailable (skill continues)"
orch_run_log --start --skill screens

SCREENS_BIN="$(dirname "${CLAUDE_SKILL_DIR:-/nonexistent}")/screens/bin/screens.mjs"
[ -f "$SCREENS_BIN" ] || SCREENS_BIN="$HOME/.claude/skills/screens/bin/screens.mjs"
[ -f "$SCREENS_BIN" ] || { echo "Aborted: screens.mjs not found."; exit 1; }

DETECT="$(dirname "${CLAUDE_SKILL_DIR:-/nonexistent}")/audit/bin/detect-framework.sh"
[ -f "$DETECT" ] || DETECT="$HOME/.claude/skills/audit/bin/detect-framework.sh"
[ -f "$DETECT" ] && eval "$("$DETECT")"
echo "FRAMEWORK=${FRAMEWORK:-unknown} PLATFORM=${PLATFORM:-unknown}"

if [ -f ".screens/.lock" ]; then
  echo "Aborted: a /screens run is already in progress in this repo (.screens/.lock present)."
  exit 1
fi

REQUESTED_PLATFORM=""
FULL_FLAG=""
for a in $ARGUMENTS; do
  case "$a" in
    web|ios|android|macos) REQUESTED_PLATFORM="$a" ;;
    --full) FULL_FLAG="--full" ;;
  esac
done
echo "RequestedPlatform=${REQUESTED_PLATFORM:-all} Full=${FULL_FLAG:-no}"
orch_state_save SCREENS_BIN REQUESTED_PLATFORM FULL_FLAG
```

`/screens <platform>` scopes the whole run to one platform and never touches `.screens/config.json`
(product decision, plan Invocation section). `--full` ignores fingerprints (passed straight to
`screens.mjs plan --full`).

## Phase 1: Discovery (first run only)

Skip this phase entirely when `.screens/config.json` already exists; go to Phase 2.

`detect-framework.sh` reports a CLI or WordPress/Local project (`FRAMEWORK=generic` with no known
web/native signature): report `SCREENS_RESULT=SKIP (unsupported project type)` and stop (Non-Goal:
CLI/WordPress-Local projects).

Otherwise, dispatch `screens-view-discoverer` (`subagent_type: screens-view-discoverer`, `model:
sonnet`, `run_in_background: false`; worker spec `screens/agents/view-discoverer.md`) once per
configured/detected platform, `MODE=full`. Input per the worker spec's Input contract:
`PLATFORM`, `PROJECT_ROOT`, `FRAMEWORK`, `SURFACE_TAXONOMY` (`design-audit/references/surface-taxonomy.md`
next to this skill).

From the returned `MANIFEST_ENTRY`/`CONFIG_DRAFT`/`DEMO_DATA_BRIEF`/`MARKETING_HERO` lines, write
`.screens/config.json` and `.screens/manifest.json` yourself (Write tool) per the schema in
`references/config-schema.md`. Compute the planned total (entries x applicable axes) for the
summary below.

**Single `AskUserQuestion`** before anything runs: show, per platform, the entry count, the state
axes that apply, the planned total, the marketing hero list with proposed headlines, and the exact
start/seed commands that will run (Trust boundary: this is the first confirmation of them). On
confirmation, write `.screens/state.json` with `command_hash` from `screens.mjs trust --confirm`
(run after config.json is written) so later runs do not re-ask unless a command changes.

## Phase 2: Scaffold

First run only (same guard as Phase 1). Dispatch a `general-purpose` subagent (`model: sonnet`,
`run_in_background: false`) with the demo-data brief and config/manifest paths: write the demo
seeder and the platform driver files the plan's "Per-project files" table names
(`database/seeders/ScreensDemoSeeder.php` or the framework's equivalent, `.screens/web/capture.spec.ts`,
etc.; driver templates for stages b/d/e are not present in this repo yet, and when a template is
missing, the executor writes only the seeder and reports which drivers it deferred). The
orchestrator never writes these files itself (subagent Write scope is the target project, not
`.claude/`).

After the executor returns, run a seeder dry run:

```bash
for c in "$(dirname "${CLAUDE_SKILL_DIR:-/nonexistent}")/audit/bin/lib-orchestrator.sh" \
         "$HOME/.claude/skills/audit/bin/lib-orchestrator.sh"; do
  [ -f "$c" ] && { . "$c"; break; }
done
orch_state_load
node "$SCREENS_BIN" up --platform "${REQUESTED_PLATFORM:-web}"
```

A `FAIL` line here (seeder error, DB guard, missing tool) stops before any capture: keep
config/manifest, report the error, the next run retries the scaffold (Edge Cases: "Seeder fails on
first run").

## Phase 3: Trust check

```bash
for c in "$(dirname "${CLAUDE_SKILL_DIR:-/nonexistent}")/audit/bin/lib-orchestrator.sh" \
         "$HOME/.claude/skills/audit/bin/lib-orchestrator.sh"; do
  [ -f "$c" ] && { . "$c"; break; }
done
orch_state_load
node "$SCREENS_BIN" trust
```

`TRUST_RESULT=NEEDS_CONFIRM` (a command field changed since the last confirmation, or a fresh
clone): show the current command fields via one `AskUserQuestion`, then run
`node "$SCREENS_BIN" trust --confirm` on approval. `TRUST_RESULT=OK`: continue silently.

## Phase 4: Plan + delta discovery

```bash
for c in "$(dirname "${CLAUDE_SKILL_DIR:-/nonexistent}")/audit/bin/lib-orchestrator.sh" \
         "$HOME/.claude/skills/audit/bin/lib-orchestrator.sh"; do
  [ -f "$c" ] && { . "$c"; break; }
done
orch_state_load
node "$SCREENS_BIN" plan $FULL_FLAG
```

When files matching `route_sources` changed since `state.commit` (`git diff --name-only
<state.commit>..HEAD -- <route_sources>`), dispatch `screens-view-discoverer` again, `MODE=delta`,
`DELTA_FILES` from that diff. Apply `MANIFEST_ENTRY`/`REMOVED_ENTRY` additions to
`.screens/manifest.json` without asking (triage decision, plan's "Incremental rule"); report the
delta in the Phase 8 summary. Hand-edited entries (no matching discoverer proposal this run) are
never touched.

## Phase 5: Per-platform loop

For each platform in scope (`REQUESTED_PLATFORM` or every platform in `config.json`, macOS last,
it takes focus visibly): `up` -> driver -> `promote` -> `down`, `down` always runs even on a driver
failure (trap semantics; a single-entry failure does not abort the platform, a driver failure does
not skip `promote`/`down`).

```bash
for c in "$(dirname "${CLAUDE_SKILL_DIR:-/nonexistent}")/audit/bin/lib-orchestrator.sh" \
         "$HOME/.claude/skills/audit/bin/lib-orchestrator.sh"; do
  [ -f "$c" ] && { . "$c"; break; }
done
orch_state_load
PLATFORM="${REQUESTED_PLATFORM:-web}"
node "$SCREENS_BIN" up --platform "$PLATFORM"
orch_state_save PLATFORM   # read back by the promote/down block below
```

`UP_RESULT=SKIP (...)` (toolchain or device setup not available/not implemented yet): report and
move to the next platform, no capture attempted. `UP_RESULT=FAIL (...)`: report the reason and run
`down` before moving on.

Driver step: read `screens/references/platform-web.md` (web, added stage b),
`screens/references/platform-apple.md` (iOS/macOS, stage d), `screens/references/platform-maestro.md`
(Android/Capacitor, stage e); when the reference file does not exist yet, report `DRIVER=SKIP
(driver added in a later stage)` for that platform and skip straight to `down`.

```bash
for c in "$(dirname "${CLAUDE_SKILL_DIR:-/nonexistent}")/audit/bin/lib-orchestrator.sh" \
         "$HOME/.claude/skills/audit/bin/lib-orchestrator.sh"; do
  [ -f "$c" ] && { . "$c"; break; }
done
orch_state_load
node "$SCREENS_BIN" promote --platform "$PLATFORM"
node "$SCREENS_BIN" down --platform "$PLATFORM"
```

## Phase 6: Marketing

```bash
for c in "$(dirname "${CLAUDE_SKILL_DIR:-/nonexistent}")/audit/bin/lib-orchestrator.sh" \
         "$HOME/.claude/skills/audit/bin/lib-orchestrator.sh"; do
  [ -f "$c" ] && { . "$c"; break; }
done
orch_state_load
node "$SCREENS_BIN" marketing
```

`MARKETING_RESULT=SKIP (renderer added in stage c; ...)` in this stage: report the planned
draft/ready split from `MARKETING_PLAN` lines, no PNGs produced yet.

## Phase 7: Index

```bash
for c in "$(dirname "${CLAUDE_SKILL_DIR:-/nonexistent}")/audit/bin/lib-orchestrator.sh" \
         "$HOME/.claude/skills/audit/bin/lib-orchestrator.sh"; do
  [ -f "$c" ] && { . "$c"; break; }
done
orch_state_load
node "$SCREENS_BIN" index
```

`INDEX_RESULT=SKIP (renderer added in stage c)` in this stage.

## Phase 8: Report

Table: platform x new/updated/unchanged/removed/failed (from the `PLAN_ENTRY`/`PROMOTE_ENTRY`/
`PROMOTE_REMOVED` lines collected above). `NEEDS REVIEW` list: marketing entries still under
`_draft` (once stage c renders). Path to `screenshots/index.html` (once stage c writes it). Suggest
`--full` when the last full run is older than 30 days (from `state.json`, once state carries that
timestamp).

```bash
for c in "$(dirname "${CLAUDE_SKILL_DIR:-/nonexistent}")/audit/bin/lib-orchestrator.sh" \
         "$HOME/.claude/skills/audit/bin/lib-orchestrator.sh"; do
  [ -f "$c" ] && { . "$c"; break; }
done
orch_run_log --skill screens --outcome "{ok|partial|fail}" \
  --counts "new={N_NEW},updated={N_UPDATED},failed={N_FAILED}"
```

Fill `{ok|partial|fail}` and the `{N_...}` placeholders with the outcome and counts tallied from
this phase's own report table before running the block (same convention as `audit/SKILL.md`
Phase 4's `{N_CRITICAL}` placeholders: the orchestrator writes literal values, not a shell
variable read from an earlier block).
