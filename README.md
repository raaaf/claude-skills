# claude-skills

A collection of Claude Code skills built for real-world development workflows. Each skill is a slash command that runs autonomously — dispatching subagents, making decisions, and producing concrete results without hand-holding.

Built and maintained by [Rafael Alex](https://rafaelalex.de).

---

## Skills

### `/audit` — Pre-Push Code Audit

Audits all uncommitted and unpushed changes before every push. A triage agent routes the diff to only the relevant subagents, parallel fix-agents handle repairs, and you get a manual test plan for visual verification.

**What it does:**
- Runs fast deterministic pre-checks first (secret scan, lockfile drift, diff-size gate) before spending tokens on LLMs
- Triage agent (Haiku) reads the diff once and routes hotspots to relevant subagents only — workers receive only their assigned hotspots plus a short summary, never the full diff (saves 40-60% input tokens per worker dispatch)
- Dispatches up to 10 specialized subagents in parallel (Architecture, Security, Performance, Code Quality, SEO, A11y, Typography, UI Design, UX, Animation) — model per worker tuned for the task: Haiku for pattern-matching dimensions (Code Quality, SEO, Typography, UI Design, Animation), Sonnet for reasoning-heavy dimensions (Architecture, Performance, A11y, UX), Opus for Security
- Workers read files on-demand via the Read tool (max 5 files per run) when hotspots alone don't suffice
- Findings are capped at 50 words each with no code snippets (only file:line references) — keeps consolidation cheap
- Incremental cache: unchanged files since last audit are skipped entirely
- Validates every finding against the filesystem to filter hallucinations before fixing
- Parallel fix-agents (Haiku) repair findings grouped by file
- Loops until clean (max 3 rounds) with convergence check and minor-only early-exit
- Generates a manual test plan for visual changes (specific pages, routes, what to check)
- Logs every audit to `.claude/audits/` (timestamped — multiple runs per day preserved)
- Self-learning: records fix patterns, tracks dismissed findings, suggests suppressions after 3 dismissals

**Subagents:** Architecture & Code Reuse · Security · Performance · Code Quality · SEO · A11y (WCAG) · Typography · UI Visual Design · UX Patterns · Animation & Motion

**Guidelines:** Detailed best-practice references in `audit/guidelines/` — loaded by the respective subagents.

**Stack-agnostic** — works with Laravel, Next.js, Nuxt, Django, or any generic project. Project-specific rules go in your project's `CLAUDE.md` under `## Audit Context`.

---

### `/full-audit` — Full Codebase Audit

A comprehensive one-time audit of the entire codebase — not just recent changes. Processes large codebases in batches to stay within context limits.

**Use when:** Starting on a new project, after a long period without auditing, or when you want a complete picture.

**What it does:**
- Auto-detects framework and sets source directories
- Splits the codebase into batches (e.g. 12 batches for 827 files)
- Runs up to 10 subagents per batch (same set as `/audit`)
- Auto-fixes all findings (Critical, Important, and Minor) per batch
- Cross-reference round after all batches to catch cross-module inconsistencies
- Generates a manual test plan for visual verification
- Same learning loop as `/audit`

---

### `/plan-it` — Iterative Plan Builder

A sparring partner for turning ideas into solid implementation plans. Asks the right questions, builds a structured plan, then challenges it from 5 perspectives.

**Inspired by:** [Grill Me Skill](https://www.aihero.dev/my-grill-me-skill-has-gone-viral) — the technique of providing a recommended answer alongside every question so you only need to confirm or correct, not answer from scratch.

**What it does:**
- Phase 1: Framing-Check + Codebase-Scan + decision-tree interview (max 3 questions per round, each with a recommended answer)
- Phase 2: Writes a structured plan to `docs/plans/{date}-{slug}.md` with rounds heuristic (2/3/4+ depending on complexity)
- Phase 2.5: Gathers codebase context (directory structure, patterns, framework) for Architecture and Risk agents
- Phase 3: Dispatches 5 challenge agents in parallel, consolidates concerns with explicit dedupe step, lets you decide what to incorporate
- Phase 3.5: Final evaluation pass (completeness, sequence, effort, risks, implementability) by Tech Lead agent
- Phase 4: Logs the plan session and dispatches a learning agent that detects patterns in user preferences across plans

**Challenge agents:** Product · Architecture (with codebase context) · Design · Risk (with codebase context) · Simplicity

---

### `/write-a-skill` — Skill Scaffolding

Creates new skills following the canonical structure: orchestrator (max 120 lines) + agents/ for parallel workers + references/ for progressive disclosure. Inspired by [Matt Pocock's write-a-skill](https://github.com/mattpocock/skills/blob/main/skills/productivity/write-a-skill/SKILL.md), adapted for our subagent + hooks + self-learning patterns.

**Includes references for:**
- Description discipline (the only thing the model sees when picking a skill)
- Subagent pattern (when to add, model routing, output format discipline)
- Hooks pitfalls (recursion guards, never spawn `claude` from a hook)
- Self-learning pattern (foreground dispatch, suggestions not auto-apply)
- Review checklist (frontmatter, body, references, smoke test)

---

## Installation

```bash
git clone https://github.com/raaaf/claude-skills ~/.claude/skills/claude-skills

# Then symlink individual skills
ln -s ~/.claude/skills/claude-skills/audit ~/.claude/skills/audit
ln -s ~/.claude/skills/claude-skills/full-audit ~/.claude/skills/full-audit
ln -s ~/.claude/skills/claude-skills/plan-it ~/.claude/skills/plan-it
ln -s ~/.claude/skills/claude-skills/write-a-skill ~/.claude/skills/write-a-skill
```

**Note:** `audit` and `full-audit` must be installed together — `full-audit` references agent definitions from `audit/agents/`. The skill resolves the path automatically (sibling directory, `~/.claude/skills/audit/`, or mono-repo layout).

## Project-specific configuration

The audit skills are stack-agnostic. Add a `## Audit Context` section to your project's `CLAUDE.md` for framework-specific rules:

```markdown
## Audit Context

Framework: Laravel 11, Livewire 3, Blade

### Security
- All Livewire components must use #[Locked] on public properties not meant for user input
...
```

The skill auto-detects your framework (Laravel, Next.js, Nuxt, Django, generic) and injects this context into every subagent.

---

## Architecture

Each skill follows a consistent pattern:

```
SKILL.md (orchestrator)
  -> Dispatches subagents in parallel (agents/*.md)
     -> Each agent reads guidelines/references on demand (progressive disclosure)
  -> Consolidates results
  -> Auto-fixes findings
  -> Logs the run
  -> Dispatches learning agent in background
```

**Key design decisions:**
- **Frontmatter controls behavior** — `model`, `allowed-tools`, `maxTurns`, `context: fork`, `effort`, `hooks` are all set per-skill
- **Descriptions are model triggers** — written in English, telling Claude *when* to invoke the skill, not what it does
- **Progressive disclosure** — large reference material lives in separate files; subagents read only what they need
- **Worker isolation** — subagents receive only triage-routed hotspots, not the full diff. Read files on-demand via the Read tool (max 5 files per run). Cuts input tokens 40-60% per worker dispatch
- **Strict output format** — every finding is capped at 50 words, no code snippets (only file:line references), enforced via the shared `agents/prompt-template.md`. Keeps consolidation cheap
- **Per-worker model tuning** — Haiku for pattern-matching, Sonnet for reasoning, Opus only where genuinely needed (Security)
- **Deterministic control flow** — Bash scripts decide branching (secret scans, diff-size gates, cache checks), not LLM judgment
- **Self-learning** — every skill logs its runs and dispatches a background learning agent that detects patterns and suggests improvements
- **On-demand hooks** — `/audit` registers a `PreToolUse` hook that blocks `git push` unless the audit passed

---

## How self-learning works

Every skill (`/audit`, `/full-audit`, `/plan-it`) dispatches a learning agent after each run.

**What the learning agent does:**
1. **Reads recent logs** — the last N runs from `.claude/audits/` (or `.claude/plans/`)
2. **Detects patterns** — findings that recur across runs, false positives that keep getting re-flagged, user overrides that keep getting applied
3. **Proposes three types of improvements:**
   - **Suppressions** — if the same false positive appears in ≥3 runs, propose adding it to the skill's ignore-list
   - **Guideline updates** — if a genuine issue keeps being found in the same shape, propose a new rule in `guidelines/` or `references/`
   - **Prompt tweaks** — if a subagent consistently misses or hallucinates something, propose a prompt adjustment
4. **Writes to `learning-log.md`** — every suggestion is logged, never silently applied. The user can review suggestions there at their own pace.

**Why foreground, not background:** Background subagents cannot write to `.claude/` (hardcoded permission protection that even `bypassPermissions` does not override, and background subagents cannot prompt). Foreground costs ~5-10s at the end of each run but reliably persists the learning.

**Why suggestions, not auto-apply:** Skill rules affect every future run. Silent auto-updates would drift the skill away from the user's intent without review.

---

## How Claude Code skills work

Skills are Markdown files that Claude Code reads and executes as slash commands. A `SKILL.md` is a precise instruction set — not a vague prompt. Subagents are separate Markdown files dispatched in parallel via the Agent tool, each with a focused scope.

- [Claude Code Docs](https://docs.anthropic.com/claude/claude-code)
- [aihero.dev](https://www.aihero.dev) — community skills and patterns

---

## Inspiration

- [aihero.dev — Grill Me Skill](https://www.aihero.dev/my-grill-me-skill-has-gone-viral) — recommended-answer-per-question technique used in `/plan-it`
- [Matt Pocock's write-a-skill](https://github.com/mattpocock/skills/blob/main/skills/productivity/write-a-skill/SKILL.md) — basis for our `/write-a-skill` (description discipline, 100-line limit, review checklist)

---

## License

MIT
