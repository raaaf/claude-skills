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

**Do not thin the list.** Near-duplicate or similar-looking files are not a reason to drop one —
list every relevant file, even 10+ structurally similar layout variants. A prior scout run dropped
14 layout variants as "near-duplicate" and the specialist that would have caught the defect in the
dropped files never ran. Coverage at this stage is cheap; a dropped file is not recoverable
downstream.

**`FLOOR_FILES` is a floor, not a ceiling.** You may add any file from `SCOPE_FILES` you judge
relevant, but you may never omit a `FLOOR_FILES` entry. `find.js` checks this in code: a missing
Floor file is added back and logged, never silently dropped — treat that as a safety net, not
permission to skip the check yourself.

**Diff-mode context files (`SCOPE=diff` only):** for each file in `SCOPE_FILES`, you may
additionally list up to 5 files it directly imports or that directly call it, tagged
`tag: 'context'`, with `reason` stating the import/call relationship. Context files are read by the
specialist but never produce their own findings — only findings the diff itself causes there.

## Output

Reply with the scout-files schema: `files[{path, tag, reason}]`.
