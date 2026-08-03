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
| Legal / tax question ("can the app do X for country Y") | Codebase scan is not enough. Websearch the rule **before** the plan is written, especially the triggering event (payment received vs. invoice issued). Never answer from intuition. |
| Time/trigger-based concept (daily digest, recap, reminder) | Check WHEN the relevant data generation actually happens in code (BGTask/cron/gate timing) before interview round 1 — the trigger moment usually decides the design. |
| Field extension / new model attribute | Grep **every** form variant that writes the model, not just the one named in the request (e.g. invoice + quote + recurring). One missed variant is a silent data gap. |

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

## Mandatory Questions (Red Flags)

Two questions get skipped or deferred over and over, and both cost a whole extra round later. Ask them in round 1 or 2, never later.

**Onboarding.** Whenever a plan touches a user-facing flow, permission, or setting: does this need an onboarding step, or does it work via toggle plus settings? Ask it directly, do not write "onboarding TBD" into the plan. Red flag: if onboarding first comes up in round 3+, the interview went wrong.

**Scope split.** Before proposing any MVP cut or phase split, answer for yourself: is this a real saving in complexity or differentiation, or does it tear apart something the user sees as one coherent feature? Only propose the split in the first case. When in doubt, ask in exactly those terms:

```
Split this into phase 1 / phase 2, or in one go?
→ My assessment: {one go | split}, because {real complexity saving | it's one coherent surface}
```

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
