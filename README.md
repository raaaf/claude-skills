# claude-skills

A collection of Claude Code skills built for real-world development workflows. Each skill is a slash command that runs autonomously — dispatching subagents, making decisions, and producing concrete results without hand-holding.

Built and maintained by [Rafael Alex](https://rafaelalex.de).

---

## Skills

### `/audit` — Pre-Push Code Audit

Audits all uncommitted and unpushed changes across 7 dimensions before every push. Runs in a loop until clean, then verifies visual changes with screenshots before allowing a push.

**What it does:**
- Dispatches 7 specialized subagents in parallel (Architecture, Security, Performance, Code Quality, SEO, A11y, Typography)
- Auto-fixes every Critical and Important finding
- Loops until the codebase is clean (max 10 rounds)
- Runs a deterministic Bash check for visual changes — if found, a screenshot agent captures responsive screenshots headless via Playwright, shows them to you, and waits for your approval before pushing
- Logs every audit to `.claude/audits/` for historical reference
- Self-learning: dispatches a background learning agent after each run that detects patterns, updates suppressions, and suggests guideline improvements

**Subagents:** Architecture & Code Reuse · Security · Performance · Code Quality · SEO · UI/UX & A11y · Typography

**Guidelines:** Detailed best-practice references in `audit/guidelines/` — loaded by the respective subagents.

**Stack-agnostic** — works with Laravel, Next.js, Nuxt, Django, or any generic project. Project-specific rules go in your project's `CLAUDE.md` under `## Audit Context`.

---

### `/full-audit` — Full Codebase Audit

A comprehensive one-time audit of the entire codebase — not just recent changes. Processes large codebases in batches to stay within context limits.

**Use when:** Starting on a new project, after a long period without auditing, or when you want a complete picture.

**What it does:**
- Auto-detects framework and sets source directories
- Splits the codebase into batches (e.g. 12 batches for 827 files)
- Runs all 7 subagents per batch
- Produces a prioritized report with fix recommendations
- Same screenshot verification and learning loop as `/audit`

---

### `/plan` — Iterative Plan Builder

A sparring partner for turning ideas into solid implementation plans. Asks the right questions, builds a structured plan, then challenges it from 5 perspectives.

**Inspired by:** [Grill Me Skill](https://www.aihero.dev/my-grill-me-skill-has-gone-viral) — the technique of providing a recommended answer alongside every question so you only need to confirm or correct, not answer from scratch.

**What it does:**
- Phase 1: Understands the idea — max 3 questions per round, each with a recommended answer based on codebase context
- Phase 2: Writes a structured plan to `docs/plans/{date}-{slug}.md`
- Phase 3: Dispatches 5 challenge agents in parallel, consolidates concerns, lets you decide what to incorporate

**Challenge agents:** CEO/Founder · Senior Engineer · Designer · Skeptic · Minimalist

---

### `/dsgvo` — DSGVO Compliance Check

Audits websites for GDPR/DSGVO compliance (German law). Works with live URLs and local project code. Produces a prioritized report, concrete code fixes, and optionally generates ready-to-use legal texts.

**What it does:**
- Detects external services via Bash/curl: Google Fonts, Analytics, Maps, YouTube, CDNs, Facebook Pixel, Hotjar, and more
- Dispatches 5 subagents in parallel: Impressum · Datenschutzerklärung · Cookie Consent · External Services · Technical
- Outputs findings as Kritisch / Wichtig / Nice-to-have with one-line fixes
- Offers to generate Datenschutzerklärung, Impressum, and Cookie banner copy based on detected services

**Covers:** § 5 DDG, DSGVO Art. 6/13/14, ePrivacy, LG München I Google Fonts ruling (2022), Dark Pattern rules, WordPress-specific pitfalls (Gravatar, WP Emojis, XML-RPC)

---

## Installation

```bash
git clone https://github.com/rafaelalex/claude-skills ~/.claude/skills/claude-skills

# Then symlink individual skills
ln -s ~/.claude/skills/claude-skills/audit ~/.claude/skills/audit
ln -s ~/.claude/skills/claude-skills/full-audit ~/.claude/skills/full-audit
ln -s ~/.claude/skills/claude-skills/plan ~/.claude/skills/plan
ln -s ~/.claude/skills/claude-skills/dsgvo ~/.claude/skills/dsgvo
```

For the `/audit` screenshot feature, install Playwright:

```bash
cd ~/.claude/skills/audit/bin && npm install
```

Screenshots run fully headless — no browser window opens.

---

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

## Screenshot auth

The screenshot agent logs into your app before capturing screenshots. Credentials are stored per project in `.claude/auth.json` (gitignored, never committed). If a seeder file exists with test credentials, the agent extracts them automatically.

```json
{
  "loginUrl": "/login",
  "username": "admin@example.com",
  "password": "secret"
}
```

---

## How Claude Code skills work

Skills are Markdown files that Claude Code reads and executes as slash commands. A `SKILL.md` is a precise instruction set — not a vague prompt. Subagents are separate Markdown files dispatched in parallel via the Agent tool, each with a focused scope.

- [Claude Code Docs](https://docs.anthropic.com/claude/claude-code)
- [aihero.dev](https://www.aihero.dev) — community skills and patterns

---

## Inspiration

- [aihero.dev — Grill Me Skill](https://www.aihero.dev/my-grill-me-skill-has-gone-viral) — recommended-answer-per-question technique used in `/plan`
- [LG München I — Google Fonts Urteil (2022)](https://rewis.io/urteile/urteil/lhm-20-01-2022-3-o-1749420/) — legal basis for the Google Fonts finding in `/dsgvo`
- [§ 5 DDG](https://www.gesetze-im-internet.de/ddg/__5.html) — Impressumspflicht
- [DSGVO Art. 13](https://dsgvo-gesetz.de/art-13-dsgvo/) — Informationspflichten bei Datenerhebung

---

## License

MIT
