# Fix Loop: Verify Finding → Fix → Verify Fix (Phase 2, Steps D.5–E.5)

Runs every round, after Step D (consolidate). Four steps in order: D.5 discards hallucinated findings mechanically, D.7 verifies the rest semantically, E applies the fix, E.5 verifies the fix. Read by the orchestrator every round; this is the block that grows whenever the loop gains a rule.

## Contents

- Step D.5 — Hallucination validator
- Step D.7 — Finding verification
- Step E — Auto-fix
- Step E.5 — Fix verification

## Step D.5 — Hallucination validator (MANDATORY before every fix)

```bash
test -f "{datei}" || echo "HALLUCINATION: file missing"
[ "$(wc -l < "{datei}")" -ge "{zeile}" ] || echo "HALLUCINATION: line out of range"
```

External APIs/libraries: check with `grep -r` in the project whether imported. Filter out hallucinated findings. Output: `Validator: X/Y verified, Z hallucinated (discarded)`.

D.5 is mechanical only: it proves the file and the line exist, never that the problem does. The semantic check is D.7.

## Step D.7: finding verification (fresh context, BEFORE any fix)

Workers report for coverage and include findings they are unsure about (see `agents/prompt-template.md`); D.7 is the stage that pays for that. Refuting happens here, by a fresh verifier that never saw the finding produced, because self-critique by the finder or the consolidating orchestrator is weaker, and refuting a wrong finding costs a fraction of applying a wrong fix and reverting it.

**Selection (scales with `CONFIDENCE_FLOOR`):**

| Floor | Effort | Goes through D.7 |
|---|---|---|
| `high` | low | nothing (step skipped entirely, fast mode) |
| `medium` | medium | every Critical/Important finding with `confidence: medium` or `low` |
| `low` | high/xhigh | every Critical/Important finding, `high` confidence included |

Minor findings never go through D.7: they are only fixed at high/medium confidence anyway, and verifying them costs more than the fix.

**At `floor=low`, confirming a finding yourself by grep is not a substitute for D.7**, however mechanical it looks ("is the key I just deleted gone?", "does that line really say what the worker claims?"). A verifier costs one grep there too, so there is no cost advantage that would justify the skip. The run that produced this rule waved five of six Important findings through on self-confirmation and sent only the one product judgement to a verifier — which is exactly where the single genuine misjudgement of the set sat. Mechanical certainty is not the property that predicts a correct finding.

**Dispatch** one `finding-verifier.md` subagent (sonnet) per finding, all in one message block, max 10 in parallel.

**Bundling above roughly 20 findings.** One agent per finding is the default and stays the default for ordinary rounds. Past about 20 findings in a round it stops being affordable: a large run (2026-08-13, 33 findings and around 50 fixes) would have meant over 80 dispatches, and the orchestrator improvised the bundling instead of following the text, which is worse than having a rule for it. So: above that size you MAY group several findings that share a file or a risk area into ONE verifier call, provided both properties that make D.7 work are preserved — the verifier still has a fresh context, and it is never the agent that produced the finding. Grouping by file is the natural cut, because the verifier reads that file once either way. Requirements when you bundle: the briefing lists each finding separately with its own identifier, the reply carries one complete verdict block per finding (never one verdict for the group), and the audit log's `## Scope` block names the resulting agent-to-verdict ratio, e.g. "10 finding-verifier for 49 verdicts". A bundled run is not the same evidence as one agent per finding, and the log has to let a reader see which one happened. The same allowance applies to Step E.5.

```
Agent(
  subagent_type: code-reviewer,
  model: sonnet,
  prompt: "Read agents/finding-verifier.md and execute it.
    FINDING: {severity} {file:line} (confidence: {level}) {description}
    DIMENSION: {dimension}
    DIFF_CONTEXT: {diff hunk of the finding, if available}
    PROJECT_GUIDELINES: {PROJECT_GUIDELINES}
    DECIDED_TRADEOFFS: {DECIDED_TRADEOFFS}",
  run_in_background: false
)
```

**Verdict handling:**

| `FINDING_VERDICT` | Action |
|---|---|
| `CONFIRMED` | goes to Step E, with `SEVERITY_CORRECTION` applied when it is not `none` + `patterns-store.sh recur {pattern}` |
| `REFUTED` | discarded before any fix + `patterns-store.sh dismissed {pattern}`, one log line with the verifier's `REASON`. Never becomes an issue. |
| `UNCERTAIN` | not fixed. Goes into the audit log under `### Unverified` with the `REASON`. A Critical `UNCERTAIN` additionally becomes an open point for the user. Never silently dropped. |

A missing or unparseable verifier reply counts as `UNCERTAIN`, never as `CONFIRMED`: an unanswered verification is not a pass.

**Feed the store DURING the run, not only at the final retro.** The `recur`/`dismissed` calls above are the orchestrator's job, right where the verdict is decided — not a step reserved for the learning agent's end-of-run pass over the finished log. At `floor=high`, D.7 is skipped entirely (see the effort table above), so there is no verdict to hang `recur` on: call it instead at Step E when the finding enters the fix queue (same `{pattern}` string used for `patterns-store.sh add`, see Step E.7). Either way, `patterns.json` should already show this run's patterns by the time the learning agent reads it — the learning agent's own trends-block pass then only reports `recurrences`, it does not populate them from scratch.

Print after the step: `Verification: {X} confirmed, {Y} refuted, {Z} uncertain (of {N})`.

## Step E — Auto-fix

Count confirmed Critical+Important (D.7 output; without D.7, at low effort, the D.5-validated findings). Save `FINDINGS_AKTUELLE_RUNDE`. Convergence check: defined in `audit/SKILL.md`, Phase 2: Audit loop (search for `NO_CONVERGENCE`).

**0 Critical and 0 Important?** → `SAUBER`. Early exit (Minor never blocks push).

**Otherwise — confidence gate (scales with `CONFIDENCE_FLOOR` from Phase 0.5):**
- `floor=high` (low effort): fix only `high`, the rest stays in the log (no issues, no verification stage, low effort is the fast mode)
- `floor=medium` (medium effort): `high` goes straight to fix, `medium`+`low` go through Step D.7 first
- `floor=low` (high/xhigh effort): every Critical/Important finding goes through Step D.7, regardless of confidence

**From here on, open points are ONLY:** genuine decision points (architecture tradeoffs, behavior changes, scope questions) that an agent is not allowed to decide. Everything else gets fixed or discarded.

**Self-regression vs. pre-existing (prioritization):** if a finding is on a line that was changed in the current branch diff (`git blame`/diff comparison), it's a **self-regression** — ALWAYS fix, never park, even if it looks like a decision point (the branch introduced the problem). Only findings on unchanged, pre-existing lines may be parked as an open point.

**HARD RULE: the orchestrator NEVER edits code files itself.** Every code fix goes through a fix agent (Sonnet). Edits by the orchestrator on Opus cost a multiple.

**Allowed orchestrator edits:** `.claude/audits/*.md`, `CLAUDE.md` audit context draft, `suppressions.json` (with user consent), changelog files.

**The worktree-wide git ban applies to the orchestrator too, not just to fix agents.** `fix-agent.md`
forbids its subagents every destructive worktree-wide git command because parallel agents share one
working tree. The orchestrator shares that same tree — and the tree also holds the user's own
uncommitted work. On 2026-08-03 the orchestrator ran exactly the command it forbids its subagents,
in a tree with parallel writers, for exactly the reason that applied to it.

When you need a clean HEAD baseline (lint comparison, render comparison, "was this red before my
fixes?"), do NOT touch the shared tree. Use a throwaway worktree instead:

```bash
TMP=$(mktemp -d)
git worktree add --detach "$TMP" HEAD
# ... measure inside "$TMP" ...
git worktree remove --force "$TMP"
```

For a single file, `git show HEAD:<path>` is enough and touches nothing. Note that
`hooks/pretooluse-bash.sh` matches on the command string, so it also blocks a Bash call that merely
*writes about* these commands — author such documentation with the Edit/Write tool.

**Verify-by-measurement (perf) — baseline:** if the round contains a `[Performance]` finding and `PERF_MEASURE_CMD` is set, measure the baseline once BEFORE the fix agent dispatch: `eval "$(bash "$AUDIT_BIN/perf-measure.sh" --run "$PERF_MEASURE_CMD")"; PERF_BASELINE="$PERF_METRIC"`. Details: `references/perf-measurement.md`.

1. Group findings by file
2. Dispatch one `fix-agent.md` subagent (Sonnet) per file, in parallel
3. Multiple findings in the same file: bundle into one fix-agent call
3a. **Centralization findings (new shared utility):** if a finding extracts a duplicated pattern into a new `lib/*.js` / helper / trait, FIRST grep all occurrences (`grep -rn "{old_pattern}" src/`, adjust the glob to the project language) and pass ALL matching files to ONE fix agent (no parallel split, otherwise file collision). Mark as a centralization fix so the fix agent migrates every occurrence (see fix-agent.md special case).
3b. **Limit fix-wave size:** a fix assignment that touches >2 templates or contains a partial extraction gets split across multiple fix agents (except the centralization fix from 3a, which stays deliberately bundled) OR gets a report checkpoint: the fix agent MUST deliver an interim report before the final edits. Large assignments without a report checkpoint tend to silently abort, based on experience.
4. Collect results: `FIX_RESULT=APPLIED` counts as fixed. **If the agent report is missing entirely** (agent finishes without a `FIX_RESULT` line), do NOT assume the fix is lost: check `git diff` on the assignment's files — if changes are present, the fix counts as APPLIED and the fix-verifier run (E.5) is MANDATORY for these files (no silent skip).

4a. **Working-tree cross-check after EVERY parallel fix wave (MANDATORY, deterministic).** Do not trust `FIX_RESULT=APPLIED`. Build the set of files you assigned across all fix agents of this wave, then compare against reality:

```bash
ACTUAL=$(mktemp)
EXPECTED=$(mktemp)

# Expected = every file assigned to a fix agent in this wave (Step E, "group findings by
# file"). Populate WAVE_ASSIGNED_FILES yourself, one path per line, BEFORE this runs --
# it is orchestrator-known state, not carried over from any earlier command.
echo "$WAVE_ASSIGNED_FILES" | sort > "$EXPECTED"
git status --porcelain | sed 's/^...//; s/^.* -> //; s/^"//; s/"$//' | sort > "$ACTUAL"   # strip status+space, rename source, and git's quoting of paths with spaces
comm -13 "$ACTUAL" "$EXPECTED"   # assigned but NOT modified -> fix lost

# Stash-Check: ein Eintrag hier heisst, ein Fix-Agent hat trotz Verbot gestasht.
# Unabhaengig von jeder Selbstauskunft — der 2026-07-22-Verstoss wurde nur durch
# die Selbstmeldung des Agents entdeckt, dieser Check findet ihn deterministisch.
git stash list | grep -q . && echo "STASH DETECTED: Welle ungueltig"
```

`STASH DETECTED` → wait until every agent of the wave is idle, `git stash pop` to restore the erased work, re-run the cross-check above, and re-dispatch any still-missing assignment ALONE.

Any assigned file that is NOT modified means the fix never landed or was destroyed by a sibling agent, regardless of what that agent reported. Re-dispatch it ALONE, with no other agent running, and state in its briefing that the previous attempt was destroyed.

4b. **`FIX_RESULT=PARTIAL` (mandatory handling, never falls through unhandled).** The code changed — verify it: the fix-verifier run (E.5) is MANDATORY for these files, exactly like `APPLIED`. It is NOT a clean fix, so do not add it to `BEREITS_GEFIXT` (point 7) — that list tells workers to stop reporting something, which would hide the leftover instead of exposing it. Instead, the original finding (same `file:line`/`severity`/`dimension`) re-enters `FINDINGS_NAECHSTE_RUNDE` with its description replaced by the agent's `remaining:` text, skipping D.7 (already confirmed once). On `RUNDE < MAX_RUNDEN` this feeds directly into the next round's finding set, so it counts toward that round's `FINDINGS_AKTUELLE_RUNDE` like any confirmed finding — a round cannot report `SAUBER` while a `PARTIAL` remainder is outstanding. On `RUNDE = MAX_RUNDEN` there is no next round: see `audit/SKILL.md`, section "After each round", for where it lands (Phase 3f, tagged `Fix incomplete`).

5. Minor: with `FIX_MINOR=1` (medium + high/xhigh effort), fix all high/medium-confidence Minor findings, otherwise skip. Unfixed Minor findings stay ONLY in the audit log — never as an issue.
6. Not fixable because a decision is needed: as an open point with justification (see definition above). Not fixable for another reason (e.g. external system): discard + `patterns-store.sh dismissed {pattern}`
7. Add fixed issues to `BEREITS_GEFIXT`, into the learning store via `patterns-store.sh add`. At `floor=high`, also call `patterns-store.sh recur {pattern}` here (same string) — D.7 was skipped for this run, so this is the only point a self-confirmed finding gets counted. `FIX_RESULT=PARTIAL` is excluded from this step (see 4b) — only a fully `APPLIED` fix is a fixed issue.

## Step E.5 — Fix verification (MANDATORY for medium/high/xhigh effort, SKIP for low)

For every `FIX_RESULT=APPLIED` or `FIX_RESULT=PARTIAL`, dispatch a fix-verifier subagent (sonnet). Above roughly 20 fixes in a round the same bundling allowance as Step D.7 applies (group by file or risk area, one verdict block per fix, ratio named in the log); read it there before using it.

```
Agent(
  subagent_type: general-purpose,
  model: sonnet,
  prompt: "Read agents/fix-verifier.md and evaluate the following fix.
    ORIGINAL_FINDING: {finding}
    FIX_RESULT: {APPLIED|PARTIAL}
    FIX_DIFF: {diff_des_fix_agents}
    FIX_DATEI: {datei}
    REMAINING: {remaining text from the agent, if PARTIAL}
    PROJECT_GUIDELINES: {PROJECT_GUIDELINES}",
  run_in_background: false
)
```

Evaluation of `FIX_VERIFIER_RESULT`:
- `RECOMMEND=keep` → fix stays, continue
- `RECOMMEND=patch` → fix stays, but the finding stays in `FINDINGS_NAECHSTE_RUNDE` as "Fix needs improvement"
- `RECOMMEND=revert` → `git checkout {FIX_DATEI}` (revert the fix), original finding goes back into the open list

Parallelization: all verifiers in one message block, max 10 in parallel. Latency add: ~3-5s per round.

**Performance fixes — verify-by-measurement (when `PERF_MEASURE_CMD` is set and a baseline was taken in Step E):** re-measure after all fixes of the round: `eval "$(bash "$AUDIT_BIN/perf-measure.sh" --run "$PERF_MEASURE_CMD")"; PERF_AFTER="$PERF_METRIC"`. Deterministic verdict: `AFTER <= BASELINE` → perf fixes `keep` (log: `Verification: measured {BASELINE}->{AFTER}`); `AFTER > BASELINE` → regression, perf fixes as an open point + fix-verifier to narrow it down; `NA` → fallback to fix-verifier. Correctness/regression of other dimensions is still checked by the fix-verifier. Details: `references/perf-measurement.md`.
