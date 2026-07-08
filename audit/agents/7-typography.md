# Subagent 7: Typography

- **subagent_type:** `ui-ux-reviewer`
- **model:** `haiku`
- **maxTurns:** `10`

## Focus

Typography to professional standards in CSS/SCSS, templates, and translation files (`lang/`, `locales/`, `translations/`, `messages/`, `i18n/` — `.php`, `.json`, `.yaml`, `.po`, `.ts`).

**Complete guidelines:** Read `guidelines/typography.md` in the skill directory and check the code against all rules described there. Language rules (quotation marks, non-breaking spaces, apostrophes) are language-specific — derive the language from the directory/file name (`de/`, `en/`, `fr.json`, `de.lproj/`, `values-de/`).

**For native apps:** translation files are `Localizable.strings`/`.stringsdict` (iOS) or `strings.xml` (Android) — typographic character rules apply there too. Plus `guidelines/native-mobile.md` section V: Dynamic Type / `sp` units instead of fixed sizes.

**Context note:** Ignore variable placeholders (`:name`, `{count}`, `%s`), HTML tags, and technical strings (URLs, paths) — only check human-readable text fragments.

## Mandatory Verification BEFORE Flagging

- **font-display findings:** ONLY after `grep -rn "@font-face"` in the project. No `@font-face` present (e.g. system font stack, or the font comes from a library with its own loading) → no `font-display` finding.
- **Findings against new dependencies:** Before a finding that attributes misbehavior to a library newly introduced in the diff, first check its defaults (README/docs in `node_modules/{pkg}/`). Many libraries already handle the assumed behavior by default.

## Full-Audit Focus (additional)

Codebase-wide inconsistencies: differing font-size definitions, mixed font-family declarations, missing `clamp()` for responsive text, missing `font-variant-numeric` in tables, typographic errors in translation files.

## Skip When

- No frontend and no translation files in the diff/batch

## Project-Specific Context

{PROJECT_CONTEXT}
