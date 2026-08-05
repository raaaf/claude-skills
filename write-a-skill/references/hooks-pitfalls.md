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

## The path pitfall: a skill hook cannot find its own skill

A hook declared in `SKILL.md` frontmatter receives exactly three path variables:
`CLAUDE_PROJECT_DIR`, `CLAUDE_PLUGIN_ROOT`, `CLAUDE_PLUGIN_DATA`. There is no `CLAUDE_SKILL_DIR`,
even though the skill body and the `allowed-tools` field both support it. That asymmetry is easy to
miss, because the same string looks correct in all three places.

The tempting form is wrong in a way that never reports an error:

```yaml
# BAD: resolves to <audited project>/hooks/guard.sh in every real session
hook: bash "${CLAUDE_PROJECT_DIR:-$HOME/.claude/skills/my-skill}/hooks/guard.sh"
```

`CLAUDE_PROJECT_DIR` points at the project being worked on, not at the skill, and the `:-` default
only fires when the variable is *unset*, which it never is. So the path lands in the audited
project, the file is not there, and the hook silently does nothing. In this repo both of `/audit`'s
PreToolUse guards were dead this way for months, including the one that blocks worktree-wide
`git stash` during parallel fix waves, which exists because such a command once destroyed another
agent's work.

Probe the install locations instead, and fail OPEN when none matches:

```yaml
hook: bash -c 'for c in "$HOME/.claude/skills/my-skill" "$HOME/.claude/skills/my-repo/my-skill"; do [ -f "$c/hooks/guard.sh" ] && exec bash "$c/hooks/guard.sh"; done; exit 0'
```

`exec` keeps stdin, so the hook script still receives the tool JSON. `exit 0` on the miss path is
deliberate: a `PreToolUse` hook that cannot find its script must not block every Bash call in a
project that has nothing to do with the skill.

**Test it, because nothing else will.** A dead hook produces no error, no log line and no failed
run. Pipe a payload into the hook command and check both directions:

```bash
echo '{"tool_input":{"command":"git stash"},"cwd":"/tmp"}' | bash -c '<your hook command>'   # expect the block, exit 2
echo '{"tool_input":{"command":"git status"},"cwd":"/tmp"}' | bash -c '<your hook command>'  # expect exit 0
HOME=/nonexistent ... # expect exit 0, fail open
```

## The frontmatter shape pitfall: `hook:` instead of `hooks:`

The skill frontmatter schema is nested, not a flat key:

```yaml
# correct
hooks:
  PreToolUse:
    - matcher: Bash
      hooks:
        - type: command
          command: "bash \"$HOME/.claude/skills/my-skill/hooks/guard.sh\""

# wrong: silently rejected
hook: bash "$HOME/.claude/skills/my-skill/hooks/guard.sh"
```

A top-level `hook:` key holding a bare command string is rejected outright, and the entire event
block is dropped with it. Nothing surfaces at the point of failure: no parse error, no warning in
the transcript, the tool call the hook was meant to guard just runs unguarded. The only trace is a
line in the debug log (`claude --debug`):

```
Invalid hooks in skill '<name>'
```

Check that log after writing or changing any skill-frontmatter hook. If the line is there, the
event block was dropped and the hook never ran regardless of what its script does.

## The single-consumption stdin pitfall: two guards, one pipe

`PreToolUse` hooks receive the tool call payload as JSON on stdin. Stdin can be read exactly once.
Chaining two independent guard scripts under the same matcher, each reading stdin for itself, gives
the payload to the first and an empty pipe to the second — the second guard silently sees nothing to
block, and reports success on every call whether or not the dangerous pattern is present.

Wrong:

```yaml
hooks:
  PreToolUse:
    - matcher: Bash
      hooks:
        - type: command
          command: "bash guard-a.sh"   # reads stdin, consumes it
        - type: command
          command: "bash guard-b.sh"   # reads stdin, gets nothing
```

Fix: use one dispatcher entry that reads stdin once and feeds the same string to every guard, then
aggregates the result (block if any guard blocks):

```bash
#!/usr/bin/env bash
INPUT=$(cat)
echo "$INPUT" | bash guard-a.sh || exit 2
echo "$INPUT" | bash guard-b.sh || exit 2
exit 0
```

Also remember exit 2 is not the only output shape: exit 0 plus a JSON
`hookSpecificOutput.permissionDecision` of `allow`, `deny`, or `ask` (PreToolUse only) is the richer
alternative when the hook needs to explain itself instead of just blocking silently — see "Output
formats" above.
