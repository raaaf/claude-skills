# Phase 2 notes (moved out of SKILL.md)

Read by `audit/SKILL.md` Phase 2: why `hunkScope` exists, and how to merge a resumed `find.js` run.

## Why `hunkScope`

On 2026-09-25 (events repo) three audits in a row reported mostly Important
findings in untouched, pre-existing code of files the diff merely touched, turning every release
into an open-ended refactor. On any diff above `SMALL`, `hunkScope` makes every specialist (and the
verifier, so it can refute one that slips through) diff each assigned file against `BASE_REF` and
report a finding only if it falls inside a changed hunk (plus 15 lines of context) or the change
makes pre-existing code wrong. `find.js` excludes `payments` from this by itself: its scope is
deliberately the whole `STRIPE_FILES` surface, not the diff's hunks.

## A resumed run is not idempotent

Merge its verdicts, do not trust them as a drop-in replacement. On 2026-09-16 (raaaf/neues-feedback) a usage-limit interruption at 76/88 agents and a resume on the same diff produced a materially different verdict set (0 Critical/23 Important before, 1 Critical/30 Important after), and one finding id (`a11y-0-1`) was reused by both passes for two different findings and had to be re-added by hand. `resumeFromRunId` replays completed agents from cache but re-runs whatever had not finished, including verifiers, so the pre-interruption and post-resume passes can legitimately disagree on the same code. When a run returns after a resume:

- Union the two verdict sets **by finding content** (dimension + file + line + a normalized description), never by `id` — ids are assigned per pass and are not stable across a resume.
- Before merging, check for id collisions between the two passes (same id, different finding content). A collision means the log stub or an earlier manual edit already used that id for the pre-interruption finding; give the post-resume finding a new id rather than overwriting the entry silently.
- Where the two passes disagree on the same underlying finding (e.g. severity, or CONFIRMED vs REFUTED), keep the post-resume verdict — it saw more context (whatever became available after the interruption) — but note the disagreement under `## Notes` so the learning phase can see it, not just the winning verdict.
