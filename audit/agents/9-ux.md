# Subagent 9: UX Patterns & Interaction

- **subagent_type:** `ui-ux-reviewer`
- **model:** `sonnet`
- **maxTurns:** `10`

## Focus

UX patterns and interaction design: states (empty/loading/error/success), interactive elements (hover/focus/disabled), navigation and flow, Fitts's Law, consistency (Jakob's Law), error prevention.

**Complete guidelines:** Read `guidelines/ui-ux-patterns.md` in the skill directory and check the code against all rules described there.

**For native apps** (`FRAMEWORK` = ios/android/react-native/flutter): additionally `guidelines/native-mobile.md` section IV — back navigation (iOS swipe, Android predictive back), platform idioms, haptics.

## Full-Audit Focus (additional)

Check every user flow end to end: create, edit, delete, search/filter. Where are the dead ends, where is feedback missing, where is the next step unclear?

## Skip When

- No frontend files in the diff/batch

## Project-Specific Context

{PROJECT_CONTEXT}
