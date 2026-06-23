# claude-skills

A collection of Claude Code skills built for real-world development workflows. Each skill is a slash command that runs autonomously: dispatches subagents, makes decisions, produces concrete results without hand-holding.

Built and maintained by [Rafael Alex](https://rafaelalex.de).

## Skills

### `/audit` — Pre-Push Code Audit

Audits all uncommitted and unpushed changes before every push. A triage agent routes the diff to relevant subagents, parallel fix-agents handle repairs, peer-review verifiers check every fix, manual test plan covers visual changes.

**Pipeline:**

1. Phase 0: Learning-Backlog-Check (asks before each audit if past improvement suggestions should be implemented); Phase 0.2 offers open `audit-finding` issues for fixing in this run and collects open PRs as dedup/conflict context
2. Phase 0.5: Effort Configuration (low / medium / high — scales rounds, Minor fixing, confidence floor)
3. Phase 1: Pre-flight (secret scan, lockfile drift, diff-size gate, deterministic i18n key-set check, project-specific guidelines from `.claude/audit-guidelines.md`)
4. Phase 2: Audit-loop with triage routing, 12 specialized workers, hallucination validator, fix-agents, fix-verifier peer review (performance fixes additionally use verify-by-measurement when a `perf-measure:` command is configured: baseline before, re-measure after, verdict from the metric delta)
5. Phase 2.5: Cross-Reference pass when diff touches >=3 files (skip on low effort)
6. Phase 3: Post-loop (changelog, linter, tests, manual test plan; open decision points go to the user — fix now / defer as issue / dismiss. Issues only for explicit deferrals, never for Minor findings)
7. Phase 4: Pre-push gate (marker-based, never in the same Bash call as `git push`)
8. Phase 5: Learning (subagent returns structured output, orchestrator writes `learning-log.md` and `suppressions.json`)
9. Phase 6: PR creation if applicable

**Worker dispatch (12 dimensions, parallel):**

| # | Dimension | Model |
|---|---|---|
| 0 | Triage | haiku |
| 1 | Architecture | sonnet |
| 2 | Security | opus |
| 3 | Performance | sonnet |
| 4 | Code Quality | haiku |
| 5 | SEO | haiku |
| 6 | A11y (WCAG 2.2) | sonnet |
| 7 | Typography | haiku |
| 8 | UI Visual Design | haiku |
| 9 | UX Patterns | sonnet |
| 10 | Animation | haiku |
| 11 | Docs Sync | sonnet |
| 12 | Copy & UX-Writing | sonnet |

Triage routes the diff to relevant workers only; workers receive triage-marked hotspots, never the full diff. Saves 40-60% input tokens per worker.

**Platform support:** web (Laravel, Next.js, Nuxt, Django) and native mobile (iOS, Android, React Native, Flutter). Framework detection sets `PLATFORM`; on native projects the security/performance/a11y/typography/UI/UX workers switch to `guidelines/native-mobile.md` (Keychain/Keystore, VoiceOver/TalkBack, Dynamic Type, main-thread, HIG/Material), and the i18n pre-check reads `.lproj` bundles and `values-*/strings.xml`.

**Per-finding output cap:** 50 words, no code snippets, only `file:line` refs.

### `/full-audit` — Full Codebase Audit

Comprehensive one-time audit of an entire codebase. Auto-detects framework, batches large codebases (>80 files), runs Phase 0 backlog check, Phase 0.5 dimension selection (Alles / Nur Backend / Nur Frontend / Custom multi-select), Phase 0.7 effort configuration. Cross-Reference pass after all batches (xhigh runs it even in SINGLE mode).

Same 12 worker definitions as `/audit` (`audit/agents/*.md` are the single source of truth).

### `/feature-audit` — Feature Test Matrix (Goal-Loop)

Builds and maintains `FEATURE_AUDIT.md`: a canonical table of every user-facing feature, route,
command, or exported entry point, with one automated test per row, and drives the suite to
all-green. This is a **goal-driven loop** (the right shape for open-ended, long-horizon work —
unlike the deterministic pre-push `/audit`). It detects the stack, ensures a test runner (with
confirmation before installing one), derives coverage from source, writes and runs tests per row,
fixes until the suite exits 0 without weakening assertions, re-verifies, then writes a holistic
`FEATURE_REVIEW.md` (Inconsistencies / Gaps / Potentials).

**Loop contract:** every turn ends with a machine-checkable status line
(`AUDIT_STATUS total=… with_story=… tested=… passing=… failing=… needs_review=… test_exit=…`).
Both the counts and `test_exit` are **computed by Bash helpers** (`bin/status-line.sh` parses the
table, `bin/run-tests.sh` reports the real process exit code), never self-reported by the model, so
completion is objectively checkable. State lives in the committed `FEATURE_AUDIT.md`, so the loop
survives interruption and resumes. Commits per passing feature (branch-first on the default
branch, scoped staging — never `git add -A`). Stops after 3 consecutive identical failures or 50
turns. Pair with `/loop /feature-audit` for the unattended grind.

### `/diagnose` — Bug Diagnosis Workflow

Reproduce-first debugging. Never hypothesizes before a working repro exists. Minimizes the
reproduction to the smallest failing case, forms ranked hypotheses, instruments precisely,
fixes, writes a regression test, and removes all debug output.

**Pipeline:**

1. Phase 0: Intake (expected vs actual, last known good)
2. Phase 1: Reproduce (one command, one output, deterministic — STOP if unrepro)
3. Phase 2: Minimize (smallest failing case, exact file:line)
4. Phase 3: Hypothesize (2-3 ranked, evidence-based only)
5. Phase 4: Instrument (max 2 debug points, test hypothesis)
6. Phase 5: Fix (surgical, re-run repro to confirm)
7. Phase 6: Regression test (fails pre-fix, passes post-fix)
8. Phase 7: Cleanup (no debug output in committed code)

### `/review` — Two-Axis Code Review

Checks implementation from two independent angles in parallel. Use before merging a feature
branch or when you want to verify a PR matches its spec. Complements `/audit` (which is
pre-push and automated); `/review` is manual and spec-aware.

**Axes (parallel):**

| Axis | Question | Agent |
|---|---|---|
| Standards | Does the code follow project conventions and guidelines? | standards-reviewer (sonnet) |
| Spec | Does the implementation match the linked issue or PRD? | spec-reviewer (sonnet) |

If no issue/PR is linked: Standards axis only.

Findings: max 50 words, file:line refs only, no code snippets. Critical and Important findings
require resolution (fix, accepted deviation, or spec update). Minor findings are listed only.

### `/handoff` — Session Compaction

Compacts the current session into a self-contained handoff document for a fresh agent or a
new session. Includes: what was done, commits made, current state, next steps, open questions,
key files, and suggested skills. Saves to `/tmp/` (never committed). Redacts tokens and keys.

### `/triage` — GitHub Issue State Machine

Fetches open `needs-triage` issues (or a specific issue number), classifies them, updates
labels, posts reasoning comments, and generates agent briefs for issues ready to work
autonomously. Requires `gh` CLI and a GitHub remote.

**States:** `needs-triage` (entry) → `needs-info` / `ready-for-agent` / `ready-for-human` / `wontfix`

`ready-for-agent` issues get an agent brief with task description, likely files, acceptance
criteria, and suggested skills.

### `/ship` — Commit, Audit, Push, Deploy

Full pipeline from "changes ready" to "live in production." Generates a conventional commit
message from the diff (or uses the one you provide), enforces the audit marker before push,
runs the project-specific deploy command, and verifies with a health check.

**Pipeline:**

1. Phase 0: Pre-flight (git status, detect deploy method from `fly.toml`/`vapor.yml`/`deploy.sh`/`.vercel`/CI, or save to `.claude/ship.md` on first run)
2. Phase 1: Commit (diff summary, generate conventional commit message, AskUserQuestion to confirm or edit, `git add -u`, sensitive-file check, `git commit`)
3. Phase 2: Audit gate (marker fresh < 30 min? skip. Stale or missing? AskUserQuestion: run `/audit` now or bypass explicitly)
4. Phase 3: Push (`git push`, auto-handles no-upstream and diverged branches)
5. Phase 4: Deploy (run detected command; skip if CI/CD deploys on push)
6. Phase 5: Verify (`gh run list` + health check if URL configured)
7. Phase 6: Failure handling (last 20 lines of output + `/diagnose` pointer)

**Arguments:**
```bash
/ship                     # auto-generate commit message
/ship "feat: add login"   # explicit commit message, no prompt
```

**Config** (`.claude/ship.md`, auto-created on first run):
```
deploy-command: fly deploy
health-check: https://myapp.fly.dev/health
```

### `/plan-it` — Iterative Plan Builder

Sparring partner for turning ideas into solid implementation plans. Asks the right questions (each with a recommended answer), builds a structured plan, then challenges it from 5 perspectives.

**Pipeline:**

1. Phase 0: Learning-Backlog-Check
2. Phase 0.5: Effort Configuration (low = 3 challenges no eval, medium = 4 challenges no eval, high/xhigh = 5 challenges full)
3. Phase 0.7: Project guidelines (`.claude/plan-guidelines.md`)
4. Phase 1: Framing-Check + Codebase-Scan + decision-tree interview
5. Phase 2: Write structured plan to `docs/plans/{date}-{slug}.md`
6. Phase 2.5: Codebase context for Architecture and Risk agents
7. Phase 3: Parallel challenges (Product · Architecture · Risk · Simplicity · Design), explicit dedupe step, user decides what to incorporate
8. Phase 3.5: Final evaluation pass
9. Phase 4: Learning (structured output, orchestrator writes)

**Inspired by:** [Grill Me Skill](https://www.aihero.dev/my-grill-me-skill-has-gone-viral).

### `/write-a-skill` — Skill Scaffolding

Creates new skills following the canonical structure: orchestrator + `agents/` for parallel workers + `references/` for progressive disclosure + `guidelines/` for content best practices. Inspired by [Matt Pocock's write-a-skill](https://github.com/mattpocock/skills/blob/main/skills/productivity/write-a-skill/SKILL.md).

## Personal skills

Two more skills live in this repo as architecture examples. They are wired to personal infrastructure and not meant for reuse — read them for patterns, not for installing.

- **`/live-audit`** — Scheduled weekly live-site audit (PageSpeed Insights API + SSL check) for my own domains. New findings become GitHub Issues in the matching repo; a suppress-label closes the learning loop. Shows: Scheduled-Tasks-MCP integration, API-based auditing without a browser, issue dedup.
- **`/rafael-writing-style`** — My personal writing style for blog posts, web copy, and emails. Shows: how to encode tone-of-voice rules as a skill.

## Stack

| | |
|---|---|
| Format | Markdown + YAML frontmatter |
| Hooks | Bash scripts in `~/.claude/hooks/` (sync, audit-loop, format) |
| Runtime | Claude Code 2.1.150+ (uses skill frontmatter `model`, `effort`, `allowed-tools`) |
| Model resolution | `model: opus` alias (auto-resolves to latest Opus on Anthropic API) |
| Dependencies | none — no npm, no composer, no Python venv |

## Installation

```bash
git clone https://github.com/raaaf/claude-skills ~/.claude/skills/claude-skills

# Symlink each skill (or use sync-skills.sh if you cloned alongside another location)
ln -s ~/.claude/skills/claude-skills/audit       ~/.claude/skills/audit
ln -s ~/.claude/skills/claude-skills/full-audit  ~/.claude/skills/full-audit
ln -s ~/.claude/skills/claude-skills/plan-it     ~/.claude/skills/plan-it
ln -s ~/.claude/skills/claude-skills/write-a-skill ~/.claude/skills/write-a-skill
```

`audit` and `full-audit` must be installed together — `full-audit` references agent definitions from `audit/agents/`. Path is auto-resolved (sibling directory, `~/.claude/skills/audit/`, or mono-repo layout).

## Project-specific configuration

Each skill reads an optional project-local override file. Drop it in your project's `.claude/` directory:

| Skill | Override file | Effect |
|---|---|---|
| /audit, /full-audit | `.claude/audit-guidelines.md` | Project rules take precedence over global `guidelines/*.md` |
| /plan-it | `.claude/plan-guidelines.md` | Project conventions threaded to all challenge agents |

Example:

```markdown
# Project Audit Overrides

Tech-Stack: Laravel 11 + Livewire 3 + Spatie Permissions

## Security
- Always use Spatie\Permission for role checks, never `$user->role === 'admin'`
- All Livewire components: `#[Locked]` on properties not meant for user input
```

**Verify-by-measurement for performance fixes (opt-in).** Add a `perf-measure:` line to `.claude/audit-guidelines.md` (or set `PERF_MEASURE_CMD`) with a command that prints exactly one line `PERF_METRIC=<number>` (lower is better). `/audit` then measures the metric before and after the round's performance fixes and decides `keep` vs revert from the real delta, instead of a subjective peer-review. Without it, performance fixes fall back to the fix-verifier. Examples (bundle bytes, build seconds, query count) and the full flow live in `audit/references/perf-measurement.md`.

```
perf-measure: npx size-limit --json | jq -r '"PERF_METRIC=\([.[].size]|add)"'
```

## Effort scaling

All three skills respect `CLAUDE_EFFORT`:

| Level | /audit | /full-audit | /plan-it |
|---|---|---|---|
| low | 1 round, no Minor, no Learning | 1 round/batch, no Cross-Ref, no Learning | 3 challenges, no eval, no learning |
| medium | 2 rounds, fix Minor, floor=medium | 2 rounds/batch, fix Minor, Cross-Ref BATCHED-only | 4 challenges, no eval |
| high / xhigh (default) | 3 rounds, fix Minor, floor=low | 3 rounds/batch, Cross-Ref always, fix Minor | 5 challenges, full eval |

```bash
CLAUDE_EFFORT=low claude /audit              # quick WIP-Push check
FULL_AUDIT_DIMENSIONS=security claude /full-audit  # security-only sweep
```

## Architecture

```
SKILL.md (orchestrator)
  -> Dispatches subagents in parallel (agents/*.md)
     -> Each agent reads guidelines/*.md on demand (progressive disclosure)
  -> Hallucination validator (filesystem checks)
  -> Auto-fixes via fix-agent subagents
  -> Fix-verifier peer-reviews each applied fix
  -> Cross-reference pass for multi-file diffs
  -> Logs run + dispatches learning agent (returns structured output)
  -> Orchestrator writes .claude/audits/ or .claude/plans/
```

**Key design decisions:**

- **Frontmatter controls behavior** — `model`, `effort`, `allowed-tools`, `maxTurns`, `hooks` set per-skill
- **Descriptions are model triggers** — third-person, written for *when* to invoke, not what it does
- **Progressive disclosure** — large reference material lives in separate files; subagents read only what they need (SKILL.md under 500 lines, references one level deep)
- **Worker isolation** — subagents receive only triage-routed hotspots, read files on-demand (max 5 per run)
- **Per-worker model tuning** — Haiku for pattern-matching dimensions, Sonnet for reasoning-heavy dimensions
- **Deterministic control flow** — Bash scripts decide branching (secret scans, diff-size gates, cache checks), not LLM judgment
- **Orchestrator-only `.claude/` writes** — subagents are blocked by hardcoded path protection; they return structured output, orchestrator parses and writes
- **Semantic suppression dedup** — `bin/normalize-suppression.sh` produces stable keys so paraphrased dismissals collapse into one
- **Hooks separate from skill** — `~/.claude/hooks/audit-loop.sh` (Stop), `block-unsafe-push.sh` (PreToolUse Bash), `auto-format.sh` (PostToolUse Edit)

## How self-learning works

Every skill dispatches a learning agent (Sonnet) after each run.

1. **Reads recent logs** — all runs from `.claude/audits/` or `.claude/plans/`
2. **Computes trends** — Critical/Important trend over last 3 runs, top dimension over last 5, recurrers in 3+ runs
3. **Returns structured output**:
   - `LEARNING_LOG_ENTRY` (markdown with `- [ ]` backlog of improvement suggestions)
   - `TRENDS_BLOCK` (top-of-log snapshot, replaced not appended)
   - `SUPPRESSIONS_TO_ADD` (audit only; normalized for semantic dedup)
4. **Orchestrator writes** — `learning-log.md` (append for entries, top-replace for trends) + `suppressions.json` (merged with dedup)

**Phase 0 picks up the backlog on the next run** — user is asked whether to implement the open `- [ ]` suggestions before the next audit/plan starts.

## Eval suite

`audit/evals/` contains a scaffold for measuring audit recall:

```bash
bash ~/.claude/skills/audit/evals/run-evals.sh
```

Fixtures live under `audit/evals/fixtures/{security,a11y,performance}/`, expected findings under `audit/evals/expected/`. Three example fixtures (Laravel SQLi, missing-aria Blade, Eloquent N+1) ship with the repo. Add a new fixture every time the audit misses a real-world bug — over time the eval becomes a real benchmark.

Status: scaffold. Three fixtures are a smoke test, not a benchmark.

## Development

```bash
# After editing a skill, sync to ~/.claude/skills/ for local use:
bash ~/.claude/hooks/sync-skills.sh

# Verify all referenced agent files exist:
bash audit/bin/verify-agents.sh audit/agents

# Test the suppression normalizer:
echo "[Security] LIKE wildcard injection" | bash audit/bin/normalize-suppression.sh
```

**Adding a new skill:**

```bash
claude /write-a-skill name-of-new-skill
```

Follow the canonical structure: orchestrator (under 500 lines, references kept one level deep) + agents/ + references/ + guidelines/.

## Inspiration

- [Grill Me Skill](https://www.aihero.dev/my-grill-me-skill-has-gone-viral) — recommended-answer-per-question technique used in `/plan-it`
- [Matt Pocock's write-a-skill](https://github.com/mattpocock/skills/blob/main/skills/productivity/write-a-skill/SKILL.md) — description discipline, body-size discipline

## License

MIT
