---
name: ship
disable-model-invocation: true
description: |
  Full commit-audit-push-deploy pipeline in one command. Stages tracked changes, generates
  a conventional commit message (or uses the provided one), enforces audit before push,
  deploys via project-specific method, and verifies the deploy. Use when ready to ship
  completed work. Never pushes without a clean audit marker.
when_to_use: "/ship, ready to ship, commit and deploy, commit push deploy, ship this, release this"
argument-hint: "[optional: commit message]"
arguments: [message]
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

Commit -> Audit -> Push -> Deploy -> Verify. In that order. No skipping.

## Phase 0: Pre-flight

```bash
# Must be in a git repo
git rev-parse --show-toplevel 2>/dev/null || { echo "Not a git repo."; exit 1; }

# Check for changes to ship
git status --short
git diff --stat HEAD 2>/dev/null
```

If no tracked changes and no staged files: report and stop. Nothing to ship.

Detect deploy method (check in priority order):

```bash
# 1. Project config (wins)
cat .claude/ship.md 2>/dev/null

# 2. Known deploy files
[ -f fly.toml ]                                          && echo "DEPLOY=fly deploy"
[ -f vapor.yml ] || [ -f vapor.yaml ]                   && echo "DEPLOY=vapor deploy production"
[ -f "deploy.sh" ]                                       && echo "DEPLOY=bash deploy.sh"
[ -f .vercel/project.json ]                              && echo "DEPLOY=vercel --prod"
[ -f netlify.toml ]                                      && echo "DEPLOY=netlify deploy --prod"
[ -f railway.toml ]                                      && echo "DEPLOY=railway up"
ls .github/workflows/deploy*.yml 2>/dev/null | head -1  && echo "DEPLOY=ci" # CI deploys on push
```

If no method found: AskUserQuestion with options:
- "CI/CD deploys on push (no extra command)" → set `DEPLOY=ci`
- "fly deploy"
- "vercel --prod"
- "Custom..." (user types the command)

Then write the chosen command to `.claude/ship.md`:
```bash
echo "deploy-command: {command}" >> .claude/ship.md
```
(Skip write if DEPLOY=ci or file already exists.)

## Phase 1: Commit

Show what will be committed:
```bash
git diff --stat HEAD 2>/dev/null
git status --short
```

**If `$message` is set:** use it as the commit message (skip generation).

**If no `$message`:** read the diff and generate a conventional commit message:
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
CWD_HASH=$(pwd | md5 2>/dev/null || pwd | md5sum 2>/dev/null | cut -d' ' -f1)
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

## Phase 3: Push

```bash
git push
```

If push fails:
- "Updates were rejected" (diverged): `git pull --rebase`, then retry push
- "No upstream branch": `git push -u origin $(git branch --show-current)`
- Any other error: report and stop

## Phase 4: Deploy

If `DEPLOY=ci`: skip this phase. CI/CD will deploy from the push.

Otherwise run the detected/configured deploy command:
```bash
{DEPLOY_COMMAND}
```

Stream output. If command exits non-zero: jump to Phase 6.

## Phase 5: Verify

```bash
# CI status (if gh available)
gh run list --limit 1 --json status,conclusion,url 2>/dev/null

# Health check (if URL configured in .claude/ship.md or detectable)
HEALTH_URL=""
grep -q "health-check:" .claude/ship.md 2>/dev/null && HEALTH_URL=$(grep "health-check:" .claude/ship.md | cut -d' ' -f2)

# Fallback: infer from fly.toml app name or vercel output
if [ -n "$HEALTH_URL" ]; then
  curl -sf --max-time 10 "$HEALTH_URL" && echo "Health: OK" || echo "Health: FAILED ($HEALTH_URL)"
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
