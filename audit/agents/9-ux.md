# Dimension: UX Patterns & Interaction

## Look for

UX patterns and interaction design: states (empty/loading/error/success), interactive elements
(hover/focus/disabled), navigation and flow, Fitts's Law, consistency (Jakob's Law), error
prevention. Read `guidelines/ui-ux-patterns.md` in full. Native apps: additionally
`guidelines/native-mobile.md` section IV (back navigation, platform idioms, haptics).

- **Flow completeness:** when a `GUIDELINE_MATCHES` entry names `guidelines/flow-completeness.md`
  (auth/commerce/upload/account/support flow files in scope), read it and walk the WHOLE flow
  chain the touched file belongs to — a missing step (no confirmation state, no error path, no way
  back) is a finding anchored to the file where the step should attach.

Skip when no frontend files are in scope.

## Severity

`Critical` only when a flow has no way to complete or recover a critical action (payment, account
deletion, irreversible data loss with no confirmation). A missing intermediate state (no loading
indicator, weak empty state) is `Important`; polish issues are `Minor`.

## Output

Reply with the specialist schema: `findings[{id, severity, confidence, files, issue, impact}]`
plus `coverage`. Every ID is prefixed `ux-`. Set `coverage` to `COVERAGE: full` or
`COVERAGE: partial | not read: {file1}, {file2}`.
