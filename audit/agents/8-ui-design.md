# Dimension: UI Visual Design

## Look for

Visual design quality and consistency: spacing scale, component consistency (buttons, inputs,
cards, badges, alerts), color and hierarchy, shadows/borders, dark mode. Read
`guidelines/ui-visual-design.md` in full. Additionally `guidelines/color.md` when CSS/styles are
touched (OKLCH palette consistency, hue drift, P3 fallbacks, hex in Tailwind v4 `@theme`; existing
hex/rgb/hsl is not a finding by itself). Additionally `guidelines/atomic-design.md` (raw values
instead of design tokens, variant sprawl, component consistency — verify the token before every
token finding). Native apps: additionally `guidelines/native-mobile.md` section IV (HIG/Material
conventions, system components, safe areas/insets, semantic colors for dark mode).

- **Contrast findings:** only with a calculated ratio (state both resolved color values) AND a
  checked actual background — badges/chips/overlays often sit on their own background, not the
  page background.
- **Resolve tokens from the project theme, never Tailwind defaults:** check the project's CSS
  theme source for overrides (including dark-mode overrides) before any ratio calculation. State
  which resolved values (project token or default, with source line) the ratio uses.
- **Confidence cap for contrast/dark-mode claims:** at most `confidence: low`.
- **New dependencies:** check the library's own defaults first.
- **Variant/style-mismatch findings:** check at least 2 comparable call sites elsewhere and state
  the convention they establish before flagging a deviation.
- **Flex-row layout fixes:** verify the long-content case (4-word name, long translation) wraps or
  truncates without pushing siblings out (`min-w-0`, `truncate`, `shrink-0`).

**Defect classes calibrated against real findings (2026-08-27 audit):**
- **Raw spacing/size literal where a token exists:** a hardcoded pixel/pt margin, padding, or
  radius (e.g. a raw `24pt`) in a project that has a design-token spacing scale — cite the missing
  token by name.
- **Component variant convention broken silently:** a default label/icon/state applied
  unconditionally instead of only for the variant it was designed for (e.g. a fallback label now
  also appears on an icon-only variant that should stay unlabeled visually).

Skip when no frontend files are in scope.

## Severity

Pure style/visual-consistency findings are at most `Important`, never `Critical`, even against a
`non_negotiable` guideline (severity cap rule). `Important` requires content becoming unreadable or
unusable (contrast below threshold on real content, layout that clips content); everything else
`Minor`.

## Output

Reply with the specialist schema: `findings[{id, severity, confidence, files, issue, impact}]`
plus `coverage`. Every ID is prefixed `ui_design-`. Set `coverage` to `COVERAGE: full` or
`COVERAGE: partial | not read: {file1}, {file2}`.
