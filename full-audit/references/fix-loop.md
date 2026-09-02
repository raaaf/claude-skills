# Fix Wave: Auto-Fix, Dedup Sweep, Regression Pass (Phase 2, Step C + After-Round Passes)

Runs after Step B/B.5 (consolidate + hallucination validator) each round: Step C verifies and fixes,
the dedup sweep catches cross-agent duplicates the per-agent grep in `fix-agent.md` cannot see, and
the regression pass covers the batch's last round, which has no following round to check it.

## Contents

- Step C — auto-fix (ALL findings)
- Per-round dedup sweep (after fixes, before the next round)
- Regression pass after the final round (MANDATORY)

## Step C — auto-fix (ALL findings)

TodoWrite: `Round {RUNDE} — fix findings` (in_progress).

**Base rule:** everything gets fixed except what the verification stage refutes.

**Finding verification before the fix wave (same stage as `/audit` Step D.7).** Workers report for coverage, including findings they are unsure about, so the filter sits here and not in the finder. Dispatch one `{AUDIT_AGENTS}/finding-verifier.md` subagent (sonnet, fresh context) per selected finding, all in one message block, max 10 in parallel, each with `run_in_background: false` (its verdict gates the same round's fix wave). Verdicts: `CONFIRMED` → fix wave (apply `SEVERITY_CORRECTION` if not `none`); `REFUTED` → discarded before any fix, one log line with the reason, never an issue; `UNCERTAIN` (also: missing or unparseable reply) → not fixed, listed under `### Unverified` in the batch log. Print `Verification: {X} confirmed, {Y} refuted, {Z} uncertain (of {N})`.

Selection gate (scales with `CONFIDENCE_FLOOR` from Phase 0.7):
- `floor=high` (low effort): no verification stage; fix only `high`, rest stays in the log
- `floor=medium` (medium effort): `high` goes straight to the fix wave, `medium`+`low` through verification first
- `floor=low` (high/xhigh effort, default): every Critical/Important finding through verification, `high` confidence included

Minor findings skip verification: they are only fixed at high/medium confidence anyway.

Fix Minor findings when `FIX_MINOR=1` (medium/high/xhigh). Unfixed Minor findings stay ONLY in the log.

**Open points are ONLY genuine decision points** (architecture tradeoffs, behavior changes) — everything else gets fixed or discarded.

**HARD RULE: the orchestrator NEVER edits code files itself.** Every fix, no matter how trivial, goes via a parallel fix subagent (Sonnet). Orchestrator edits on Opus cost a multiple.

**Allowed orchestrator edits:** `.claude/audits/*.md` (log + state file), `.claude/audits/full-audit-batches/*.txt`, `CLAUDE.md` context draft, `suppressions.json`, changelog files.

- 0 findings AND `UNCOVERED_BY_DIM` empty → `CLEAN`. 0 findings WITH `UNCOVERED_BY_DIM` non-empty → NOT clean: no fix wave needed, but the round-disposition table still applies — see `full-audit/SKILL.md`, section "After every round" (carry the unread files into the next round, or mark the row `blocked` if this was the batch's last round) — a dimension that never finished reading is not the same as a dimension that found nothing.
- Otherwise: fix all high/medium via fix subagent. Group findings by file, bundle multiple findings per file into one fix-agent call.
- **Centralization findings (new shared utility / helper / trait):** if a finding extracts a duplicated pattern into a new `lib/*.js` (or similar), FIRST grep all occurrences (`grep -rn "{altes_pattern}" src/`, adjust the glob to the project language) and hand ALL matching files to ONE single fix agent (no parallel split, or file collision results). Mark as a centralization fix so the fix agent applies the extended file boundary (see `fix-agent.md` special case) and migrates every occurrence.
- **Cross-finding dependencies before parallel dispatch:** before dispatching fix agents for the round in parallel, scan the findings for pairs that depend on each other — fix A references a helper/extension that fix B creates in the same run, or fix C reads a file derived from a source that fix D rewrites. Sequence such pairs (A after B, C after D) or merge them onto one agent instead of relying on the round's own verification pass as the safety net; that pass only catches it one round late, after the broken intermediate state has already shipped as its own finding. This complements the centralization rule above, which only covers one finding wrongly split across agents — this one covers two distinct findings that depend on each other.
- **`FIX_RESULT=PARTIAL` (mandatory, never falls through as done).** The code changed but is incomplete — do not add it to `BEREITS_GEFIXT` (that list tells workers to stop reporting something, which would hide an unfinished fix instead of exposing it). Re-enter the finding into the round's confirmed-finding set under its original `file:line`/severity, description replaced by the agent's `remaining:` text; it counts toward the next round's Critical+Important tally like any confirmed finding, so the batch cannot go `CLEAN` while a `PARTIAL` remainder is outstanding. On the batch's final round there is no next round to carry it into — the regression pass below is explicitly scoped to check it, and if unresolved there, it is why the row goes `blocked` rather than `clean`.
- Add each fully `FIX_RESULT=APPLIED` fix to `BEREITS_GEFIXT`. Increment C/I/M in the batch row of the state file.
- Unclear fix → ask briefly. No "open point" without explicit user consent.
- **Hook-blocked files** (e.g. `.env.example` blocked by a write-protection hook): not a plain open point. Present a ready diff/copy-paste block in the chat and actively offer to apply it yourself via `!` command, not just list it.
- Result: `FIXES_APPLIED`.

## Per-round dedup sweep (after fixes, before the next round)

Parallel fix agents in one round share a working tree but cannot see each other's edits, so two agents can independently add the *same* new top-level declaration (helper, extension, method, state mapping) in different files. The per-agent same-diff grep in `fix-agent.md` only sees one agent's own diff, so cross-agent duplicates slip through and surface as a fresh finding one round later.

After Step C applies the round's fixes and before starting the next round, run a short deterministic sweep over ONLY the round's own diff:

```bash
# top-level declarations the round introduced (adjust decl keywords to the project language)
git diff HEAD --unified=0 -- {round's changed files} \
  | grep -E '^\+' \
  | grep -Ei 'func |extension |struct |enum |class |static (let|var|func)|def |function |const ' \
  | sort | sed -E 's/^\+[[:space:]]*//' | sort | uniq -d
```

Any name that appears added in `>= 2` different files (or twice in one) is a candidate cross-agent duplicate: read both sites, and if they are the same logic, dispatch ONE centralization fix agent to collapse them (extended file boundary, per the centralization rule in Step C) before the next round runs. This is cheap (one grep over a small diff) and catches the class of duplicate — doubled firmware-state mappings, re-implemented analyzer helpers — that has repeatedly cost an extra round. It runs every round, including before the final regression pass.

## Regression pass after the final round (MANDATORY)

The last round applies fixes and no round is left to look at them. Every other round is checked by the one after it; this one would ship unchecked.

Dispatch ONE worker, scoped to the files the final round's fix agents actually touched (`git diff --name-only` against the round's starting state), not a full dimension sweep. Its brief is the seam, not the dimension:

- Fixes applied by parallel agents that could not see each other's edits: contradictions, half-applied changes, a comment that now describes something else, an import that no longer matches.
- State a fix forgot to reset, a lifecycle a fix left half-torn-down, a check a fix moved but did not re-verify from the other side.
- Anything the round's own fix reports flagged as "skipped" or "outside my boundary".
- Every `FIX_RESULT=PARTIAL` from this round: is the `remaining:` work actually done now, or does it still need another pass?

Findings from this pass are fixed like any other. It does NOT open a new round and does not extend `{MAX_RUNDEN_PRO_BATCH}`; on findings it cannot resolve, the row goes `blocked` rather than `clean`.

Why this is not optional: parallel fix agents with disjoint file boundaries are fast and blind to each other, and the regressions they introduce are caught only by a pass that looks at the seam.
