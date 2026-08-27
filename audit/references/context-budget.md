# Context Budget — measurement and open work

**Status: ANALYSIS ONLY. Nothing here is wired into the skills.** A first implementation was written
on 2026-08-27, audited, found defective, and reverted the same day. The measurement below stands and
is the reason to try again; the "Attempted and reverted" section is why the obvious implementation
does not work. Read that section before writing the second attempt.

## The measurement

An orchestrator pays for its context on EVERY turn, not once. Cache-read cost is
`context_size x turns`, so a context that is never allowed to shrink makes a long run quadratic.
Measured on a real `/full-audit` run (2026-08-27, one project, one session):

| | |
|---|---|
| assistant turns | 2860 |
| average context per turn | 503k token |
| peak context | 989k token |
| cache-read total | 1440M token |
| output total | 4M token |

360 read tokens per written token. The run was not expensive because it dispatched many agents; it
was expensive because nothing it accumulated was ever allowed to shrink.

Composition of that context at the end (4.0M characters total):

| Share | Source |
|---|---|
| 35% | agent final reports arriving as messages |
| 26% | agent briefings the orchestrator writes |
| 19% | Bash tool results |
| 5% | orchestrator prose + thinking |

417 agent dispatches, median briefing 2456 characters, 444 Bash calls at median 1074 characters.

**The root cause is `hooks/pre-compact.sh`.** It blocks auto-compaction whenever
`/tmp/claude-audit-in-progress-{cwd-hash}` exists, and all three audit skills `touch` that marker
once at run start, remove it at run end, with a 3-hour stale window. For `/audit` that is minutes.
For `/full-audit` it means the context is forbidden to shrink for the entire run.

Reproduce the number before and after any fix: aggregate `cache_read_input_tokens` per session from
`~/.claude/projects/**/*.jsonl` and compare against the 503k average.

## Attempted and reverted (2026-08-27)

The attempt scoped the marker to a wave: claim at dispatch, release once the round is persisted,
stale window 20 minutes. Its own audit found three Critical and seven Important. The four that any
second attempt has to answer:

1. **Shell state does not survive between Bash tool calls.** The attempt set `COMPACT_MARKER=...` in
   the Phase 1 block and wrote `touch "$COMPACT_MARKER"` in the dispatch block. Different
   invocation, empty variable, `touch ""` — the marker was never created, so the change did not
   scope the block, it silently removed it. Every claim and release site must recompute the hash
   inline, the way the existing run-end cleanups already do. This is also why the existing code
   repeats that `pwd | md5` expression instead of factoring it out; that repetition is load-bearing.
2. **`/audit` has no per-round persistence.** Its audit log is written after the loop ends
   (`audit/SKILL.md`, "Write audit log (after loop ends)"), so rounds 1..N-1 exist only as chat
   output. Releasing the block after each round can lose them. `/full-audit` has a state file, but
   it explicitly keeps `BEREITS_GEFIXT` and `FINDINGS_VORHERIGE_RUNDE` round-local, and
   `FINDINGS_NAECHSTE_RUNDE` (the `FIX_RESULT=PARTIAL` remainders) is persisted nowhere at all. A
   release point is only safe once these are on disk.
3. **A wave is longer than 20 minutes.** Twelve workers plus D.5/D.7/E/E.5 routinely exceed that, so
   a short stale window makes the hook self-release in the middle of exactly the window it is meant
   to protect. Either the marker is refreshed while the wave runs, or the window is sized to a real
   wave rather than an optimistic one.
4. **A briefing that names a shared file needs a worker contract.** Moving the wave constants to
   disk only helps if `agents/prompt-template.md` tells workers to read that file; the attempt
   changed the dispatch text and not the template, leaving the placeholders unfilled. And the read
   costs a tool call: `full-audit/references/scope-context-batching.md` derives `BATCH_MAX = 20 - 5`
   from an exactly-allocated reserve, so a sixth mandatory read means `BATCH_MAX` drops to 14. Those
   two constants are coupled by that file's own rule.

Two documentation defects from the same attempt, worth not repeating: the hook is registered in
`~/.claude/settings.json` by a single hard-coded path, not by the fail-open probe the audit skill
uses for its PreToolUse hook, and `sync-skills.sh` only writes into `~/.claude/skills/`, never into
`~/.claude/hooks/`. A copy of the hook shipped inside the skill is therefore NOT the one that runs.

## Candidate rules for the second attempt

Unimplemented. Listed so the analysis is not lost, not as instructions to follow today.

- **Wave-scoped compaction block.** The window that needs protection is between dispatching a wave
  and persisting that round, not the whole run. Prerequisites: defects 1, 2 and 3 above.
- **Wave constants written once to disk** instead of once per worker. The per-wave constants
  (`SUPPRESSIONS`, `PROJECT_GUIDELINES`, `DECIDED_TRADEOFFS`, the file list, `GUIDELINE_MATCHES`,
  `WAVE_HEAD`, `BEREITS_GEFIXT`) are identical for all twelve workers and are currently paid for
  twelve times in the one context that gets re-read every turn. Prerequisite: defect 4.
- **Capped Bash output.** A command whose result is only checked prints a verdict, not data
  (`wc -l`, `grep -c`, `&& echo OK`); one whose result is read is capped (`| tail -40`,
  `--porcelain`, `git diff --stat`). 0.48M characters of Bash output sat in the measured context.
- **The report format is a budget.** The 50-word and no-code-snippet rules in `prompt-template.md`
  already exist; the cost of a violation is that report re-read on every remaining turn.

Of these, the compaction block is the one that matters. The other three attack the size of the
context; only that one attacks the number of times it is paid for.
