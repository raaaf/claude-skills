# Context Budget

Shared by `/audit`, `/full-audit` and `/design-audit`. The orchestrator reads this once per run,
at the first dispatch step, and applies it for the whole run.

## Why this file exists

An orchestrator pays for its context on EVERY turn, not once. Cache-read cost is
`context_size x turns`, so a context that is never allowed to shrink makes a long run quadratic.
Measured on a real audit run (2026-08-27, one project, one session):

| | |
|---|---|
| assistant turns | 2860 |
| average context per turn | 503k token |
| peak context | 989k token |
| cache-read total | 1440M token |
| output total | 4M token |

360 read tokens per written token. The run was not expensive because it dispatched many agents;
it was expensive because everything those agents said, and everything the orchestrator wrote to
them, stayed in one context that got re-read 2860 times and was forbidden to compact.

Composition of that context at the end (4.0M characters total):

| Share | Source | Lever |
|---|---|---|
| 35% | agent final reports arriving as messages | R3 (already partly covered by the 50-word rule) |
| 26% | agent briefings the orchestrator writes | **R1** — they are ~90% identical within a wave |
| 19% | Bash tool results | **R2** |
| 5% | orchestrator prose + thinking | — |

And above all of it: **R4** — nothing was ever allowed to shrink.

417 agent dispatches, median briefing 2456 characters. The per-wave constants
(`SUPPRESSIONS`, `PROJECT_GUIDELINES`, `DECIDED_TRADEOFFS`, `DATEILISTE`/`BATCH_DATEILISTE`,
`GUIDELINE_MATCHES`, `WAVE_HEAD`, `BEREITS_GEFIXT`, `ARCHITEKTUR-NOTIZ`, `PROJECT_CONTEXT`) are
**identical for every worker in the same wave** and were written once per worker, so a 12-worker
wave paid for them twelve times in the orchestrator's own context and then re-read all twelve
copies on every subsequent turn.

## R1 — Wave constants go to disk, briefings carry the path (MANDATORY)

Before dispatching a wave, write the constants ONCE:

```bash
WAVE_SHARED="$AUDIT_TMP/wave-${WAVE_ID}-shared.md"   # WAVE_ID = round, or batch-round in /full-audit
cat > "$WAVE_SHARED" <<EOF
WAVE_HEAD: ${WAVE_HEAD}
FRAMEWORK: ${FRAMEWORK}
PROJECT_CONTEXT: ${PROJECT_CONTEXT}
SOURCE_DIRS: ${SOURCE_DIRS}
ARCHITEKTUR-NOTIZ: ${ARCHITEKTUR_NOTIZ}
SUPPRESSIONS:
${SUPPRESSIONS}
PROJECT_GUIDELINES:
${PROJECT_GUIDELINES}
DECIDED_TRADEOFFS:
${DECIDED_TRADEOFFS}
GUIDELINE_MATCHES:
${GUIDELINE_MATCHES}
BEREITS_GEFIXT:
${BEREITS_GEFIXT}
DATEILISTE:
${DATEILISTE}
EOF
echo "wave-shared: $WAVE_SHARED ($(wc -c < "$WAVE_SHARED") bytes)"
```

The briefing then names the file instead of inlining its content:

```
Agent(
  subagent_type: {type}, model: {model},
  prompt: "Read {AUDIT_AGENTS}/prompt-template.md, section '{SECTION}', and your definition
    {AUDIT_AGENTS}/{N}-{dim}.md. All shared placeholder values for this wave are in
    {WAVE_SHARED} — read it FIRST, it replaces every placeholder except the ones below.
    DIMENSIONEN: {DIMENSIONEN}
    HOTSPOTS: {HOTSPOTS}
    Report in the template's format."
)
```

Only genuinely per-agent fields (`DIMENSIONEN`, `HOTSPOTS`, and in `/full-audit` a per-dimension
file list when `UNCOVERED_BY_DIM` rescoped it) stay in the briefing. Everything else is one path.
The worker's own reads are free to the orchestrator: they happen in the subagent's context, which
is discarded when it finishes.

**The two reads count against the worker's tool-call budget.** `prompt-template.md` reserves
~5 calls for non-file reads; `wave-shared.md` fits in that reserve, it does not lower `BATCH_MAX`.

**Do not use this to smuggle more content to workers.** The point is to stop paying for the same
block twelve times, not to make the block bigger. If `wave-shared.md` exceeds 20k characters, that
is a signal the constants themselves need trimming (usually `SUPPRESSIONS` or `DECIDED_TRADEOFFS`
grown into prose), not a reason to raise the limit.

## R2 — Bash results are context, cap them (MANDATORY)

444 Bash calls in the measured run, median 1074 characters, 0.48M characters total. Every one of
them is re-read on every later turn. Rules for every Bash call the loop makes:

- A command whose output the orchestrator only needs to *check* prints a verdict, not data:
  `... | wc -l`, `... && echo OK || echo FAIL`, `grep -c` instead of `grep`.
- A command whose output it needs to *read* is capped: `| tail -40`, `| head -40`, `--quiet`,
  `--porcelain`, `-q`. Test runs: `--stop-on-failure` or the runner's compact reporter.
- Never `cat` a file the orchestrator will not act on line by line. `wc -c` plus the path is enough
  to hand it to an agent.
- `git diff` in the loop: `--stat` by default. The full hunks belong in a worker, not here.

## R3 — Reports stay inside their contract

The 50-word-per-finding and no-code-snippets rules in `prompt-template.md` are a context budget,
not a style preference. When a worker exceeds them the cost is not that one report — it is that
report re-read on every remaining turn of the run. A reply that ignores the format gets one
re-prompt with the format, exactly like an idle agent.

## R4 — The compaction block is wave-scoped, never run-scoped (MANDATORY)

This was the single most expensive line in the audit system, and it was one `touch`.

`~/.claude/hooks/pre-compact.sh` blocks auto-compaction whenever
`/tmp/claude-audit-in-progress-{cwd-hash}` exists. All three audit skills used to `touch` that
marker once at run start and remove it at run end, with a 3-hour stale window. For `/audit` that is
minutes. For `/full-audit` it meant the context was forbidden to shrink for the entire run: it grew
to 989k token, averaged 503k across 2860 turns, and every single turn paid for the peak.

The window that genuinely needs protection is narrow: between dispatching a wave and writing that
round's results to the audit log and state file, the findings exist ONLY in context, and a
compaction there could drop them. Once the round is persisted, compaction is safe by
construction — `references/state-file.md` says so explicitly ("survives session death, context
compaction, and interruptions").

So:

- **Claim** at the dispatch step: `touch "$COMPACT_MARKER"`
- **Release** immediately after the round is written to log + state: `rm -f "$COMPACT_MARKER"`
- Never hold it across a batch boundary, a user question, or a test run.
- The hook's own stale window is 20 minutes (`MAX_WAVE_AGE`). A marker older than that is a leak
  from a crashed run, and the hook releases it by itself.

A run that holds the block from start to finish is not "safer". It converts a linear cost into a
quadratic one and buys protection for a window the state file already covered.

**This does not license stopping early.** `/full-audit`'s "Running long" rule stands unchanged: do
not summarize early, do not hand off, do not propose a fresh session, do not shrink scope because
the session is long. R4 is the opposite of that — it lets a long run stay long *cheaply*, by
letting the harness compact between waves instead of forcing the orchestrator to carry the peak to
the end. Compaction is invisible to the loop; the state file and the audit log are the memory.

## Expected effect

Against the measured baseline (1440M cache-read token in one run):

| Rule | Attacks | Rough share |
|---|---|---|
| R4 | context was never allowed to shrink | the bulk — after a compaction, turns restart from a small context instead of paying the peak |
| R1 | 26% of context is duplicated briefing constants | most of that 26% |
| R2 | 19% is uncapped Bash output | about half of that 19% |
| R3 | 35% is worker reports | only the part already violating the format |

R4 and R1 are the two that matter. R2 and R3 are hygiene that keeps the win from eroding.

Re-measure after a run instead of trusting these numbers: aggregate
`cache_read_input_tokens` per session from `~/.claude/projects/**/*.jsonl` and compare against the
503k average above.
