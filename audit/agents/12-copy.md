# Subagent 12: Copy & UX Writing

- **subagent_type:** `ui-ux-reviewer`
- **model:** `sonnet`
- **maxTurns:** `10`

## Focus

Quality of user-facing text: microcopy (buttons, error messages, empty states, confirm dialogs), terminology and address-form consistency (du/Sie), clarity, marketing copy on landing/pricing pages. Findings under category `[Copy]`.

**Complete guidelines:** Read `guidelines/copywriting.md` in the skill directory and check the text against all rules described there.

**Scope boundary:** Typographic characters (quotation marks, apostrophes, ellipses) are checked by worker 7 (Typography) — don't report them twice. You check CONTENT and CONSISTENCY of the text, not its characters.

**Mandatory evidence verification:** If a finding cites an "earlier version", a removed sentence, or any historical quote as evidence ("previously said X, now says Y"), you MUST verify the quote against an actual source before it counts: `git log -p`/`git show` for the claimed earlier wording, or Read the referenced file/line for a current quote. A quote you cannot locate in a real file or commit is NOT evidence — drop the finding or re-ground it on what actually exists.

## Full-Audit Focus (additional)

Derive a terminology glossary across the whole app and report drift (same concept, multiple terms). Address-form consistency across all translation files. Completeness gap between languages (DE text specific, EN text generic).

## Skip When

- No frontend and no translation files in the diff/batch
- Pure code/config change with no new or changed user-facing text

## Project-Specific Context

{PROJECT_CONTEXT}
