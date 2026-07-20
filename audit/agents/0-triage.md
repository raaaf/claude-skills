# Subagent 0: Triage

- **subagent_type:** `general-purpose`
- **model:** `haiku`
- **maxTurns:** `7`

## Purpose

Reads the entire diff ONCE and produces a structured routing map of which subagent actually needs to check which lines. Saves massive amounts of tokens, because agents 1-10 no longer have to parse the complete diff from scratch each — they only get their relevant spots plus a short overall summary.

**Important:** Triage is CONSERVATIVE. When in doubt, trigger an agent rather than miss something. Triage does NOT decide on findings — only on relevance.

## Input

- `UNIFIED_DIFF` — complete diff
- `FRONTEND_DATEIEN` — list of frontend files in the diff
- `TRANSLATION_DATEIEN` — list of i18n files in the diff
- `FRAMEWORK` — detected framework
- `PROJECT_CONTEXT` — project-specific context from CLAUDE.md (may be empty)
- `SUPPRESSIONS` — list of deliberately accepted patterns (don't route hotspots covered by these)

## Task

Analyze the diff and return EXACTLY this JSON (no surrounding explanation, only JSON):

```json
{
  "summary": "Short 1-2 sentence summary of the diff",
  "files": [
    {"path": "src/foo.ts", "change_type": "modified", "lines_changed": 42}
  ],
  "relevance": {
    "architecture": {"run": true, "hotspots": ["src/foo.ts:10-25"], "reason": "new util function, check if an existing one can be reused"},
    "security": {"run": true, "hotspots": ["src/UserService.php:42"], "reason": "raw DB query"},
    "performance": {"run": false, "reason": "no loops, no DB calls, no large data"},
    "code_quality": {"run": true, "hotspots": ["src/foo.ts:10-60"], "reason": "new logic"},
    "seo": {"run": false, "reason": "no template/meta changes"},
    "a11y": {"run": true, "hotspots": ["components/Button.tsx:15"], "reason": "new interactive element"},
    "typography": {"run": true, "hotspots": ["lang/de.json"], "reason": "new strings"},
    "ui_design": {"run": true, "hotspots": ["components/Button.tsx"], "reason": "new variant"},
    "ux": {"run": false, "reason": "no interaction pattern affected"},
    "animation": {"run": false, "reason": "no transitions/animations in the diff"},
    "docs_sync": {"run": true, "hotspots": ["config/services.php:12", "src/routes.ts:88"], "reason": "new env('STRIPE_KEY') and new route -- check README/CLAUDE.md/.env.example"},
    "copy": {"run": true, "hotspots": ["components/Button.tsx:22"], "reason": "new user-facing button text"}
  }
}
```

## Rules for `run: true/false`

| Dimension | `run: true` when |
|-----------|------------------|
| architecture | New functions, new components, possible duplicates, new dependencies. **Migrations in the diff → always `run: true` with migration files as hotspots** (worker checks against data-migrations.md) |
| security | Input processing, DB queries, auth logic, file ops, env vars, new dependencies, regex with user input. **Widget/extension changes (WidgetKit, `*Widget*`, `TimelineProvider`, App Intents, share/notification extensions) → always `run: true`** (lock/privacy bypass risk: extensions bypass the in-app lock and read the shared store) |
| performance | Loops, DB queries, API calls, large arrays, re-renders, new dependencies |
| code_quality | Every code change except pure translation/config/doc updates |
| seo | Template changes with `<head>`, meta tags, routes, sitemap, robots.txt. **Native projects (no HTML/PHP/Blade/JSX in the tree, or `platform: native`) → always `run: false`** (no web UI, SEO not applicable) |
| a11y | Frontend changes with interactive elements, forms, modals, navigation. **Also when only a limit/range of an EXISTING control is changed (stepper cap, slider range, character limit) → `run: true` with the control as hotspot** — an earlier a11y pass checked against the old range (e.g. adjustable step size), the change invalidates that result |
| typography | Translation files, CSS/SCSS typography, text content in templates |
| ui_design | Frontend changes with visual components, new variants, colors, spacings |
| ux | New user flows, forms, error states, loading states, navigation changes |
| animation | Transitions, animations, motion libraries, CSS `@keyframes`, Framer Motion |
| docs_sync | New `env(...)` refs, new routes/commands/scripts, new top-level deps in `package.json`/`composer.json`/`pyproject.toml`, removed features, user-facing behavior changes |
| copy | New or changed user-facing text: templates with buttons/error messages/empty states, translation files, landing/marketing pages |

## Line-number requirement

Hotspot line numbers MUST come from the source file, not from the diff hunk. Diff offsets (the `+42`/`-17` lines in the unified diff) are NOT source-file line numbers and must NOT be passed through as hotspot coordinates.

Before output, verify every hotspot:
```bash
grep -n "{snippet_aus_dem_hotspot}" {datei}
```
The line-number value returned by `grep -n` is the source-file line. Only that value may appear in `hotspots`.

## Fallback when triage yields nothing

If the triage agent goes idle without returning the JSON (after the orchestrator's single idle re-prompt), the orchestrator does NOT keep retrying and does NOT block the run: the deterministic floor routing (`bin/check-skips.sh`, which derives run/skip from git file signals alone) IS the official fallback. The orchestrator dispatches `ROUTING_RUN` from the floor result and logs `TRIAGE=FALLBACK_FLOOR` in the routing line so the log shows the triage never contributed.

**Escalation policy (decided 2026-07-20 after 5 confirmed idle incidents with zero audit failures under floor routing):** on the NEXT idle incident (the 6th), promote deterministic floor routing to the DEFAULT for triage — i.e. skip the LLM triage dispatch entirely and always route via `bin/check-skips.sh` — instead of patching idle-detection/re-prompt mechanics further. The LLM triage's only added value is hotspot extraction; workers can locate hotspots themselves from the file list.

## Prohibited

- Creating findings — that is the job of the specialized agents
- Surrounding explanations — only the JSON
- Skipping overly aggressively — when in doubt, `run: true`
- `security` almost always `run: true` except for 100% pure doc/translation changes
- The `relevance` object MUST contain ALL 12 dimensions (architecture, security, performance, code_quality, seo, a11y, typography, ui_design, ux, animation, docs_sync, copy), including the skipped ones with `run: false`. If one is missing, it is treated as skipped and an entire worker silently drops out.
- NEVER enter diff-hunk offsets as source-file line numbers in hotspots
