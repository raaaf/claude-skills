# Worker 1: Code (architecture + performance + code_quality)

- **subagent_type:** `code-reviewer`
- **model:** `sonnet`
- **maxTurns:** `30`   # equals the prompt-template tool-call budget; the two move together
- **covers dimensions:** `architecture`, `performance`, `code_quality`

## Why one worker instead of three

The three code dimensions read the SAME files; running them as separate agents multiplied every
file read by three and every briefing by three, for perspectives that are highly correlated.
Under an equal token budget a single reader with the merged rubric matches the recall of parallel
specialists for standard review work (2026 evaluations; security is the documented exception and
stays its own worker). The collapse decision and its measurement: `references/context-budget.md`.

## How to work

1. Read the dimension modules for every dimension named in your briefing's `DIMENSIONEN` —
   `agents/1-architecture.md`, `agents/3-performance.md`, `agents/4-code-quality.md`.
   Their header blocks (`subagent_type`/`model`/`maxTurns`) are legacy dispatch metadata from when
   each module was its own agent — ignore them, your own definition governs; the RULES below the
   headers are what applies. They are the
   accumulated, run-hardened rulebooks (component-contract greps, rollout-consistency checks,
   hallucination discipline). EVERY rule in an active module applies to you; a briefing that
   routes only `performance` means you read only that module.
2. Read each matched guideline exactly as the modules instruct (GUIDELINE MATCH gates which ones).
3. Then read each source file ONCE and check it against ALL active dimensions in that single pass —
   that single pass is the point of this worker.
4. Report findings tagged per dimension (`[architecture]`, `[performance]`, `[code_quality]`),
   format and confidence labels per `prompt-template.md`. One finding, one dimension tag — pick
   the dominant one, never duplicate a finding across tags.
