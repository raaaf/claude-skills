# claude-skills

Repo of Claude Code skills. Each skill is a slash command implemented in Markdown + Bash, no runtime.

## Stack

- Markdown + YAML frontmatter (skill orchestrator)
- Bash for deterministic logic (`audit/bin/`, `~/.claude/hooks/`)
- Claude Code 2.1.150+ frontmatter features: `model`, `effort`, `allowed-tools`, `maxTurns`
- No dependencies — no npm, no composer, no venv (single exception: vendored `/find-skills` shells out to `npx skills`)

## Architecture

Each skill follows the same shape:

```
skill-name/
  SKILL.md              orchestrator (under 500 lines)
  agents/*.md           subagent definitions (one per worker)
  references/*.md       on-demand details (TOC if >100 lines)
  guidelines/*.md       content best practices loaded by workers
  bin/*.sh              deterministic helpers (audit only)
  evals/                fixture-based recall measurement (audit only)
```

Key invariants:

- **Orchestrator writes, subagents return.** Subagents cannot write under `.claude/` (hardcoded permission protection, also under `bypassPermissions`). Learning, suppression, log files: structured output → parsed by orchestrator → written by orchestrator.
- **Single source of truth.** `/full-audit` references `../audit/agents/` instead of duplicating. Same for `guidelines/`. Edit once.
- **Frontmatter `model: opus`**, not pinned versions. Resolves to latest Opus on Anthropic API. Pin only on Bedrock/Vertex/Foundry.
- **Worker model routing.** Haiku for pattern-matching (0-triage, 4-code-quality, 5-seo, 7-typography, 8-ui-design, 10-animation). Sonnet for reasoning (1-arch, 3-performance, 6-a11y, 9-ux, 11-docs-sync, 12-copy, fix-agent, fix-verifier, learning-agent). Opus for 2-security (exploit reasoning).
- **Platform support.** `detect-framework.sh` emits `PLATFORM=web|native|cross` (laravel/nextjs/nuxt/django vs ios/android vs react-native/flutter). Native projects: workers 2/3/6/7/8/9 additionally read `guidelines/native-mobile.md`; Swift/Kotlin/Dart count as frontend files; `check-i18n-keys.sh` handles `.lproj` and `values-*/strings.xml`.

## Commands

| Command | Purpose |
|---|---|
| `bash ~/.claude/hooks/sync-skills.sh` | Copy + zip skills to `~/.claude/skills/` after edits |
| `bash audit/bin/verify-agents.sh audit/agents` | Verify all 17 required agent files present |
| `bash audit/bin/check-i18n-keys.sh [root]` | Deterministic i18n key-set diff across locales |
| `bash audit/bin/check-outdated.sh [root] [--security-only]` | Dependency vulnerabilities (audit-grade) + outdated majors (full-audit only) |
| `bash audit/evals/run-evals.sh` | Run eval suite against fixtures (recall + false-positive count) |
| `echo "..." \| bash audit/bin/normalize-suppression.sh` | Test the semantic dedup key for a suppression |
| `bash audit/bin/perf-measure.sh --detect` / `--run "<cmd>"` | Verify-by-measurement helper for performance fixes (detect `perf-measure:` command, run it, emit `PERF_METRIC`) |
| `bash feature-audit/bin/run-tests.sh [FILE]` | Run the `test-command:` from FEATURE_AUDIT.md, report real `TEST_EXIT=<code\|none>` |
| `bash feature-audit/bin/status-line.sh FILE <exit>` | Parse FEATURE_AUDIT.md table + needs-review, emit the deterministic `AUDIT_STATUS` line |
| `echo '<triage-json>' \| bash audit/bin/check-skips.sh [framework]` | Deterministic sanity-floor over the haiku triage routing: derive file signals from git, force obvious wrong skips back on, emit the `Routing:` line |
| `bash audit/bin/match-guidelines.sh <guidelines-dir>` | Per-file guideline selection: which guidelines' `applies_to` ERE matches the diff (emit `name<TAB>priority<TAB>scoped\|always`); no-frontmatter guidelines are always applicable |

## Conventions

- **SKILL.md under 500 lines.** If approaching, split into `references/*.md` (one level deep, never nested).
- **Reference files >100 lines need a TOC** at top.
- **YAML `name` is lowercase + hyphens**, no `claude`/`anthropic`. Description in third person, includes both *what* and *when*.
- **No emojis. No em-dashes.** German prose uses real umlauts (ä, ö, ü, ß) only in user-facing content; agent definitions use ae/oe/ue/ss to avoid encoding edge cases.
- **Frontmatter for skills** sets `model: opus`, `effort: high|xhigh`, `allowed-tools: [...]`, optional `hooks: { PreToolUse: ... }`.
- **Frontmatter for agents** sets `subagent_type`, `model`, `maxTurns`. No system instructions in frontmatter — those live in the body.
- **Finding output cap** is 50 words, only `file:line` refs, no code snippets. Enforced in `audit/agents/prompt-template.md`.
- **Hook safety:** never `claude` from inside a Stop/PreToolUse hook (would spawn an infinite loop). All hooks live in `~/.claude/hooks/`, not the repo.

## Skill roster

| Skill | Model | Purpose |
|---|---|---|
| `/audit` | opus | Pre-push diff audit, 12 dimensions, fix-loop |
| `/full-audit` | opus | Full codebase audit, batched |
| `/feature-audit` | opus | Goal-loop: FEATURE_AUDIT.md matrix, one test per feature, drive to all-green |
| `/ship` | sonnet | Commit + audit gate + push + deploy + verify |
| `/diagnose` | sonnet | Reproduce-first bug diagnosis, regression test |
| `/review` | sonnet | Two-axis review: Standards + Spec (parallel agents) |
| `/triage` | sonnet | GitHub issue state machine, agent briefs |
| `/handoff` | sonnet | Session compaction to /tmp for fresh agent |
| `/plan-it` | opus | Iterative plan builder, parallel challenges |
| `/write-a-skill` | opus | Skill scaffolding |
| `/live-audit` | sonnet | Scheduled live-site audit (personal) |
| `/rafael-writing-style` | sonnet | Personal writing style (personal) |
| `/improve` | sonnet | Product-perspective analysis: feature gaps, growth, business |
| `/mockup` | sonnet | Photorealistic design mockups via Nano Banana Pro / ImageMagick (personal) |
| `/produktbild` | sonnet | AI lifestyle product images via Nano Banana Pro (personal) |
| `/produktvideo` | sonnet | AI lifestyle video via Runway Gen-4 (personal) |
| `/find-skills` | sonnet | Skill discovery/install via npx skills (third-party, vendored) |

## Effort levels (set on skill frontmatter or via `CLAUDE_EFFORT`)

| Level | /audit | /full-audit | /plan-it |
|---|---|---|---|
| low | 1 round | 1 round/batch, no Cross-Ref | 3 challenges, no eval, no learning |
| medium | 2 rounds, fix Minor | 2 rounds/batch, fix Minor | 4 challenges, no eval |
| high / xhigh (default) | 3 rounds, fix Minor | 3 rounds/batch, Cross-Ref always | 5 challenges, full eval |

Issue policy: GitHub issues only for decision points the user explicitly defers (fix now / defer / dismiss prompt at audit end). Minor findings never become issues; unconfirmed low-confidence findings are verified or dropped, never tracked. At audit start (Phase 0.2), open `audit-finding` issues are offered for fixing in the same run (closed via `gh issue close` after a verified fix); open PRs are collected as dedup context — no issue is created for something an open PR already addresses.

## Project-specific overrides

Projects can override globals by adding files to their own `.claude/`:

- `.claude/audit-guidelines.md` — read in `audit` Phase 1, takes precedence over global `guidelines/*.md`. May also declare a `perf-measure: <cmd>` line to enable verify-by-measurement for performance fixes (see Gotchas)
- `.claude/plan-guidelines.md` — read in `plan-it` Phase 0.7, threaded to all challenge agents
- `.claude/audits/learning-log.md` — auto-generated per-project audit history
- `.claude/audits/suppressions.json` — auto-generated dismissed-finding list
- `.claude/plans/logs/*.md` — auto-generated per-plan logs

## Gotchas

- **Per-file guideline selection (`applies_to` + `priority`).** A guideline may declare `applies_to: <ERE>` (matched against the diff's changed file paths) and `priority: non_negotiable|mandatory|recommended` in YAML frontmatter. `match-guidelines.sh` (SKILL.md Phase 1) emits which guidelines match the diff; workers load only the listed ones (prompt-template.md "Guideline-Scope" rule) and use `priority` as a severity anchor (non_negotiable→Critical, mandatory→Important, recommended→Minor). **Backward compatible:** a guideline without `applies_to` is always applicable, so migration is incremental and never silently drops a guideline. Migrated so far: `atomic-design`, `data-migrations`, `native-mobile`, `seo`, `typography`, `ui-animation`; project-level (`theme-fork`) and global (`security`, `code-quality`, …) stay always-on. Concept borrowed from mcp-context-toolkit (`query_rules_for_file`); single ERE per file, no YAML-list parser. bash 3.2 safe.
- **Triage routing has a deterministic floor + is now visible.** The triage agent (haiku) decides which workers run; haiku is the cheapest model gating the whole audit, so `audit/bin/check-skips.sh` (SKILL.md Schritt C.0.5) derives file-type signals from git and forces obvious wrong skips back on (frontend files present but a11y/ui/ux off, etc.) before dispatch. It also emits a `Routing:` line printed every round and written to the audit log under `## Routing`, so every skip is visible with a reason. The floor only forces dims with a clear file signal (a11y/ui/ux/copy/typography/architecture/code_quality/security); perf/seo/animation/docs_sync stay with the triage to avoid false floors. Fails open (all dims run) if jq is missing or the JSON is unparseable. bash 3.2 safe.
- **Verify-by-measurement is opt-in and deterministic.** Performance fixes are only measured (baseline before / re-measure after / verdict from the delta) when `PERF_MEASURE_CMD` or a `perf-measure:` line in `.claude/audit-guidelines.md` is set; the command must print exactly one `PERF_METRIC=<number>` line (lower = better). The before/after comparison is plain Bash in `audit/SKILL.md` Schritt E/E.5, not an LLM judgment — by design (Bash decides branching). No command set → unchanged fix-verifier peer-review. `--detect` emits a `printf %q`-quoted assignment so `eval` reconstructs commands with spaces; don't "simplify" it back to a bare `echo`. Full flow + honest limits (per-round aggregate, not per-finding): `audit/references/perf-measurement.md`. Inspired by AvdLee's Xcode-Build-Optimization skill.
- **`.claude/` write block applies in foreground too.** Earlier learning agents tried `mode: bypassPermissions` and still failed. The fix is always: subagent returns structured output, orchestrator parses + writes.
- **Pre-push marker and `git push` must be separate Bash calls.** The PreToolUse hook scans the command string for `git push` and blocks before any marker write in the same call would execute. See `audit/SKILL.md` Phase 4.
- **Two marker-hash conventions — never mix them.** `/tmp/claude-audit-passed-*` hashes the cwd WITHOUT trailing newline (`echo -n "$PWD" | md5`; same in the settings.json PreToolUse hook via `printf '%s'`). `/tmp/claude-audit-in-progress-*` hashes WITH newline (`pwd | md5`; same in `pre-compact.sh`). Each family is internally consistent; reading one family with the other convention silently produces a different hash (this exact bug broke ship's audit gate once).
- **`sync-skills.sh` only runs in the claude-skills working directory.** Edits to `~/.claude/skills/audit/SKILL.md` directly are not synced anywhere — always edit in this repo and let the Stop hook copy.
- **Plan mode on `model: opus` switches to Sonnet during execution** if you use `opusplan` globally. Skill frontmatter override (`model: opus`) keeps it on Opus end-to-end.
- **`maxTurns` on agents is a hard limit.** A worker that exceeds it returns whatever it has, including partial findings. Triage and fix-agent need slack (5 turns minimum); fix-verifier is tighter (3-5 is plenty).
- **Worker output never includes code snippets.** Findings reference `file:line` only. This is by design — keeps consolidation cheap and prevents the worker from being a code generator.
- **Stop-hook `additionalContext` does NOT block.** Verified against the hooks docs (June 2026): `hookSpecificOutput.additionalContext` on Stop/SubagentStop lets the stop proceed and only injects context. The audit loop needs blocking to force the next round — `exit 2` in `~/.claude/hooks/audit-loop.sh` stays. Don't "modernize" this.
- **`PreCompact` hook blocks auto-compaction during audit runs.** `~/.claude/hooks/pre-compact.sh` checks for `/tmp/claude-audit-in-progress-{cwd-hash}`. Marker is written in `audit/SKILL.md` Phase 1 and removed in Phase 6. Markers older than 3 hours are treated as stale and auto-removed.
- **`disable-model-invocation: true`** is set on all skills except `/rafael-writing-style` and `/find-skills` (auto-triggering is intended for both). Claude never auto-triggers the others; only explicit `/skill-name` invocations work. Required for destructive/long-running skills like `/audit`, `/full-audit`, and for paid-API skills (`/mockup`, `/produktbild`, `/produktvideo`).
- **`${CLAUDE_SKILL_DIR}`** expands to the skill's own directory. Used in `audit/SKILL.md` for `AUDIT_BIN` and `AUDIT_AGENTS_DIR`. Replaces the old `${CLAUDE_PROJECT_DIR:-$HOME/.claude/skills/audit}` pattern. `full-audit/SKILL.md` uses it as the first candidate in the AUDIT_ROOT resolution loop.
- **`disallowed-tools`** on `/handoff` and `/triage` blocks `AskUserQuestion` — both are fully autonomous and should never interrupt for input.
- **Named `arguments:`** on `/review` (`$target`) and `/triage` (`$issue`) replace positional `{N}` placeholders.

## Adding a new skill

Use `/write-a-skill` if available, or follow this minimum:

1. Create `new-skill/SKILL.md` with frontmatter (`name`, `description`, `model`, `effort`, `allowed-tools`).
2. Add `agents/` for any subagents you dispatch.
3. Add `references/` for content over 100 lines.
4. Add `guidelines/` for opinionated best practices the agents should follow.
5. Run `bash ~/.claude/hooks/sync-skills.sh` to deploy locally.
6. Update root `README.md` to list the new skill.

## Adding a 2026 best-practice section to an existing guideline

Edit `audit/guidelines/{name}.md`. Append a new Roman-numeral section (e.g. `## XVI. New Topic (2026)`). Keep the file under 500 lines — if it would go over, split into a continuation file (`{name}-2026.md`, see `code-quality-2026.md`) and reference both in the worker's agent file. Don't rewrite existing content — additive only unless something is genuinely wrong.

## Release process

There isn't one. Push to `main`, Stop hook syncs to `~/.claude/skills/`, next Claude Code session picks up the changes.
