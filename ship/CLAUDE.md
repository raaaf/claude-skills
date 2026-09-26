# /ship internals

Rules bound to `/ship`'s own pipeline. Cross-cutting rules (marker hashing, `test-command:`/
`deploy-command:` trust boundary) live in the root `CLAUDE.md`.

## Gotchas

- **`/ship`'s docs phase and `/audit`'s docs_sync worker are different jobs, and the ship one runs before the commit on purpose.** Phase 0.8 in `ship/SKILL.md` inventories the repo's own docs (README, CLAUDE.md, CHANGELOG, `docs/**`, help pages, `.env.example`, `SKILL.md`), runs `check-docs-claims.sh` for the mechanical part, and updates whatever the diff invalidated. It sits before Phase 1 so the change and its documentation land in one commit rather than in a follow-up nobody writes; Phase 1's `git add -u` picks the edits up, since every file it may touch is already tracked. **It never creates a doc file that does not exist** (this repo has no CHANGELOG, and `/ship` must not invent one) and it never rewrites prose the diff did not invalidate. The audit worker still exists and is not redundant: it only fires when the routing floor sees a doc-shaped path in the diff, so a pure code change that silently outdates the README reaches the floor's blind spot, which is exactly the gap this phase closes. `/ship` therefore needs `Edit` in `allowed-tools`; it previously had only `Read`/`Write`, and a whole-file `Write` is the wrong instrument for a surgical README correction. Doc-only edits deliberately do not invalidate a fresh audit marker: they are prose by the same definition `classify-diff.sh` uses, so Phase 2 keeps checking marker age only.
