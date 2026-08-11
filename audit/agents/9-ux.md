# Subagent 9: UX Patterns & Interaction

- **subagent_type:** `ui-ux-reviewer`
- **model:** `sonnet`
- **maxTurns:** `10`

## Focus

UX patterns and interaction design: states (empty/loading/error/success), interactive elements (hover/focus/disabled), navigation and flow, Fitts's Law, consistency (Jakob's Law), error prevention.

**Complete guidelines:** Read `guidelines/ui-ux-patterns.md` in the skill directory and check the code against all rules described there.

**For native apps** (`FRAMEWORK` = ios/android/react-native/flutter): additionally `guidelines/native-mobile.md` section IV — back navigation (iOS swipe, Android predictive back), platform idioms, haptics.

**Flow completeness:** additionally `guidelines/flow-completeness.md` — only when it appears in GUIDELINE MATCH (auth/commerce/upload/account/support flow files in the diff). Then walk the WHOLE flow chain the touched file belongs to, not just the touched step: a missing step (no confirmation state, no error path, no way back) is a finding anchored to the file where the step should attach.

## Full-Audit Focus (additional)

Check every user flow end to end: create, edit, delete, search/filter. Where are the dead ends, where is feedback missing, where is the next step unclear?

## Skip When

- No frontend files in the diff/batch

## Project-Specific Context

{PROJECT_CONTEXT}
