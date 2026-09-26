# /design-audit internals

Rules and commands bound to `/design-audit`'s own tooling. Cross-cutting rules (fresh-shell,
marker hashing, hook scope) live in the root `CLAUDE.md`.

## Effort levels

| Level | /design-audit (default `high`) |
|---|---|
| low | elevation cap 3, fixes not verified |
| medium | elevation cap 5, fixes verified |
| high / xhigh (default) | elevation cap 7, fixes verified |

`/design-audit` carries `effort: high` in its frontmatter, and per the dual-use rule that value is
what `${CLAUDE_EFFORT}` receives; the `:-high` fallback in Phase 0 only matters if the frontmatter
line is removed. It additionally scales `MAX_ELEVATION` and `VERIFY_FIXES` (`design-audit/SKILL.md`
Phase 0), a different knob unrelated to fixing (the fix wave needs no user selection since
2026-09-25; only suspected prompt-injection notes are held for manual review).

## Commands

| Command | Purpose |
|---|---|
| `bash audit/bin/validate-locations.sh <pairs.tsv> [root]` | Hallucination validator for orchestrators that hold findings in prose (`/design-audit` Phase 3): reads `path<TAB>line` rows from a FILE the orchestrator wrote with the Write tool, so finding text never enters a command line (an inline `F='{datei}'` template was a Critical on 2026-09-16). Rejects non-integer lines, absolute or `..` paths, missing files, out-of-range lines; `LOCATIONS_RESULT=OK\|HITS (N)\|SKIP` |

## Gotchas

- **In-progress marker is run-scoped, not wave-scoped.** `/design-audit` (`9d8e274`, 2026-09-16): claim once in Phase 0, touch after each wave including the fix wave, release once in Phase 7; its per-dispatch model contradicted itself between Phase 0 and Phase 4 before. Same convention as `/full-audit`, see `full-audit/CLAUDE.md`.
- **Stop-hook `additionalContext` does NOT block.** Per the hooks docs, `hookSpecificOutput.additionalContext` on Stop/SubagentStop lets the stop proceed and only injects context. This is why `/design-audit`'s multi-dispatch waves still need `exit 2`-style blocking where they rely on it — `additionalContext` alone would not force a stop. Don't "modernize" a genuine block into `additionalContext`.
