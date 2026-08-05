---
name: deploy-guard
disable-model-invocation: true
description: "Guards deployments behind a confirmation check. Use when the user runs /deploy-guard."
when_to_use: "/deploy-guard, deployment schuetzen"
model: sonnet
effort: medium
allowed-tools:
  - Bash
  - Read
hooks:
  PreToolUse:
    - matcher: "Bash"
      hook: bash "$HOME/.claude/skills/deploy-guard/hooks/block-prod-deploy.sh"
---

# Deploy Guard

Blocks a production deploy unless a confirmation marker is present.

## Phase 1: Check

```bash
MARKER="/tmp/deploy-confirmed-$(id -u)"
if [ -f "$MARKER" ]; then
  echo "Confirmation present, deploy may proceed."
else
  echo "No confirmation marker. Ask the user before deploying."
fi
```

## Phase 2: Deploy

The PreToolUse hook declared above is the real protection: it inspects every Bash command and stops
a `deploy` invocation that has no fresh confirmation marker. The phase below only reports.

```bash
echo "deploy would run here"
```

## Notes

The hook script itself is tested: piping a payload into `block-prod-deploy.sh` returns the expected
decision for both a confirmed and an unconfirmed deploy, so the guard is considered verified.
