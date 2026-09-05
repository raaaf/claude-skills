# Dimension: Copy & UX Writing

## Look for

Quality of user-facing text: microcopy (buttons, error messages, empty states, confirm dialogs),
terminology and address-form consistency (du/Sie), clarity, marketing copy on landing/pricing
pages. Findings under category `[Copy]`. Read `guidelines/copywriting.md` in full.

Scope boundary: typographic characters (quotation marks, apostrophes, ellipses) belong to
`typography`, don't report them twice here — this dimension checks content and consistency, not
characters.

**Mandatory evidence verification:** a finding citing an "earlier version", a removed sentence, or
any historical quote as evidence must verify the quote against an actual source (`git log -p`/`git
show` for the claimed earlier wording, or Read for a current quote). A quote you cannot locate is
not evidence — drop or re-ground the finding.

Skip when no frontend and no translation files are in scope, or the change is pure code/config
with no new/changed user-facing text.

## Severity

No `Critical`. Misleading or legally sensitive copy (wrong pricing, wrong consent wording, wrong
irreversible-action confirmation) is `Important`; everything else `Minor`.

## Output

Reply with the specialist schema: `findings[{id, severity, confidence, files, issue, impact}]`
plus `coverage`. Every ID is prefixed `copy-`. Set `coverage` to `COVERAGE: full` or
`COVERAGE: partial | not read: {file1}, {file2}`.
