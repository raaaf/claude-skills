# Learning Phase (Phase 5)

Runs after the audit log is written and before the push marker. Skipped entirely when `SKIP_LEARNING=1` (low effort).

The learning agent returns a **structured output**. **Subagents cannot write to `.claude/` paths** (hardcoded protection, even in the foreground and with bypassPermissions). The orchestrator parses the output and writes it itself — `.claude/audits/*.md` and `.claude/audits/suppressions.json` are among the allowed orchestrator edits.

**Step 0: check the run ledger (mandatory, before dispatching the learning agent).** This is the moment the check happens — the point every `/audit` and `/full-audit` run already passes through — not a new ritual; do not replace it with a separate dashboard.

```bash
bash "$AUDIT_BIN/run-stats.sh"
```

`RUNSTATS_RESULT=OK` or `SKIP (reason)`: no action, go to Step 1. `RUNSTATS_RESULT=ANOMALIES (N)`: append every `RUNSTAT <key>: <detail>` line to the current audit log's `## Open Points` section (create the heading if the log has none yet), tagged `AGED` and placed at the top of that section — the same escalation `full-audit/SKILL.md` Phase 4 already applies to a recurring open point or gap, labelled "open/present 3x+ — decision overdue": `run-stats.sh` only reports a condition once it has recurred, so every anomaly it surfaces already qualifies.

**Step 0.5: verify the recurrence feed was fed (mandatory, before dispatching the learning agent).** The per-verdict `patterns-store.sh recur` duty in `fix-loop.md` (Step D.7, or Step E at `floor=high`) is what populates `patterns.json`; the learning agent only reads it. On 2026-08-26 a run confirmed 10 findings and wrote 0 store entries, and nothing noticed until the retro. Check it here, deterministically:

```bash
TODAY=$(date +%Y-%m-%d)
CONFIRMED_N={number of CONFIRMED findings this run, from the audit log}
FED_N=$(jq -r --arg d "$TODAY" '[.recurrences[] | objects | select(.last_seen == $d)] | length' \
  "$(git rev-parse --show-toplevel)/.claude/audits/patterns.json" 2>/dev/null || echo 0)
echo "RECUR_FEED confirmed=$CONFIRMED_N fed_today=$FED_N"
```

`FED_N >= CONFIRMED_N` (or `CONFIRMED_N=0`): go to Step 1. `FED_N < CONFIRMED_N`: back-fill NOW, before the agent runs: call `patterns-store.sh recur {pattern}` once per confirmed finding that has no entry yet (same normalized pattern string the verdict table would have used), re-run the check, and write one line under `## Notes` in the current audit log (`Recurrence feed: {CONFIRMED_N - FED_N}/{CONFIRMED_N} confirmed findings back-filled at Phase 5, per-verdict recur was skipped`). A back-fill is a process failure worth recording, not a silent repair: the learning agent must see the note so the retro can name it.

**Step 1: dispatch the learning agent**

```
Agent(
  subagent_type: general-purpose,
  model: sonnet,
  prompt: "Read agents/learning-agent.md and run the process.
    PROJECT_ROOT={PROJECT_ROOT}
    AKTUELLES_LOG={Inhalt des gerade geschriebenen Audit-Logs}
    AUDIT_TYPE=audit",
  run_in_background: false
)
```

**`run_in_background: false` is mandatory, not decoration.** Since Claude Code v2.1.198 subagents run in the background by default, and a background subagent's result only arrives as a completion notification in a *later* turn. Phase 5 has to parse that output and write the log in *this* turn, before Phase 6 writes the push marker, a backgrounded learning agent silently loses the whole learning pass. Foreground costs 5-10s and is not push-blocking.

**Step 2: parse the output**

The agent returns three blocks between `LEARNING_RESULT_START` and `LEARNING_RESULT_END`: `SUPPRESSIONS_TO_ADD` (JSON array), `LEARNING_LOG_ENTRY` (markdown up to `LEARNING_LOG_ENTRY_END`), and `TRENDS_BLOCK` (markdown between `TRENDS_BLOCK_START` and `TRENDS_BLOCK_END`). The suggestions for guideline/agent changes are included as `- [ ]` checkboxes in the `Suggested improvements` section of the `LEARNING_LOG_ENTRY`.

**Step 3: the orchestrator writes**

- append `LEARNING_LOG_ENTRY` to `.claude/audits/learning-log.md` (or create it if this is the first audit)
- insert `TRENDS_BLOCK` at the top of `learning-log.md` or replace the existing block (do not append — it should stay a top snapshot)
- before persisting a NEW pattern key via `patterns-store.sh` (`add` or `recur`) or a new suppression, grep the existing store for keys that describe the same thing under a different name; if one exists, reuse or merge instead of creating a twin. Reference case: blade-duplication landed under two names on 2026-08-05 and fragmented the recurrence count.
- merge `SUPPRESSIONS_TO_ADD` into `.claude/audits/suppressions.json`. **If the file does not exist, create it first** (`{"suppressions": []}`) — any audit run, log, or finding that references a suppression MUST leave a valid `suppressions.json` behind; a dangling reference without the file is an orchestrator bug. **Dedup rule:** run the pattern of every new suppression through `bash "$AUDIT_BIN/normalize-suppression.sh"`, same normalization for existing suppressions. If both produce the same key → keep the existing one, discard the new one. This way "[Security] LIKE injection in scope" and "Like-wildcard injection (security)" are recognized as the same. **Consent gate (mandatory):** after dedup, present the remaining genuinely-new patterns to the user (chat, or `AskUserQuestion` when available) and write only the ones they approve — `SKILL.md`'s "Allowed orchestrator edits" rule lists `suppressions.json` explicitly as "(with user consent)"; a suppression is LLM-proposed and permanently silences a class of future finding, so it does not get written unasked.
- show in the chat: number of new suppressions and number of new open backlog points. The user knows they'll be asked at the next `/audit` (or `/full-audit`).

---
