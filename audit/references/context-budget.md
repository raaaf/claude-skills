# Context Budget

Shared by `/audit`, `/full-audit` and `/design-audit`. **Status: implemented (v2, 2026-08-27).**
The claim/release sites live in the three SKILL.md files and `fix-loop.md`; the worker-side read
contract lives in `agents/prompt-template.md`; the hook is `~/.claude/hooks/pre-compact.sh`
(registered in `~/.claude/settings.json`, deliberately outside version control like every global
hook — see the repo CLAUDE.md's hook-safety bullet). v1 of this design shipped and was reverted
the same day; its four defects are documented at the bottom because each one is now a rule.

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
was expensive because `pre-compact.sh` held the compaction block for the whole run (3-hour stale
window), so nothing the run accumulated was ever allowed to shrink.

Composition of that context at the end (4.0M characters): 35% agent reports, 26% briefings the
orchestrator wrote (417 dispatches, median 2456 chars — ~90% identical within a wave), 19% Bash
results (444 calls, median 1074 chars), 5% prose/thinking.

Re-measure after any change here: aggregate `cache_read_input_tokens` per session from
`~/.claude/projects/**/*.jsonl` and compare against the 503k average.

## The rules

### R1 — Wave constants go to disk once, briefings carry the path

The per-wave constants (`SUPPRESSIONS`, `PROJECT_GUIDELINES`, `PROJECT_CONTEXT`,
`DECIDED_TRADEOFFS`, `GUIDELINE_MATCHES`, `WAVE_HEAD`, `BEREITS_GEFIXT`, the file list) are
identical for every worker in a wave. Inlining them per briefing pays for the same block twelve
times in the one context that is re-read every remaining turn. So: the orchestrator writes them
ONCE to `{AUDIT_TMP}/wave-*-shared.md` — **with the Write tool, never a bash heredoc, because the
shell variables holding those values are dead outside their own block** — and the briefing passes
the path plus only per-agent fields (dimension, hotspots, rescoped file lists).

Worker side: `agents/prompt-template.md` ("Wave-shared file") makes reading it the worker's first
Read. That read costs a tool call, which is why `BATCH_MAX = 20 - 6 = 14`
(`full-audit/references/scope-context-batching.md` — the two constants are coupled).

### R2 — Bash results are context, cap them

A command whose output is only *checked* prints a verdict, not data (`wc -l`, `grep -c`,
`&& echo OK`). One whose output is *read* is capped (`| tail -40`, `--porcelain`, `--stat`,
compact test reporters). Never `cat` a file the orchestrator will not act on line by line —
`wc -c` plus the path suffices to hand it to an agent.

### R3 — Reports stay inside their contract

The 50-word and no-code-snippet rules in `prompt-template.md` are a context budget, not a style
preference: a violating report is re-read on every remaining turn. One re-prompt with the format,
same as an idle agent.

### R4 — The compaction block is wave-scoped

The window that needs protection is between dispatching agents and persisting the round — there,
findings live only in context. Once the round is on disk, compaction is recoverable by
construction. Mechanics:

- **Claim** before EVERY agent dispatch (worker wave, D.7, E, E.5, cross-ref):
  `touch "/tmp/claude-audit-in-progress-$(pwd | md5 2>/dev/null || pwd | md5sum 2>/dev/null | cut -d' ' -f1)"`
- **Persist, then release** at round end: first write the round's loop state
  (`round-state.md` in `{AUDIT_TMP}`: findings, `BEREITS_GEFIXT`, `FINDINGS_NAECHSTE_RUNDE`,
  `UNCOVERED_BY_DIM`, round number), then `rm -f` the marker (inline hash again).
- **Recover** at the next round start: after a compaction, `round-state.md` is authoritative over
  any summarized memory of the loop state.
- The hook's stale window is **45 minutes** — sized for the gap between two re-touches, not for a
  round. Shortening it without increasing re-touch frequency self-releases mid-wave.
- **Fail-safe:** when `AUDIT_TMP` is not writable (Phase 0/1 prints the WARN and checks `-w`, not
  just mkdir success), the skill claims the marker ONCE right there and releases it only at the
  run-end cleanup — the old run-scoped behavior: expensive but safe, never half-wired, and never
  a WARN path with no protection at all.
- **Post-loop dispatches re-claim for themselves:** `/audit` Phase 2.5 (cross-reference) runs
  after the last round's release, so it claims before its dispatches and releases right after the
  audit log is written; `/design-audit` re-touches before its Phase 2.5 verdict agents and Phase 3
  verifier wave.

Releasing between waves is NOT "stopping because of context" (full-audit's "Running long" rule
stands): it lets the harness compact between waves instead of carrying the peak context through
thousands of turns. R4 attacks the number of times context is paid for; R1-R3 attack its size.

## Why v1 failed (each defect is now a rule above)

1. **Shell state does not survive between Bash tool calls.** v1 set `COMPACT_MARKER` in Phase 1
   and ran `touch "$COMPACT_MARKER"` at dispatch — different invocation, empty variable,
   `touch ""`: the marker was never created and the block was silently OFF, not wave-scoped.
   Hence: every claim/release recomputes the hash inline, and the wave-shared/round-state files
   are written with the Write tool, never via heredoc variables. A manual test that computes and
   touches in one block cannot catch this class — check variable *lifetime*, not syntax.
2. **`/audit` had no per-round persistence** (log written only after the loop), and
   `FINDINGS_NAECHSTE_RUNDE` was persisted nowhere in either skill. Hence: `round-state.md` is
   written BEFORE every release, and release without it is forbidden.
3. **A 20-minute stale window was shorter than a real wave** (12 workers plus verification plus
   idle re-prompts), so the hook self-released mid-wave. Hence: 45 minutes plus re-touch at every
   dispatch inside the round (`fix-loop.md`).
4. **The briefing named a shared file no worker was told to read** — `prompt-template.md` was
   unchanged, placeholders stayed unfilled, and the extra read broke the exactly-allocated
   `BATCH_MAX` reserve. Hence: the contract paragraph in `prompt-template.md` and
   `BATCH_MAX = 20 - 6 = 14`.

Also from v1's audit: a hook copy shipped inside the skill is NOT the one that runs —
`settings.json` registers the literal `~/.claude/hooks/pre-compact.sh` and `sync-skills.sh` never
writes into `~/.claude/hooks/`. The hook therefore stays a global hook; this file documents it,
the repo does not carry a dead copy of it.
