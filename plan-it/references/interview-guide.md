# Phase 1 Interview Guide (Detail)

Detail for Phase 1 (understanding). Read by the orchestrator when the assessment is difficult.

## Step B: Codebase Scan Table

What to scan, depending on the topic:

| Topic | Scan action |
|---|---|
| Data overhaul / schema migration | Grep all write and read sites of the field, check cache layer, trait mixins |
| Multi-channel / multi-service | `ls` the channel/service classes, reliability status (deprecated? in tests?), monitoring sites |
| New feature | Grep for similar features (naming search), existing patterns for lifecycle/permission/UI |
| Refactoring / renaming | Caller list via grep, check test coverage, doc mentions |
| Performance / caching | Find existing cache keys, invalidation pattern, N+1 hotspots |

**Output format:** Short codebase map (3-8 bullet points) as a factual basis before the questions:

```
Before the questions — codebase state:
- {Fact 1, e.g. "Push channels: APNs, FCM, NativePushChannel — the latter is the only active implementation"}
- {Fact 2}
- {Fact 3}
```

## Question Format with Own Assessment

Don't just ask — directly propose the best answer based on codebase, context, typical patterns. The user only corrects or confirms.

```
{Question}
→ My assessment: {concrete assumption/recommendation, justified in 1 sentence}
```

Examples:
- "Who is the user here? → My assessment: Admin — because the route sits behind auth and no onboarding flow exists."
- "How should errors be handled? → My assessment: Toast notification, since that's the existing pattern in the app."
- "Do we need a migration? → My assessment: No — the new field is optional and has a default."

## Detecting Dependencies

Before asking a question, check:
- Does the answer depend on a still-open decision? → Clarify the dependency first.
- Does the answer open a new branch? → Keep asking there right after the answer.
- Are several questions independent of each other? → Then ask them in the same round.

Example tree:
```
Who is the user? (blocks everything)
├── Admin → Which permissions? → Does it need audit logging?
├── End user → Onboarding needed? → Which flow?
└── Both → Role-based views? → Shared components or separate?
```

## Tone

The skill talks like a smart colleague:

Good: "I notice the plan has no error handling for X. What happens if Y goes wrong?"
Bad: "Re-grounding context: The user's plan lacks error handling. Completeness: 3/10."

Good: "This sounds like a simple feature flag rather than the whole overhaul. What's the case against that?"
Bad: "Alternative approach detected. Please evaluate tradeoffs."

Good: "Who's actually the user here? Admin or end user? That changes the whole approach."
Bad: "Target user persona not specified. Please select: A) Admin B) End user C) Both."
