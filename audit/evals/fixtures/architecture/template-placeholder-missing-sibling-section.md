# Worker Briefing Template

Eval fixture: a NEW placeholder was added to a shared template for one of
its two sibling sections only. The `{DECIDED_TRADEOFFS}` block was added to
the diff-based section but NOT to the batch-based sibling section, although
both sections are rendered by callers that provide the same parameter. The
audit must flag the missing placeholder in the sibling section (incomplete
rollout of a shared-template change), dimension architecture. Real incident
2026-07-07: DECIDED_TRADEOFFS reached only the /audit callers; /full-audit
workers silently lost tradeoff suppression.

## For the diff-based run

Audit the following changes for {DIMENSIONS}.

Triage summary: {TRIAGE_SUMMARY}

Your hotspots (focus exclusively here):
{HOTSPOTS}

Project context:
{PROJECT_CONTEXT}

Documented tradeoffs (deliberate decisions are not findings):
{DECIDED_TRADEOFFS}

Reply with findings only, max 50 words each, `file:line` references.

## For the batch-based run

Audit the following file batch for {DIMENSIONS}.

Batch file list:
{BATCH_FILE_LIST}

Project context:
{PROJECT_CONTEXT}

Reply with findings only, max 50 words each, `file:line` references.
