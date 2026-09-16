---
name: ship
description: |
  Full docs-commit-audit-test-push-deploy pipeline in one command. Brings README, CLAUDE.md,
  CHANGELOG and help pages back in sync with the change before committing, stages tracked changes,
  generates a conventional commit message (or uses the provided one), enforces audit and (where the
  project configures one) the full test suite before push, deploys via project-specific method, and
  verifies the deploy. Use when ready to ship completed work. Push requires a fresh audit marker
  and a green suite; bypassing either is only possible as an explicit, logged user decision,
  never silently.
when_to_use: "/ship, committe das und pushe, fertig zum deployen, jetzt live stellen, push und deploy machen, ab damit, ready to ship, commit and deploy, commit push deploy, ship this, release this"
argument-hint: "[optional: commit message]"
model: sonnet
effort: medium
allowed-tools:
  - Read
  - Write
  - Edit
  - Bash
  - Glob
  - AskUserQuestion
---

# Ship

Docs -> Commit -> Audit -> Tests -> Push -> Deploy -> Verify. In that order. No skipping.
(The test phase runs only when the project sets `test-command:` in `.claude/ship.md`.)

## Phase 0: Pre-flight

```bash
# Must be in a git repo
git rev-parse --show-toplevel 2>/dev/null || { echo "Not a git repo."; exit 1; }

# Check for changes to ship
git status --short
git diff --stat HEAD 2>/dev/null
```

If no tracked changes and no staged files: report and stop. Nothing to ship.

Detect deploy method and health check URL (check in priority order):

```bash
# 1. Project config wins — read the values if present, all three through the one parser in the lib
for c in "$(dirname "${CLAUDE_SKILL_DIR:-/nonexistent}")/audit/bin/lib-orchestrator.sh" "$HOME/.claude/skills/audit/bin/lib-orchestrator.sh"; do [ -f "$c" ] && { . "$c"; break; }; done   # fresh shell per block
orch_state_clear   # /ship has no in-progress claim; start this run's cross-block state empty
DEPLOY_COMMAND=$(orch_ship_value deploy-command) || DEPLOY_COMMAND=""
HEALTH_URL=$(orch_ship_value health-check) || HEALTH_URL=""

# 2. Detect deploy method from known files
if [ -z "$DEPLOY_COMMAND" ]; then
  [ -f fly.toml ]               && DEPLOY_COMMAND="fly deploy"
  [ -f vapor.yml ]              && DEPLOY_COMMAND="vapor deploy production"
  [ -f vapor.yaml ]             && DEPLOY_COMMAND="vapor deploy production"
  [ -f deploy.sh ]              && DEPLOY_COMMAND="bash deploy.sh"
  [ -f .vercel/project.json ]   && DEPLOY_COMMAND="vercel --prod"
  [ -f netlify.toml ]           && DEPLOY_COMMAND="netlify deploy --prod"
  [ -f railway.toml ]           && DEPLOY_COMMAND="railway up"
  ls .github/workflows/deploy*.yml 2>/dev/null | head -1 | grep -q . && DEPLOY_COMMAND="ci"
  # iOS / BaaS
  [ -f fastlane/Fastfile ]        && DEPLOY_COMMAND="fastlane"       # lane asked below
  [ -f firebase.json ]            && DEPLOY_COMMAND="firebase deploy"
  [ -f .firebaserc ]              && DEPLOY_COMMAND="firebase deploy"
  [ -f supabase/config.toml ]     && DEPLOY_COMMAND="supabase db push && supabase functions deploy"
  [ -f amplify.yml ]              && DEPLOY_COMMAND="amplify push --yes"
  [ -d .xcode/cloud ]             && DEPLOY_COMMAND="ci"             # Xcode Cloud triggers on push
fi

# Fastlane: ask which lane (beta / release / custom)
if [ "$DEPLOY_COMMAND" = "fastlane" ]; then
  LANES=$(grep -E '^\s*lane\s+:' fastlane/Fastfile 2>/dev/null \
    | sed 's/.*lane\s*:\([a-z_]*\).*/\1/' | tr '\n' ' ')
  # DEPLOY_COMMAND resolved by AskUserQuestion below (see "no method found" block)
  # Pass LANES as context to the question
fi

# 3. Auto-detect health check URL from codebase (only if not in .claude/ship.md)
if [ -z "$HEALTH_URL" ]; then

  # fly.toml: app name + health_checks path
  if [ -f fly.toml ]; then
    FLY_APP=$(grep '^app\s*=' fly.toml | head -1 | sed 's/.*=\s*["\x27]\(.*\)["\x27]/\1/')
    FLY_HEALTH=$(grep -A2 'health_checks' fly.toml | grep 'path' | head -1 \
      | sed 's/.*path\s*=\s*["\x27]\(.*\)["\x27]/\1/')
    FLY_HEALTH="${FLY_HEALTH:-/health}"
    [ -n "$FLY_APP" ] && HEALTH_URL="https://${FLY_APP}.fly.dev${FLY_HEALTH}"
  fi

  # vapor.yml: production domain -> Laravel /up route
  if [ -z "$HEALTH_URL" ] && [ -f vapor.yml ]; then
    VAPOR_DOMAIN=$(awk '/^production:/,/^[a-z]/' vapor.yml | grep 'domain:' | head -1 \
      | awk '{print $2}' | tr -d '"')
    [ -n "$VAPOR_DOMAIN" ] && HEALTH_URL="https://${VAPOR_DOMAIN}/up"
  fi

  # netlify.toml: production URL
  if [ -z "$HEALTH_URL" ] && [ -f netlify.toml ]; then
    NETLIFY_URL=$(grep -A5 '\[context\.production\]' netlify.toml | grep 'url' | head -1 \
      | cut -d'"' -f2)
    [ -n "$NETLIFY_URL" ] && HEALTH_URL="${NETLIFY_URL}/health"
  fi

  # .env.example: APP_URL (readable, unlike .env)
  if [ -z "$HEALTH_URL" ] && [ -f .env.example ]; then
    APP_URL=$(grep '^APP_URL=' .env.example | cut -d= -f2- | tr -d '"' | tr -d "'" | tr -d ' ')
    if [ -n "$APP_URL" ] && [ "$APP_URL" != "http://localhost" ] \
        && [ "$APP_URL" != "http://127.0.0.1" ]; then
      # Laravel has /up built-in (11+); else try /health
      [ -f artisan ] && HEALTH_URL="${APP_URL}/up" || HEALTH_URL="${APP_URL}/health"
    fi
  fi

  # Firebase Hosting: site name from firebase.json -> https://{site}.web.app/
  if [ -z "$HEALTH_URL" ] && [ -f firebase.json ]; then
    FB_SITE=$(python3 -c "import json,sys; d=json.load(open('firebase.json')); \
      h=d.get('hosting',{}); print((h[0] if isinstance(h,list) else h).get('site',''))" \
      2>/dev/null)
    # Fall back to project ID from .firebaserc
    [ -z "$FB_SITE" ] && FB_SITE=$(python3 -c "import json; \
      print(json.load(open('.firebaserc'))['projects']['default'])" 2>/dev/null)
    [ -n "$FB_SITE" ] && HEALTH_URL="https://${FB_SITE}.web.app/"
  fi

  # Supabase: project_id from supabase/config.toml -> https://{id}.supabase.co/health
  if [ -z "$HEALTH_URL" ] && [ -f supabase/config.toml ]; then
    SB_ID=$(grep '^project_id' supabase/config.toml | cut -d'"' -f2)
    [ -n "$SB_ID" ] && HEALTH_URL="https://${SB_ID}.supabase.co/health"
  fi

  # Fastlane / iOS: no HTTP health check applicable
  # Xcode Cloud / TestFlight: no HTTP health check applicable
fi
orch_state_save DEPLOY_COMMAND HEALTH_URL
```

Log what was detected:
```
Deploy: {DEPLOY_COMMAND}
Health: {HEALTH_URL or "not detected"}
```

If `DEPLOY_COMMAND = "fastlane"`: AskUserQuestion — which lane?
- Each detected lane name as an option (from `$LANES`)
- "Custom lane..." (user types it)
→ Set `DEPLOY_COMMAND="fastlane {lane}"`

If no deploy method found: AskUserQuestion with options:
- "CI/CD deploys on push (no extra command)"
- "fly deploy"
- "firebase deploy"
- "fastlane beta"
- "Custom..." (user types the command)

Save to `.claude/ship.md` if not already present (never overwrite existing config):
```bash
for c in "$(dirname "${CLAUDE_SKILL_DIR:-/nonexistent}")/audit/bin/lib-orchestrator.sh" "$HOME/.claude/skills/audit/bin/lib-orchestrator.sh"; do [ -f "$c" ] && { . "$c"; break; }; done   # fresh shell per block
orch_state_load
DEPLOY_COMMAND="{the resolved command: the fastlane lane or the chosen option when a question above was asked, else the detected value}"
if [ ! -f .claude/ship.md ]; then
  mkdir -p .claude
  {
    echo "deploy-command: ${DEPLOY_COMMAND}"
    [ -n "$HEALTH_URL" ] && echo "health-check: ${HEALTH_URL}"
  } > .claude/ship.md
  echo "Created .claude/ship.md"
fi
orch_state_save DEPLOY_COMMAND
```

**Run log setup (resolve once, used by every phase below — fail open, never blocks ship):**

```bash
# Shared prologue (audit/bin/lib-orchestrator.sh); finding it is the one loop that stays inline.
for c in "$(dirname "${CLAUDE_SKILL_DIR:-/nonexistent}")/audit/bin/lib-orchestrator.sh" \
         "$HOME/.claude/skills/audit/bin/lib-orchestrator.sh"; do
  [ -f "$c" ] && { . "$c"; break; }
done
type orch_run_log >/dev/null 2>&1 || echo "lib-orchestrator.sh not found; run log and helpers unavailable (skill continues)"
# Run-ledger start marker — this is the true beginning of the run, before commit/audit/test/push/deploy.
orch_run_log --start --skill ship
```

Every later "run the log call" below means, in a block that starts with the lib source line and `orch_state_load`: `orch_run_log --skill ship --outcome {outcome} --gate "${SHIP_GATE:-n/a}" --counts "tests=${SHIP_TESTS:-n/a},deploy=${SHIP_DEPLOY:-n/a},docs=${SHIP_DOCS:-n/a}"`, substituting that step's outcome. Never in the same Bash call as `git push`. Every `SHIP_*=` assignment this file names happens inside a sourced block that ends with `orch_state_save <that name>`; without that, every block read `n/a` (fresh shell per block) and the ledger recorded a gate that never fired.

## Phase 0.8: Docs Sync

A ship that changes behaviour and leaves the docs behind is how a README starts lying. This phase
runs BEFORE the commit, so doc updates land in the same commit as the change they describe.

Inventory what changed and which docs this repo actually has:

```bash
CHANGED=$( { git diff --name-only HEAD; git diff --cached --name-only; } 2>/dev/null \
  | sort -u | grep -v '^$')

DOC_FILES=$(git ls-files 2>/dev/null | grep -Ei \
  '(^|/)(README|CHANGELOG|CONTRIBUTING|CLAUDE|AGENTS|INSTALL|UPGRADING)[^/]*\.(md|mdx|rst|txt)$|^(docs?|documentation|help|guides?|handbook)/.*\.(md|mdx|rst|txt)$|(^|/)SKILL\.md$|(^|/)\.env\.example$')

printf 'Changed:\n%s\n\nDocs in repo:\n%s\n' "$CHANGED" "${DOC_FILES:-none}"
```

Mechanical drift check, when the audit helper is reachable. Fails open, never blocks the ship:

```bash
for c in "$(dirname "${CLAUDE_SKILL_DIR:-/nonexistent}")/audit/bin/check-docs-claims.sh" \
         "$HOME/.claude/skills/audit/bin/check-docs-claims.sh"; do
  [ -f "$c" ] && { bash "$c" . 2>/dev/null; break; }
done
```

Now decide, do not ask. Read the diff, read every doc the diff could touch, update the ones that
are actually wrong or incomplete. This is triage: pick, act, and report one line per file with the
decision and its reason.

| Doc | Update when the diff ... |
|---|---|
| `README.md` | changes install steps, commands, requirements, supported platforms, the feature list, or any other claim the README states as fact |
| `CLAUDE.md` / `AGENTS.md` | changes architecture, conventions, invariants, or the command table, or adds a gotcha a future session would otherwise rediscover |
| `CHANGELOG.md` | changes anything user-visible. Add an entry under the existing `Unreleased` heading, matching the format already in the file |
| `docs/**`, help pages | documents a behaviour, flag, endpoint, or screen the diff changed |
| `.env.example` | adds or renames a config variable |
| `SKILL.md` | changes a skill's tools, phases, or trigger phrases |

Hard rules:

- **Never create a doc file that does not exist.** No CHANGELOG in the repo means this ship has no
  changelog entry. Report that as a line, do not invent the file.
- **Match the file's existing format**, including heading style, tense and language. A German
  README stays German.
- **Only the claims the diff invalidates.** No rewrites, no tidying of neighbouring prose, no
  reformatting. Same surgical rule as any other edit.
- **A version bump is intent, not triage.** An entry under `Unreleased` needs no question. Cutting
  a new version number is the user's call, so AskUserQuestion only when there is no `Unreleased`
  section to add to.

Phase 1 stages these with `git add -u`, since every file touched here was already tracked. Doc-only
edits do not invalidate a fresh audit marker: they are prose by the same definition
`classify-diff.sh` uses, so Phase 2 still checks marker age only.

Set `SHIP_DOCS` to the number of doc files updated, or `none` when the diff touched no documented
surface. `none` is a legitimate outcome for a pure refactor, not a reason to skip the check.

```bash
for c in "$(dirname "${CLAUDE_SKILL_DIR:-/nonexistent}")/audit/bin/lib-orchestrator.sh" "$HOME/.claude/skills/audit/bin/lib-orchestrator.sh"; do [ -f "$c" ] && { . "$c"; break; }; done   # fresh shell per block
SHIP_DOCS={N|none}
orch_state_save SHIP_DOCS
```

## Phase 1: Commit

Show what will be committed:
```bash
git diff --stat HEAD 2>/dev/null
git status --short
```

**If `$ARGUMENTS` is non-empty:** use it verbatim as the commit message (skip generation).

`$ARGUMENTS`, not a named argument: a commit message is free text, and named or indexed arguments map to shell-quoted *positions*, so `/ship fix: broken login` would bind only `fix:`. `$ARGUMENTS` expands to the full argument string as typed.

**If `$ARGUMENTS` is empty:** read the diff and generate a conventional commit message:
- Format: `{type}({optional-scope}): {what changed in imperative mood}`
- Types: `feat`, `fix`, `refactor`, `chore`, `docs`, `style`, `test`
- One line, max 72 chars, no period at end

Show the generated message. AskUserQuestion:
- "Commit with this message" (default)
- "Edit the message" → user provides the correct message in the next turn

Stage all tracked modified files (not untracked):
```bash
git add -u
# Plus any already-staged files
```

Check the staged diff for sensitive files AND for secret-shaped content. The filename grep alone is
not a secret check: a token pasted into `config/services.php` has an innocent name, and the audit
marker Phase 2 accepts may be up to 1800s old, so a secret added after that audit ran would reach
the remote unscanned (2026-09-16 audit, Critical). `pre-checks.sh` scans file CONTENT of every
changed and staged file with the same patterns `/audit` uses and prints `file:line: pattern-name`
only, never the value:
```bash
for c in "$(dirname "${CLAUDE_SKILL_DIR:-/nonexistent}")/audit/bin/lib-orchestrator.sh" "$HOME/.claude/skills/audit/bin/lib-orchestrator.sh"; do [ -f "$c" ] && { . "$c"; break; }; done   # fresh shell per block: source the lib again
git diff --cached --name-only | grep -iE '(\.env|secret|credential|\.pem|\.key)'   # -i: SECRET.txt and DB_CREDENTIAL.json are the same class
PRECHECK=$(orch_helper pre-checks.sh) || { echo "pre-checks.sh not found: the content secret scan cannot run, refusing to commit"; exit 1; }
bash "$PRECHECK" | grep -E '^SECRET_SCAN_RESULT=|^SECRET '
```
Filename hit: warn and AskUserQuestion — continue or abort? `SECRET_SCAN_RESULT=FINDINGS`: stop, do
not commit, name the `file:line` lines; this one is not a question.

```bash
git commit -m "{message}"
```

If commit fails (hook rejection, empty): run the log call (`outcome=commit_failed`), report the hook output and stop.

## Phase 2: Audit Gate

```bash
for c in "$(dirname "${CLAUDE_SKILL_DIR:-/nonexistent}")/audit/bin/lib-orchestrator.sh" "$HOME/.claude/skills/audit/bin/lib-orchestrator.sh"; do [ -f "$c" ] && { . "$c"; break; }; done   # fresh shell per block: source the lib again
MARKER="/tmp/claude-audit-passed-$(orch_hash_passed)"   # passed-family hash (no trailing newline), lib-orchestrator.sh
if [ -f "$MARKER" ]; then
  AGE=$(( $(date +%s) - $(stat -f%m "$MARKER" 2>/dev/null || stat -c%Y "$MARKER" 2>/dev/null) ))
  if [ "$AGE" -ge 1800 ]; then
    echo "STALE: Audit marker is ${AGE}s old (limit: 1800s)."; SHIP_GATE=stale
  elif ! orch_marker_matches; then
    echo "STALE: the audit marker certifies a different tree than the one just committed (edited after /audit ran, or a marker from before tree binding)."; SHIP_GATE=stale
  else
    echo "Audit marker fresh (${AGE}s ago) and bound to this tree. Proceeding to push."; SHIP_GATE=passed
  fi
else
  echo "MISSING: No audit marker found."; SHIP_GATE=missing
fi
orch_state_save SHIP_GATE
```

If marker missing or stale: AskUserQuestion:
- "Run /audit now" → invoke the audit skill (`/audit`), then re-check marker. `SHIP_GATE=passed-after-rerun` on success (not `passed`: the gate DID fire, the ledger must show that, otherwise `run-stats.sh` reports a gate that never blocks even when it blocked-and-reran every time; 17 such runs on 2026-08-28). On failure: `SHIP_GATE=blocked`, run the log call (`outcome=audit_failed`), then stop.
- "Push without audit (risky)" → `SHIP_GATE=bypassed`, log the bypass and continue with a warning in the output

Never silently skip the audit. The bypass must be an explicit user choice. Each of these is set in a sourced block ending with `orch_state_save SHIP_GATE` (4a).

## Phase 2b: Test Gate

Only when `test-command:` is set in `.claude/ship.md`. Skip silently otherwise (`SHIP_TESTS=not_configured`).
Re-derived here, not carried over from Phase 0: every block is a fresh shell.

```bash
for c in "$(dirname "${CLAUDE_SKILL_DIR:-/nonexistent}")/audit/bin/lib-orchestrator.sh" "$HOME/.claude/skills/audit/bin/lib-orchestrator.sh"; do [ -f "$c" ] && { . "$c"; break; }; done   # fresh shell per block
TEST_COMMAND=$(orch_test_command_declared) || { SHIP_TESTS=not_configured; orch_state_save SHIP_TESTS; echo "SHIP_TESTS=not_configured"; exit 0; }
if eval "$TEST_COMMAND"; then SHIP_TESTS=passed; else SHIP_TESTS=failed; fi
orch_state_save SHIP_TESTS; echo "SHIP_TESTS=$SHIP_TESTS"
```

Green → `SHIP_TESTS=passed`, continue to push. Red → `SHIP_TESTS=failed`, run the log call (`outcome=test_failed`), then STOP. Report the failing tests and do not push. Fixing them is
new work: the user commits the fixes, then re-runs `/ship` (which re-audits and re-tests).

Why this phase exists: `/audit` deliberately runs only the *affected* tests, on the assumption
that CI runs the full suite on every push. That assumption does not hold for repos whose CI only
runs on pull requests while work is pushed straight to `main` — there, nothing would ever run the
full suite before production. `TEST_COMMAND` closes that hole.

Never silently skip a red suite. A bypass must be an explicit user choice, logged like the audit
bypass.

## Phase 3: Push

```bash
git push
```

If push fails:
- "Updates were rejected" (diverged): `git pull --rebase`, then retry push
- "No upstream branch": `git push -u origin $(git branch --show-current)`
- Any other error: run the log call (`outcome=push_failed`), then report and stop

## Phase 4: Deploy

If `DEPLOY_COMMAND` is `ci`: skip this phase (`SHIP_DEPLOY=ci`, sourced block, `orch_state_save SHIP_DEPLOY`). CI/CD will deploy from the push. Phase 5 waits for that CI run before the health check.

`DEPLOY_COMMAND` is read from the audited repo's own `.claude/ship.md` (same trust boundary as
`TEST_COMMAND` in Phase 2b — see CLAUDE.md Gotchas). Everywhere else in this pipeline, a
repo-supplied step that is in its expected green state runs without asking; deploy is the
exception, because it is the one step that is both irreversible and production-facing, and
because `DEPLOY_COMMAND` is persisted once (Phase 0) and then reused silently on every later run —
nothing else in the pipeline shows it again before it executes. AskUserQuestion:
- "Deploy" (default) — show the resolved `{DEPLOY_COMMAND}` in the question text
- "Skip deploy" → `SHIP_DEPLOY=skipped` (sourced block, `orch_state_save SHIP_DEPLOY`), skip Phase 5 (nothing new was deployed, a health check would only re-check the
  old version) and go straight to Summary Output with `Deploy: skipped by user`

Otherwise run the detected/configured deploy command:
```bash
for c in "$(dirname "${CLAUDE_SKILL_DIR:-/nonexistent}")/audit/bin/lib-orchestrator.sh" "$HOME/.claude/skills/audit/bin/lib-orchestrator.sh"; do [ -f "$c" ] && { . "$c"; break; }; done   # fresh shell per block
{DEPLOY_COMMAND}
SHIP_DEPLOY=$([ $? -eq 0 ] && echo executed || echo failed); orch_state_save SHIP_DEPLOY; echo "SHIP_DEPLOY=$SHIP_DEPLOY"
```

Stream output. `SHIP_DEPLOY=executed` if it exits zero. If command exits non-zero: `SHIP_DEPLOY=failed`, jump to Phase 6.

## Phase 5: Verify

```bash
for c in "$(dirname "${CLAUDE_SKILL_DIR:-/nonexistent}")/audit/bin/lib-orchestrator.sh" "$HOME/.claude/skills/audit/bin/lib-orchestrator.sh"; do [ -f "$c" ] && { . "$c"; break; }; done   # fresh shell per block
orch_state_load   # DEPLOY_COMMAND, HEALTH_URL from Phase 0
# CI deploy: the deploy happens in the workflow the push triggered. A health check before that
# run finishes tests the previous version and reports OK for a deploy that has not happened
# (run 11, 2026-09-16). Wait for it; `gh run watch` blocks without sleeping. Call this block with
# the Bash tool's timeout at 600000 and re-run it when the tool times out: it re-finds the run.
CI_STATUS=n/a
if [ "$DEPLOY_COMMAND" = "ci" ]; then
  RUN_ID=$(gh run list --branch "$(git branch --show-current)" --limit 1 --json databaseId --jq '.[0].databaseId' 2>/dev/null)
  if [ -n "$RUN_ID" ]; then
    gh run watch "$RUN_ID" --exit-status --interval 15 >/dev/null 2>&1
    CI_STATUS=$(gh run view "$RUN_ID" --json status,conclusion --jq 'if .status=="completed" then .conclusion else .status end' 2>/dev/null || echo unknown)
    gh run view "$RUN_ID" --json url --jq .url 2>/dev/null
  else
    CI_STATUS=no_run_found   # the push may not have registered yet: re-run this block once
  fi
  echo "CI_STATUS=$CI_STATUS"
  [ "$CI_STATUS" = "success" ] || { echo "Health: skipped, CI run is $CI_STATUS (nothing new is deployed)"; HEALTH_URL=""; }
fi

# Health check. HEALTH_URL is repo-supplied (.claude/ship.md): only http(s), never a loopback,
# private, link-local or non-canonical numeric host; the parser and the filter live in the lib
# (orch_url_host / orch_host_public, 21-case test in the commit that added them).
case "$HEALTH_URL" in http://*|https://*) ;; "") ;; *) echo "Health: refusing non-http(s) URL from .claude/ship.md"; HEALTH_URL="";; esac
HEALTH_HOST=$(orch_url_host "$HEALTH_URL")
if [ -n "$HEALTH_URL" ] && ! orch_host_public "$HEALTH_HOST"; then echo "Health: refusing loopback/private/link-local/non-canonical host $HEALTH_HOST"; HEALTH_URL=""; fi
if [ -n "$HEALTH_URL" ]; then
  HTTP_STATUS=$(curl -so /dev/null -w "%{http_code}" --max-time 15 "$HEALTH_URL" 2>/dev/null)
  if [ "$HTTP_STATUS" -ge 200 ] && [ "$HTTP_STATUS" -lt 400 ]; then
    echo "Health: OK ($HTTP_STATUS) — $HEALTH_URL"
  else
    echo "Health: FAILED ($HTTP_STATUS) — $HEALTH_URL"
    # Jump to Phase 6 health-check-failed branch
  fi
else
  echo "Health: not configured (add 'health-check: https://...' to .claude/ship.md)"
fi
```

## Phase 6: Failure Handling

If `CI_STATUS` is not `success` for a `ci` deploy: run the log call (`outcome=deploy_failed`), report the run URL, stop.

If deploy failed: run the log call (`outcome=deploy_failed`), then:
```
Deploy failed.

Command: {DEPLOY_COMMAND}
Exit code: {N}
Output: {last 20 lines}

Next step: reproduce the deploy failure locally and write a regression test before fixing it.
```

If health check failed: run the log call (`outcome=health_failed`), then:
```
Deploy succeeded but health check failed.

URL: {HEALTH_URL}
Response: {curl output}

Check: app logs, recent error monitoring, or reproduce the failure locally with a regression test.
```

## Summary Output

Run the log call (`outcome=shipped`).

```
Shipped.

Docs:     {n files updated, listed / "none needed"}
Commit:   {short SHA} {message}
Push:     origin/{branch}
Deploy:   {command or "CI/CD triggered" or "skipped by user"}
Health:   {OK / FAILED / not configured}
CI run:   {url or "n/a"}
```
