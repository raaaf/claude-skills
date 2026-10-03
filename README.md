# claude-skills

Claude Code skills for real development work. Each one is a slash command that runs on its own: it dispatches subagents, makes the routine decisions, and leaves you a result and a log.

Built and maintained by [Rafael Alex](https://rafaelalex.de).

## Skills

| Command | What it does |
|---|---|
| `/audit` | Reviews your uncommitted and unpushed changes like a PR before a push: deterministic checks, the built-in `/code-review`, one fix round, then the push is unlocked. |
| `/plan-it` | Interviews you, writes an executor-grade plan that ends in a /delegate-ready spec, challenges it (architecture and risk always; product, design, simplicity when the plan calls for them). `execute` runs it in a worktree and reviews the result. |
| `/delegate` | Default way to implement: the session model writes a mini-spec, Sonnet builds it, the session model reviews the diff. |
| `/ship` | Docs sync, commit, audit gate, push, deploy, verify. |
| `/screens` | Builds and maintains a complete screenshot catalog of every view in every state, plus App-Store marketing renders. Incremental after the first run. |
| `/store-assets` | Renders App Store / Play Store screenshot stills from a project's own app screens and a project-local config: real device bezels, a fixed headline/device grid, a two-phone hero composition. |

Archived skills: /full-audit and /design-audit were removed on 2026-10-02; restore with `git checkout archive/pre-slim-2026-10-02 -- full-audit design-audit`.

## How an audit runs

1. Deterministic pre-checks: secrets, lockfile drift, i18n keys, dependency vulnerabilities, CI hardening, docs claims.
2. The built-in `/code-review high` reviews the diff in a temporary worktree. When the diff touches auth, payment or privacy paths, one extra checklist agent reviews those paths for policy bypass, third-party data flow without consent, payment correctness and secrets in logs.
3. The orchestrator reads every finding and decides: fix, or discard with a stated reason.
4. One executor fixes, the test suite runs once.
5. Log with cost line, push marker if nothing Critical or Important is open.

A prose-only diff gets the deterministic checks only. A pre-push audit is a PR review, so it costs about as much as one.

## Install

```bash
git clone https://github.com/raaaf/claude-skills ~/Developer/claude-skills
cd ~/Developer/claude-skills
for s in */; do [ -f "$s/SKILL.md" ] && ln -sfn "$PWD/${s%/}" ~/.claude/skills/"${s%/}"; done
ln -sfn "$PWD/agents" ~/.claude/agents
```

Symlinks, not copies: an edit in the clone is live in the next session. Needs Claude Code 2.1.218 or newer, `git` and `jq`. No other dependencies.

## Configure per project

- `.claude/audit-guidelines.md`: project rules the audit reads during triage.
- `.claude/plan-guidelines.md`: rules every plan challenger gets.

Audit logs land in `.claude/audits/`, plans in `docs/plans/`. Logs reference `file:line`, never file contents, so they are safe to commit.

## Development

`CLAUDE.md` is the contributor guide: conventions, invariants, and the gotchas that cost real time. `bash audit/bin/check-docs-claims.sh` checks that the docs name only files that exist.

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
