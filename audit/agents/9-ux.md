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

**Defect classes calibrated against real findings (2026-08-27 audit):**
- **Background sync/integration with no error channel:** a sync or calendar/third-party
  integration path that has a success path back to the UI but no failure/error surface, so a
  failed sync looks identical to a successful one.
- **Content rendered before its gate resolves:** form fields or protected content rendered/visible
  before an async auth/password check has resolved, briefly exposing the gated state.

Skip when no frontend files are in scope.

## Severity

`Critical` only when a flow has no way to complete or recover a critical action (payment, account
deletion, irreversible data loss with no confirmation). A missing intermediate state (no loading
indicator, weak empty state) is `Important`; polish issues are `Minor`.

Examples (2026-09-05 audit): `Critical` — every downloads query on the member-area page failed with
"Verbindungsfehler" after a boolean-vs-null regression, blocking the flow with no recovery path
(browser verification). `Important` — upload items whose attachment had been deleted still reported
`available=true`, letting a user click a dead download with no explanation. `Minor` — empty
`<x-section>` shells still render for 17 unconfigured layouts instead of being hidden, a known
open polish gap.

## Output

Reply with the specialist schema: `findings[{id, severity, confidence, files, issue, impact}]`
plus `coverage`. Every ID is prefixed `ux-`. Set `coverage` to `COVERAGE: full` or
`COVERAGE: partial | not read: {file1}, {file2}`.
