# claude-skills

Claude Code skills for real development work. Each one is a slash command that runs on its own: it dispatches subagents, makes the routine decisions, and leaves you a result and a log.

Built and maintained by [Rafael Alex](https://rafaelalex.de).

## Skills

| Command | What it does |
|---|---|
| `/audit` | Audits your uncommitted and unpushed changes before a push. 13 dimensions, verified findings, one fix wave, then the push is unlocked. |
| `/full-audit` | The same pipeline over a whole codebase. No push gate. |
| `/design-audit` | Visual pass over the entire frontend: typography, color, spacing, motion, visual accessibility. Reports first, fixes only what you pick. |
| `/feature-audit` | Turns a feature list into a test matrix and drives it to all green. |
| `/plan-it` | Interviews you, writes an executor-grade plan, challenges it from five perspectives. `execute` runs it in a worktree and reviews the result. |
| `/delegate` | Default way to implement: the session model writes a mini-spec, Sonnet builds it, the session model reviews the diff. |
| `/review` | Two-axis code review: project standards and the linked spec. |
| `/diagnose` | Reproduce-first bug diagnosis with a regression test. |
| `/ship` | Docs sync, commit, audit gate, push, deploy, verify. |
| `/triage` | GitHub issue state machine with agent briefs. |
| `/handoff` | Compacts the session into a handoff file for a fresh agent. |
| `/improve` | Product perspective: feature gaps, growth, business. |
| `/app-baseline` | Onboards an app onto a 12-point production baseline. |
| `/baseline-check` | Checks an existing app against that baseline. |
| `/write-a-skill` | Scaffolds a new skill in this shape. |

## How an audit runs

1. Deterministic pre-checks: secrets, lockfile drift, i18n keys, dependency vulnerabilities, CI hardening.
2. Two start questions: which dimensions, and whether to fix nothing, Critical only, or Critical and Important. Minor is logged, never fixed.
3. `find.js`, one Workflow pipeline per dimension in parallel: a scout picks the relevant files (a content-based floor guarantees the obvious ones), specialists read chunks of 5 to 8 files, a fresh verifier confirms or refutes every finding, an Opus refuter double-checks each Critical.
4. You decide per confirmed finding: fix, log, discard.
5. `fix.js`: one fixer per file, a fix-verifier per 3 to 5 fixes, a regression pass over everything touched, then the test suite once.
6. Log with cost line, push marker if nothing Critical is open.

Sonnet does all the reading and fixing, Opus only the refuting. Measured on a 257-file WordPress theme: 27 to 42 minutes and 73 to 124 USD for the whole codebase, where the previous batch-and-rounds design took 22 hours and around 760 USD.

## Install

```bash
git clone https://github.com/raaaf/claude-skills ~/Developer/claude-skills
cd ~/Developer/claude-skills
for s in */; do [ -f "$s/SKILL.md" ] && ln -sfn "$PWD/${s%/}" ~/.claude/skills/"${s%/}"; done
ln -sfn "$PWD/agents" ~/.claude/agents
```

Symlinks, not copies: an edit in the clone is live in the next session. `audit`, `full-audit` and `design-audit` share `audit/agents/`, install them together. Needs Claude Code 2.1.218 or newer, `git` and `jq`. No other dependencies.

## Configure per project

- `.claude/audit-guidelines.md`: project rules the audit workers read first. Optional lines `perf-measure: <command that prints PERF_METRIC=<number>>` for measured performance fixes and `scope-extensions: md` to widen the full-audit scope.
- `.claude/plan-guidelines.md`: rules every plan challenger gets.
- `AUDIT_DIMENSIONS=security,a11y` and `AUDIT_FIX_SCOPE=none|critical|all` skip the start questions, for CI or headless runs.
- `CLAUDE_EFFORT=low|medium|high` preselects the fix scope.

Audit logs land in `.claude/audits/`, plans in `docs/plans/`, learnings in `.claude/audits/learning-log.md`. Logs reference `file:line`, never file contents, so they are safe to commit.

## Development

`CLAUDE.md` is the contributor guide: conventions, invariants, and the gotchas that cost real time. `bash audit/bin/verify-agents.sh audit/agents` checks the agent roster, `audit/evals/` holds the fixture-based recall suite.

## Inspiration

- [Grill Me Skill](https://www.aihero.dev/my-grill-me-skill-has-gone-viral): the recommended-answer-per-question technique in `/plan-it`
- [Matt Pocock's write-a-skill](https://github.com/mattpocock/skills/blob/main/skills/productivity/write-a-skill/SKILL.md): description and body-size discipline
- [shadcn/improve](https://github.com/shadcn/improve): executor-grade plan template and the worktree execute-and-review loop

## Hi, I'm Rafael

<img src="docs/avatar.png" alt="Rafael Alex" width="88" align="left">

I design and build websites, apps and AI tools. Alone, from Fürth, Germany. These skills are how I actually work, published as they evolve.

More at [rafaelalex.de](https://rafaelalex.de).

<br clear="left">

## License

MIT
