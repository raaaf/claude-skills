# Dimension: Docs Sync & Style

## Look for

Keep project documentation current and consistent in style. Check `README.md`, `CLAUDE.md`,
`.env.example`, `CHANGELOG.md` and `docs/**` against the actual state of the code. Findings under
category `[Docs]`. Read `guidelines/documentation.md` in full (structure standards, `.env.example`
sync rules, style rules). `guidelines/docs-sync.md` additionally for wizard/config/schema diffs
(check its checklist: wizard steps, config keys, migrations, routes → which docs must be checked).

Uses `scout-clusters.md`, not `scout-files.md`: docs-sync findings live in the gap between two
files, so a module/pattern map with cross-reference points finds more than a per-file chunk did.

**Sync against code (mandatory):**
- Every `env('FOO')`/`process.env.FOO`/`os.getenv('FOO')` → entry in `.env.example`?
- New routes, CLI/Artisan commands, scripts → mentioned in README?
- New top-level dependencies → stack section in CLAUDE.md current?
- Do install/run commands still work? Do referenced paths/files still exist?
- **Design token/palette/brand value changed?** Grep the OLD literal under `tests/`,
  `__snapshots__/`, `Snapshots/` and fixture directories too — a snapshot harness re-records a
  stale value as the new baseline on first re-run.
- **Anything named, numbered or listed changed?** Walk every repeat site explicitly: CLAUDE.md
  tables (Commands, migrated-so-far lists, skill roster, effort table, counts), README counts and
  feature lists, SKILL.md step/phase numbering, `.claude-plugin/plugin.json` and
  `marketplace.json`. Each stale repeat site is its own `[Docs]` finding — grep the changed
  identifier repo-wide, the drift is by definition in files the diff did NOT touch.

**Defect class calibrated against a real finding (2026-08-27 audit):** an auth/secret-bearing
environment variable (`BACKEND_JWT_SECRET`-style) used in code but absent from `.env.example` —
its absence in production causes a silent feature lockout, not just a setup inconvenience; flag
this class of missing `.env.example` entry even when other, non-secret vars are already documented.

**Test-count drift (unconditional, every run):** determine the real test count (test-runner
summary or `grep -rcE '\b(it|test)\(' tests/`) and diff it against every "number + test/assertion"
phrase in README/CLAUDE.md. Mismatch → `[Docs]` finding with both numbers.

**Structure/style (see guideline):** clear sections, no duplication between README and CLAUDE.md,
no filler ("just", "simply", "basically"), no preambles, tables over prose, short paragraphs.

Skip in `/audit` mode when the diff has no doc-relevant change (no new env/route/command/script, no
new top-level dependency, no user-facing behavior change) and is not a pure i18n/test change —
except the test-count drift check, which always runs.

## Severity

`Important` when the drift breaks setup/onboarding (missing `.env.example` entry, dead install
command, broken referenced path) or misstates a number readers rely on. Style/structure issues and
cosmetic drift are `Minor`. No `Critical` — docs drift alone carries no exploit or data-loss path.

## Output

Reply with the specialist schema: `findings[{id, severity, confidence, files, issue, impact}]`
plus `coverage`. Every ID is prefixed `docs_sync-`. Set `coverage` to `COVERAGE: full` or
`COVERAGE: partial | not read: {file1}, {file2}`.
