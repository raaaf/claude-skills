# Full-Audit State File: Format, Resume, Loop Mode

Persistent goal-loop state for /full-audit, following the /feature-audit pattern. The entire loop progress (batches, rounds, finding counters, post-phases) lives in a file on disk, not in the conversation context — it survives session death, context compaction, and interruptions.

## Files

| File | Content |
|---|---|
| `.claude/audits/full-audit-state.md` | Matrix + header (the state file) |
| `.claude/audits/full-audit-batches/batch-NN.txt` | File list per batch, repo-root-relative, one per line |

Both are local run infrastructure (in `.gitignore`, like `cache.json`). Both paths are allowed orchestrator edits.

## Format

```
# Full-Audit State — v1
mode: BATCHED
effort: xhigh
dimensions: architecture,security,performance,code_quality
batch-dir: .claude/audits/full-audit-batches
post-phases: cross_ref=pending log=pending issues=pending
started: 2026-07-07

| ID | Directory | Files | Rounds | C | I | M | Status | HEAD |
|---|---|---|---|---|---|---|---|---|
| 01 | app/Services | 34 | 2/3 | 1 | 3 | 5 | clean | a1b2c3d |
| 02 | resources/views | 38 | 1/3 | 0 | 0 | 0 | running | - |
| 03 | app/Models | 22 | 0/3 | 0 | 0 | 0 | pending | - |

## Blocked / Needs review
- none
```

Rules:

- **Status values:** `pending` (not yet audited) | `running` (batch in progress) | `clean` (audited + fixed) | `blocked` (NO_CONVERGENCE or decision points).
- **Rounds** = `used/max` (e.g. `2/3`). **C/I/M** = accumulated findings of the batch across all rounds. **HEAD** = short SHA on batch completion (`git rev-parse --short HEAD`), else `-`.
- **Header keys machine-readable** (`key: value`, one line): `mode`, `effort`, `dimensions`, `batch-dir`, `post-phases`, `started`. Resume reads mode/effort/dimensions from here instead of asking the user again.
- **Cells must not contain a raw `|`** (breaks the awk parser) — escape as `\|` or rephrase.
- **SINGLE mode** = one batch row (ID `01`, Directory `.`).
- **Blocked section:** one checkbox bullet per blocked point (`- [ ] [ID] short description`). `- none` doesn't count. Blocked does NOT block completion, but must appear here AND in the audit log.

**Column rename note:** `Verzeichnis`→`Directory` and `Dateien`→`Files` are safe — neither `status-line.sh` nor `resume-check.sh` looks up those two columns by name at all (they're never read, only occupy a position). `Runden`→`Rounds` is safe because `status-line.sh` matches `c=="runden" || c=="rounds"` bilingually, and `resume-check.sh` doesn't reference the rounds column at all. Verified by reading both scripts (see below); do not rename `ID`, `Status`, or `HEAD` without re-verifying the same way.

## Scripts (bash 3.2, deterministic — Bash decides, not the LLM)

**`status-line.sh <STATE_FILE>`** emits exactly one line:

```
FULL_AUDIT_STATUS batches_total=3 pending=1 running=1 clean=1 blocked=0 rounds_used=3 critical=1 important=3 minor=5 blocked_items=1 post_phases=pending
```

`post_phases=done` only once ALL keys of the `post-phases:` line are `=done`. Missing file → zero line. The orchestrator decides completion ONLY from the line of the current turn, never from memory.

**`resume-check.sh <STATE_FILE>`** checks every `clean` row: batch list against everything that changed since the recorded HEAD (`git diff <head>..HEAD` + working tree via `git status --porcelain`). Output per clean batch: `BATCH_DIRTY id=NN files=K` or `BATCH_CLEAN id=NN`. Missing batch list or unresolvable HEAD → `BATCH_DIRTY files=unknown` (fail toward re-audit). The script only reads — resetting rows to `pending` is the orchestrator's job.

## Resume Semantics

If the state file exists when /full-audit is invoked:

1. Run `resume-check.sh`. Reset every `BATCH_DIRTY` to `pending` (Rounds `0/{max}`, zero C/I/M, HEAD `-`).
2. Reset `running` rows (session died mid-batch) to `pending` — half batches are re-audited from scratch, never resumed.
3. Take over mode/effort/dimensions from the header, skip phases 0.3-1.5, go directly to Phase 2 starting at the first `pending` batch.
4. `clean` batches are NEVER re-audited for confirmation.

**Non-determinism (important):** audit findings are LLM judgments, not reproducible tests. `clean` means "audited and fixed in this run", not "re-verifiably green" — a fresh worker run on unchanged code can produce different findings. Hence: no re-audit of clean batches, re-audit exclusively via the deterministic dirty check. (This is exactly where the loop differs from /feature-audit, whose rows are tied to real tests.)

Fresh finish and restart: delete the state file + `full-audit-batches/`, call /full-audit again.

## Loop Mode (optional)

Default stays single-session: all batches in one run, the state file is then just crash insurance.

For very large codebases, turn-by-turn via `/loop /full-audit`:

- `FULL_AUDIT_BATCHES_PER_TURN=N` (default without loop: all) — after N batches the turn ends with the `FULL_AUDIT_STATUS` line (verbatim as the last line), /loop fires the next one.
- **Stop conditions** (feature-audit pattern): the same batch `blocked` for 3 turns in a row without progress → leave the batch blocked, continue with the next one; 50 turns total → abort with a digest.
- NO new Stop hook (hook safety gotcha: `audit-loop.sh` belongs to /audit; the line is therefore called `FULL_AUDIT_STATUS`, never `AUDIT_STATUS`).

## Future Option (deliberately NOT built)

File-exact caching via `audit/bin/cache-check.sh`/`cache-write.sh` (sha256 per file): fix agents permanently invalidate the hashes during the run, resume granularity is the batch. If batch granularity ever gets too coarse, start here.
