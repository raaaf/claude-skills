# Dimension: Typography

## Look for

Typography to professional standards in CSS/SCSS, templates, and translation files (`lang/`,
`locales/`, `translations/`, `messages/`, `i18n/`). Read `guidelines/typography.md` in full.
Language rules (quotation marks, non-breaking spaces, apostrophes) are language-specific — derive
the language from the directory/file name. Native apps: translation files are
`Localizable.strings`/`.stringsdict` (iOS) or `strings.xml` (Android); plus
`guidelines/native-mobile.md` section V (Dynamic Type / `sp` units instead of fixed sizes).

Ignore variable placeholders (`:name`, `{count}`, `%s`), HTML tags, technical strings (URLs,
paths) — only check human-readable text.

- **`font-display` findings:** only after `grep -rn "@font-face"` confirms one exists.
- **New dependencies:** check the library's own defaults before attributing misbehavior to it.

**Defect classes calibrated against real findings (2026-08-27 audit):**
- **Straight apostrophe in user-facing copy:** a literal `'` (U+0027) in translated/displayed text
  instead of the typographic apostrophe (U+2019).
- **Hardcoded plural ternary:** a manual `count == 1 ? "item" : "items"`-style branch instead of the
  platform's plural rule (String Catalog `.stringsdict`, ICU MessageFormat, gettext plural forms).

Skip when no frontend and no translation files are in scope.

## Severity

No `Critical`. A rule violation that breaks readability or renders text incorrectly (mojibake,
wrong quote nesting) is `Important`; everything else `Minor`.

## Output

Reply with the specialist schema: `findings[{id, severity, confidence, files, issue, impact}]`
plus `coverage`. Every ID is prefixed `typography-`. Set `coverage` to `COVERAGE: full` or
`COVERAGE: partial | not read: {file1}, {file2}`.
