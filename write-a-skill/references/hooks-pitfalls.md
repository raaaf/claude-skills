# Hooks: Pitfalls and Patterns

Hooks run automatically on tool events. They can amplify a skill or burn down your machine. Read this before adding any hook.

## The recursion pitfall

NEVER spawn `claude` (the CLI) inside a hook script. Reason:

1. Hook fires after a tool event in your main session
2. Your hook runs `claude --model haiku -p ...` to do something LLM-shaped
3. That subprocess starts a NEW Claude Code session
4. New session loads ALL your plugins, MCP servers, skills (~300-500 MB RAM)
5. New session ends -> Stop event fires in subprocess -> your same hook fires again
6. Recursive subprocess explosion -> RAM full -> crash

The `stop_hook_active` guard works only inside the SAME session. Subprocess sessions have their own state.

If you genuinely need an LLM call in a hook, call the Anthropic API directly via `curl https://api.anthropic.com/v1/messages` with an API key. This skips the entire Claude Code stack.

## Hook events overview

| Event | Fires | Use for |
|---|---|---|
| `PreToolUse` | Before any tool call | Block dangerous commands, gate `git push`, redirect file writes |
| `PostToolUse` | After tool succeeds | Auto-format, log changes |
| `UserPromptSubmit` | When user submits a prompt | Inject routing context, prefix detection |
| `SessionStart` | New session opens | Install deps, show worktree hint |
| `Stop` | Assistant turn ends | Cleanup, post-processing, audit-loop |
| `Notification` | Claude Code shows a permission/idle prompt | External notification (terminal bell, etc.) |

## Output formats

### Block silently (exit 2)
```bash
exit 2
```
Stop is blocked. Reason printed to stderr is shown to the user.

### Block with structured reason (JSON)
```json
{
  "hookSpecificOutput": {
    "hookEventName": "PreToolUse",
    "permissionDecision": "ask",
    "permissionDecisionReason": "Are you sure?"
  }
}
```
Triggers an interactive prompt. Only valid for PreToolUse.

### Inject extra context
```json
{
  "hookSpecificOutput": {
    "hookEventName": "UserPromptSubmit",
    "additionalContext": "Note: user used haiku: prefix"
  }
}
```

## Anti-recursion guards

Always include for Stop hooks that could re-trigger:
```bash
INPUT=$(cat)
if echo "$INPUT" | grep -q '"stop_hook_active"[[:space:]]*:[[:space:]]*true'; then
    exit 0
fi
```

For PreToolUse hooks that could trigger themselves via tool calls in their own logic: usually not a concern, but worth sanity-checking.

## Disable switches

Always provide an environment variable to disable the hook for ad-hoc situations:
```bash
if [ "${SKILL_X_DISABLE:-0}" = "1" ]; then
    exit 0
fi
```

User can `export SKILL_X_DISABLE=1 && claude` to skip the hook for one session.

## Performance

Hooks run synchronously and block the next tool call until they exit. Keep them under 200ms. Heavy work (parsing transcripts, calling APIs) belongs in subprocesses spawned with `&` if at all.

## Documentation

Document every hook in your skill's README:
- What event it fires on
- What it does
- How to disable
- What can go wrong
