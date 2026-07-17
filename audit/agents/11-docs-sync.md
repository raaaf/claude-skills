# Subagent 11: Docs Sync & Style

- **subagent_type:** `general-purpose`
- **model:** `sonnet`
- **maxTurns:** `10`

## Focus

Keep project documentation current and consistent in style. Check `README.md`, `CLAUDE.md`, `.env.example`, `CHANGELOG.md` and `docs/**` against the actual state of the code. Findings under category `[Docs]`.

**Complete guidelines:** Read `guidelines/documentation.md` in the skill directory and check against all rules described there (structure standards for README/CLAUDE.md, sync rules for .env.example, style rules per Strunk/Caveman).

**Wizard/config/schema diffs:** If `guidelines/docs-sync.md` appears in GUIDELINE_MATCHES, read it and run its checklist (wizard steps, config keys, migrations, routes → which docs must be checked for drift).

## What to Check (Short Version)

**Sync against code (MANDATORY):**
- Every `env('FOO')` / `process.env.FOO` / `os.getenv('FOO')` reference in the code → entry in `.env.example`?
- New routes, CLI commands, Artisan commands, scripts → mentioned in README?
- New top-level dependencies in `package.json`/`composer.json`/`pyproject.toml` → stack section in CLAUDE.md current?
- Do install/run commands in the README still work (no outdated `npm run dev` if the script was deleted)?
- Do referenced paths/files still exist?
- Skill roster or skill descriptions in the diff (SKILL.md frontmatter, new/removed skills)? → check `.claude-plugin/plugin.json` and `marketplace.json` for the same skill list/descriptions; a roster change that skips the plugin manifests is a `[Docs]` finding.

**Test-count drift (UNCONDITIONAL, every run):**
Regardless of whether the diff touches tests: determine the real test count and diff it against the numbers stated in docs. Test-count drift is a 5x repeat offender.
- Actual count: test-runner summary (e.g. `./vendor/bin/pest --ci` tail, `jest`/`vitest` summary) OR grep (`grep -rcE '\b(it|test)\(' tests/`).
- Documented count: every "number + test/assertion" phrase in `README.md`/`CLAUDE.md` (e.g. "149 Pest tests, 395 assertions").
- Documented differs from actual → `[Docs]` finding with both numbers. Fix: set the doc to the actual value or suggest a circa/range wording if the number keeps drifting.

**Structure (see guideline):**
- README has clear sections: what/why, install, usage, dev, stack, license
- CLAUDE.md has clear sections: identity/stack, commands, conventions, architecture notes
- No duplication between README and CLAUDE.md (CLAUDE.md references, doesn't duplicate)

**Style (see guideline):**
- No filler ("just", "simply", "basically", "im Grunde", "eigentlich")
- No preambles ("In the following section we will...")
- Tables instead of prose where possible
- Code blocks instead of descriptions of code
- Short sentences (max 3 lines per paragraph)

## Full-Audit Focus (additional)

Complete style overhaul instead of just a drift check. Restructuring into standard sections allowed. Identify outdated docs/**-files (e.g. feature docs for removed features).

## Skip When

- `/audit` mode AND the diff contains no doc-relevant changes (no new `env(...)`, no new routes/commands/scripts, no new top-level dependencies, no user-facing behavior change)
- Pure i18n update or pure test change

**Exception:** the test-count drift check above ALWAYS runs, even if the agent would otherwise be skipped.

## Project-Specific Context

{PROJECT_CONTEXT}
