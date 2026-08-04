---
name: app-baseline
disable-model-invocation: true
description: |
  Captures the production baseline for a new or existing app (web or mobile):
  interviews for the positioning charter (three keywords, value prop, target user),
  scans the repo against the baseline spec, writes BASELINE.md, and scaffolds
  missing infrastructure (CI gate, .env.example, deploy stub, backup script) on
  selection. Use when starting a new app or when onboarding an existing app onto
  the baseline standard. Checking an already-onboarded app is /baseline-check.
when_to_use: "/app-baseline, neue App aufsetzen, Baseline erfassen, App-Standard einrichten, Boilerplate für neue App, BASELINE.md erstellen"
argument-hint: "[project root, defaults to cwd]"
model: sonnet
effort: high
allowed-tools:
  - Read
  - Write
  - Edit
  - Bash
  - Grep
  - Glob
  - Agent
  - AskUserQuestion
---

# App Baseline

Onboards an app onto the baseline standard defined in `guidelines/baseline-spec.md`.
Interactive by design: the charter comes from the user, not from guessing.

Output: a `BASELINE.md` in the project root plus scaffolded infra the user selected.
This skill never deploys, never pushes, never runs backups. It writes files.

## Phase 0: Scan

```bash
SKILL_DIR="${CLAUDE_SKILL_DIR}"
# Skill argument, not the shell positional $1: inside a skill body $1 would be the SECOND
# argument (shorthand for $ARGUMENTS[1]), and inside the Bash tool a bare $1 is empty either
# way, so the passed project root was silently ignored and the run always fell back to cwd.
ROOT="$ARGUMENTS"
[ -z "$ROOT" ] && ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
bash "$SKILL_DIR/bin/baseline-scan.sh" "$ROOT"
```

Read `guidelines/baseline-spec.md` for the dimension definitions. Keep the scan
output; it drives Phase 2 (what to prefill) and Phase 3 (what to offer).

If a `BASELINE.md` already exists: read it, tell the user, and switch to update
mode (only fill gaps, never overwrite existing answers without asking).

## Phase 1: Interview

Ask via AskUserQuestion, in two batches. Free-text answers come through "Other".

Batch 1 (charter, D1):
1. The three keywords the app should transmit (free text expected).
2. One-sentence value proposition (free text expected).
3. Target user (free text expected).
4. Explicit out-of-scope: what does this app deliberately not do?

Batch 2 (ops, D6/D8/D9 — prefill options from scan evidence where possible):
1. Deploy target (options from what the scan saw: CI workflow found / TestFlight /
   SSH server / not set up yet).
2. Backup situation: where does persistent data live, is anything backed up today,
   has a restore ever been tested?
3. Observability: error tracking and uptime monitoring in place? Which service?
4. Dark mode: supported, planned, or a deliberate no (a documented no is valid, spec D2).

Do not interrogate dimensions the scan already verified as PASS. One question per
unknown, no more.

## Phase 2: Write BASELINE.md

Template (fill from interview + scan; omit nothing, use "TBD" only where the user
explicitly deferred):

```markdown
# Baseline: {app name}

## Charter
- **Keywords:** {k1}, {k2}, {k3}
- **Value proposition:** {one sentence}
- **Target user:** {one sentence}
- **Out of scope:** {list}

## Platform
- {web|native|cross}, {framework}, runtime {version}

## Deployment
- **How:** {mechanism}
- **Rollback:** {documented path, or TBD with owner}
- **Staging:** {target, or documented decision why none}

## Backups
- **What/where:** {data stores and destinations}
- **Schedule:** {cron/managed}
- **Last restore test:** {date + outcome, or "never (open Must)"}

## Observability
- **Error tracking:** {service or "none (open Must)"}
- **Uptime:** {service or "none (open Must)"}

## Accessibility
- **Automated:** {tool + where it runs}
- **Last manual pass:** {date, method}

## Decided tradeoffs
- {conscious deviations from the baseline spec, with reasons; this section
  suppresses findings in /baseline-check}

## Data & legal
- **Personal data stored:** {what, where, retention}
- **Legal pages:** {Impressum/Datenschutz locations}
```

Rules:
- Never write secrets or credential values into BASELINE.md, only names/locations.
- Open Musts are written as "open Must" honestly, not hidden. /baseline-check
  will pick them up.

## Phase 3: Scaffold (on selection)

From the scan FAILs, offer concrete scaffolds via AskUserQuestion (multiSelect).
Only offer what is actually missing. Candidates:

| Gap (scan check) | Scaffold |
|---|---|
| D4 ci_gate | Minimal CI workflow: lint + typecheck + test, blocking. GitHub Actions unless the repo shows another CI. |
| D4 pre_push_gate | Husky/hook pre-push running the test command (or point to the /audit marker flow if this machine uses it). |
| D12 env_example | `.env.example` generated from the env vars actually referenced in code (names only, values as placeholders). |
| D5 env_ignored | Add env patterns to `.gitignore`. |
| D6 deploy_automation | Deploy stub matching the stated target (Fastlane lane skeleton for mobile, workflow + SSH/rsync skeleton for web). Marked TODO where credentials/hosts must be filled by the user. |
| D8 backup_mechanism | Backup script skeleton (DB dump + offsite rsync) plus a cron line as a comment. Not installed, not scheduled: the user wires it. |

Scaffold rules:
- Match the project's existing conventions and package manager. No new dependencies
  without asking.
- Every scaffold that needs secrets gets placeholder names, never values, and a
  TODO comment naming where the secret should live (CI secrets, Keychain).
- Nothing speculative: no scaffolds for gaps the user chose to skip.

## Phase 4: Summary

```
Baseline captured: {ROOT}/BASELINE.md

Charter:        {k1}, {k2}, {k3}
Open Musts:     {n} ({list of dimension ids})
Scaffolded:     {list or "nothing selected"}
Skipped:        {gaps the user deferred}

Next: /baseline-check to verify, /full-audit for code-level depth.
```

Do not commit. Committing is the user's call.
