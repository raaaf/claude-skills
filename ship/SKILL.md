---
name: ship
description: |
  Full commit-audit-test-push-deploy pipeline in one command. Stages tracked changes, generates
  a conventional commit message (or uses the provided one), enforces audit and (where the project
  configures one) the full test suite before push, deploys via project-specific method, and
  verifies the deploy. Use when ready to ship completed work. Push requires a fresh audit marker
  and a green suite; bypassing either is only possible as an explicit, logged user decision,
  never silently.
when_to_use: "/ship, ready to ship, commit and deploy, commit push deploy, ship this, release this"
argument-hint: "[optional: commit message]"
model: sonnet
effort: medium
allowed-tools:
  - Read
  - Write
  - Bash
  - Glob
  - AskUserQuestion
---

# Ship

Commit -> Audit -> Tests -> Push -> Deploy -> Verify. In that order. No skipping.
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
# 1. Project config wins — read the values if present
DEPLOY_COMMAND=$(grep '^deploy-command:' .claude/ship.md 2>/dev/null | cut -d' ' -f2-)
HEALTH_URL=$(grep '^health-check:' .claude/ship.md 2>/dev/null | cut -d' ' -f2-)
TEST_COMMAND=$(grep '^test-command:' .claude/ship.md 2>/dev/null | cut -d' ' -f2-)

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
if [ ! -f .claude/ship.md ]; then
  mkdir -p .claude
  {
    echo "deploy-command: ${DEPLOY_COMMAND}"
    [ -n "$HEALTH_URL" ] && echo "health-check: ${HEALTH_URL}"
  } > .claude/ship.md
  echo "Created .claude/ship.md"
fi
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

Check staged diff for sensitive files:
```bash
git diff --cached --name-only | grep -E '(\.env|secret|credential|\.pem|\.key)'
```
If found: warn and AskUserQuestion — continue or abort?

```bash
git commit -m "{message}"
```

If commit fails (hook rejection, empty): report the hook output and stop.

## Phase 2: Audit Gate

```bash
CWD_HASH=$(echo -n "$PWD" | md5 2>/dev/null || echo -n "$PWD" | md5sum 2>/dev/null | cut -d' ' -f1)
MARKER="/tmp/claude-audit-passed-${CWD_HASH}"

if [ -f "$MARKER" ]; then
  AGE=$(( $(date +%s) - $(stat -f%m "$MARKER" 2>/dev/null || stat -c%Y "$MARKER" 2>/dev/null) ))
  if [ "$AGE" -lt 1800 ]; then
    echo "Audit marker fresh (${AGE}s ago). Proceeding to push."
  else
    echo "STALE: Audit marker is ${AGE}s old (limit: 1800s)."
    MARKER_FRESH=0
  fi
else
  echo "MISSING: No audit marker found."
  MARKER_FRESH=0
fi
```

If marker missing or stale: AskUserQuestion:
- "Run /audit now" → invoke the audit skill (`/audit`), then re-check marker. If audit fails: stop.
- "Push without audit (risky)" → log the bypass and continue with a warning in the output

Never silently skip the audit. The bypass must be an explicit user choice.

## Phase 2b: Test Gate

Only when `TEST_COMMAND` is set (`test-command:` in `.claude/ship.md`). Skip silently otherwise.

```bash
eval "$TEST_COMMAND"
```

Green → continue to push. Red → STOP. Report the failing tests and do not push. Fixing them is
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
- Any other error: report and stop

## Phase 4: Deploy

If `DEPLOY_COMMAND` is `ci`: skip this phase. CI/CD will deploy from the push.

Otherwise run the detected/configured deploy command:
```bash
{DEPLOY_COMMAND}
```

Stream output. If command exits non-zero: jump to Phase 6.

## Phase 5: Verify

```bash
# CI run status
gh run list --limit 1 --json status,conclusion,url 2>/dev/null

# Health check — HEALTH_URL was resolved in Phase 0
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

If deploy failed:
```
Deploy failed.

Command: {DEPLOY_COMMAND}
Exit code: {N}
Output: {last 20 lines}

Next step: /diagnose — describe the deploy failure as the bug.
```

If health check failed:
```
Deploy succeeded but health check failed.

URL: {HEALTH_URL}
Response: {curl output}

Check: app logs, recent error monitoring, or run /diagnose.
```

## Summary Output

```
Shipped.

Commit:   {short SHA} {message}
Push:     origin/{branch}
Deploy:   {command or "CI/CD triggered"}
Health:   {OK / FAILED / not configured}
CI run:   {url or "n/a"}
```
