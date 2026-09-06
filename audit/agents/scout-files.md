# Scout: File Scout

Dispatched once per dimension in `find.js` (except `architecture` and `docs_sync`, which use only
`scout-clusters.md`; `security` gets both scouts, merged in Stage 2). `agentType: 'Explore'`,
`model: 'sonnet'`, `schema: SCOUT_FILES_SCHEMA` (`references/finding-schema.md`).

## Input (from `find.js` args)

- `DIMENSION` — the dimension name and its search patterns (from that dimension's agent file's
  "Look for" block).
- `SCOPE_FILES` — every file in scope (`SCOPE=diff`: the diff file list; `SCOPE=repo`: the full
  tracked source list from `collect-scope.sh --all`). You may only select from this list, plus
  `context` files under the diff-mode allowance below.
- `FLOOR_FILES` — the subset of `SCOPE_FILES` that the deterministic floor (`check-skips.sh`, via
  `FRONTEND_EXT_RE` and the dimension signals in `lib-git-base.sh`) already assigns to this
  dimension.

## Task

List every file in `SCOPE_FILES` relevant to `DIMENSION`'s search patterns, tagged `tag: 'floor'`
for files also in `FLOOR_FILES`, `tag: 'scope'` for everything else you add.

**A file outside `FLOOR_FILES` is only listed if you can name a concrete trigger you actually saw
in it.** The `reason` field must name the specific construct in that file (a function, hook,
attribute, selector or pattern) that matches one of `DIMENSION`'s own "Look for" classes. A reason
of the shape "could contain", "might be relevant", "part of the frontend", "general utility", or a
restatement of the dimension name is not a trigger — leave that file out. This applies per file:
you must have actually looked at the file's content, not inferred relevance from its path, name, or
similarity to another file.

**Near-duplicates each get listed on their own trigger, never on a sibling's.** A prior scout run
dropped 14 layout variants as "near-duplicate" even though each one contained the trigger, and the
specialist that would have caught the defect in the dropped files never ran — so if several
structurally similar files each individually contain the trigger, list all of them. But a file with
no trigger of its own is never listed just because a similar file has one.

**`FLOOR_FILES` is a floor, not a ceiling.** You may add any file from `SCOPE_FILES` you judge
relevant, but you may never omit a `FLOOR_FILES` entry. `find.js` checks this in code: a missing
Floor file is added back and logged, never silently dropped — treat that as a safety net, not
permission to skip the check yourself. When the briefing says there are none for this dimension,
every file you list must still carry its own concrete trigger, and the list is expected to be a
small fraction of `SCOPE_FILES`, not most of it.

**Diff-mode context files (`SCOPE=diff` only):** for each file in `SCOPE_FILES`, you may
additionally list up to 5 files it directly imports or that directly call it, tagged
`tag: 'context'`, with `reason` stating the import/call relationship. Context files are read by the
specialist but never produce their own findings — only findings the diff itself causes there.

## Output

Reply with the scout-files schema: `files[{path, tag, reason}]`.
