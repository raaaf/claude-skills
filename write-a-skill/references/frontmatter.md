# Frontmatter Reference

- [Trigger and identity](#trigger-and-identity): `name`, `description`, `when_to_use`, `argument-hint`, `arguments`, `paths`
- [The description budget](#the-description-budget-matters-more-than-it-looks): the 1,536-char cap and the listing budget
- [Invocation control](#invocation-control): `disable-model-invocation`, `user-invocable`
- [Execution environment](#execution-environment): `model`, `effort`, `allowed-tools`, `disallowed-tools`, `hooks`, `shell`
- [Forked execution](#forked-execution): `context`, `agent`, `background`, and the background-by-default trap
- [String substitutions](#string-substitutions-in-the-body): `$ARGUMENTS`, `$name`, `${CLAUDE_SKILL_DIR}` and friends
- [Repo defaults](#repo-defaults)

Every field Claude Code supports on a `SKILL.md`, what it is good for, and the version it needs.
Verified against the official skills documentation (code.claude.com/docs/en/skills), August 2026.
All fields are optional; only `description` is genuinely recommended.

Booleans accept `true`/`false`, and since v2.1.218 also `yes`/`no`/`on`/`off`/`1`/`0` in any case.
Stick to `true`/`false` in this repo: it works on every version.

## Trigger and identity

| Field | What it does |
|---|---|
| `name` | Display label in skill listings. For personal and project skills it does NOT set the command name, that comes from the directory name. Only in plugin skills does `name` set the last command segment. |
| `description` | What the skill does and when to use it. This is the trigger text Claude matches against. |
| `when_to_use` | Extra trigger phrases, appended to `description` in the listing. |
| `argument-hint` | Autocomplete hint, e.g. `[issue-number]`. |
| `arguments` | Named positional arguments for `$name` substitution. Space-separated string or YAML list. |
| `paths` | Glob patterns that gate automatic activation: the skill auto-loads only when the work touches matching files. Comma-separated string or YAML list. Pointless together with `disable-model-invocation: true`: that already blocks auto-loading entirely. |

### The description budget (matters more than it looks)

`description` + `when_to_use` are **capped at 1,536 characters combined** per skill
(`skillListingMaxDescChars` changes the cap). On top of that, the whole skill listing has a budget
of ~1% of the model's context window. When the listing overflows, Claude Code **drops descriptions
starting with the skills you invoke least**, so an over-long description in one skill can silently
cost a rarely used skill its trigger text.

Consequences for writing:

- Put the key use case in the **first sentence**; truncation eats the tail.
- Trim before you hit the cap, don't write up to it.
- `/doctor` estimates the listing's context cost and names the biggest contributors. The Skills row
  in `/context` shows the size after the budget is applied.
- Levers if the listing is tight: `skillListingBudgetFraction` (e.g. `0.02`), the
  `SLASH_COMMAND_TOOL_CHAR_BUDGET` env var, or setting low-priority skills to `"name-only"` in the
  `skillOverrides` setting.

## Invocation control

| Field | What it does |
|---|---|
| `disable-model-invocation` | `true` prevents Claude from auto-loading the skill (manual `/name` only). Also blocks preloading into subagents, and since v2.1.196 blocks scheduled-task invocation, never set it on a skill that runs on a schedule. |
| `user-invocable` | `false` hides the skill from the `/` menu. For background knowledge that Claude should load but users should not invoke. |

## Execution environment

| Field | What it does |
|---|---|
| `model` | Model while the skill is active: `opus`, `sonnet`, `haiku`, `fable`, or `inherit`. Applies for the rest of the turn, not saved to settings. Use `inherit` (or omit) when the skill should run on whatever the session picked. |
| `effort` | `low`, `medium`, `high`, `xhigh`, `max`. Overrides session effort. Available levels depend on the model. |
| `allowed-tools` | Tools pre-approved for the invoking turn (permission grant, NOT a tool pool). Space/comma string or YAML list. Grant clears with the next user message. |
| `disallowed-tools` | Tools removed from the pool while the skill is active. This one really does remove, use it for autonomous skills that must never call `AskUserQuestion`. |
| `hooks` | Hooks scoped to this skill's lifecycle. |
| `shell` | `bash` (default) or `powershell` for inline `` !`command` `` blocks. |

`allowed-tools` supports `${CLAUDE_SKILL_DIR}` substitution, which makes bundled scripts run without
a prompt when the same path is used in the body:

```yaml
allowed-tools: Bash(${CLAUDE_SKILL_DIR}/bin/scan.sh *)
```

Needs v2.1.129+ for the substitution in `allowed-tools`; `${CLAUDE_PROJECT_DIR}` needs v2.1.196+.

## Forked execution

| Field | What it does |
|---|---|
| `context` | `fork` runs the skill in an isolated subagent. The skill body becomes the subagent's prompt; there is no conversation history. |
| `agent` | Which agent type executes the fork (`Explore`, `Plan`, `general-purpose`, or a custom one from `.claude/agents/`). Defaults to `general-purpose`. |
| `background` | Only with `context: fork`. `false` waits for the result inside the invoking turn. Needs v2.1.218+. |

**The trap:** since v2.1.218 a forked skill runs in the **background by default**, and a background
subagent gets a narrower built-in tool set: `Read`, `Grep`, `Glob`, `Bash`, `Edit`, `Write`,
`WebFetch`, `WebSearch`, `TodoWrite`, `Skill`, `ToolSearch`, `SendMessage`, `Artifact` and a few
more. Everything else is stripped, whether inherited or listed. If the skill produces a report the user
is waiting for, or needs a tool outside that set, set `background: false`.

`context: fork` only makes sense for skills that contain an actual task. A guideline-style skill
forked into a subagent gives the subagent rules and no work, and it returns nothing useful.

## String substitutions in the body

| Variable | Expands to |
|---|---|
| `$ARGUMENTS` | All arguments as typed. If absent from the body, arguments are appended as `ARGUMENTS: <value>`. |
| `$ARGUMENTS[N]` / `$N` | One argument by 0-based index. Shell-style quoting, so `"two words"` stays one argument. |
| `$name` | Named argument declared in `arguments:`. Missing → empty string (indexed placeholders stay literal instead). |
| `${CLAUDE_SKILL_DIR}` | The skill's own directory. Use it for bundled scripts instead of guessing install paths. |
| `${CLAUDE_PROJECT_DIR}` | Project root. |
| `${CLAUDE_SESSION_ID}` | Session ID, for per-session log files. |
| `${CLAUDE_EFFORT}` | `low` … `max`. Lets one skill scale its own depth; ultracode reports as `xhigh`. |

Escape a literal `$` before a digit or name with a backslash: `\$1.00`.

**Headless invocation gotcha:** in `claude -p "/my-skill do the thing in English"`, everything after
the skill name is the argument. Extra instructions glued onto the invocation therefore arrive as
`$ARGUMENTS` and can be parsed as a scope hint, a dimension, or a file path. This silently corrupted
the audit eval harness for months. Put the skill argument in the prompt and everything else in
`--append-system-prompt`.

## Repo defaults

- `disable-model-invocation: true` unless auto-triggering is the point (`/find-skills`, `/delegate`)
  or the skill runs on a schedule (`/live-audit`: the flag would kill the schedule).
- `model: opus` for orchestrators, worker routing by task type. Omit `model` when the skill should
  ride the session model (`/delegate`).
- Named `arguments:` over positional `{N}` placeholders.
