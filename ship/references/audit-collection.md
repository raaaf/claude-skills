# Quick-fix collection (audit-collection)

Detail behind Phase 0.5, Phase 3, and Phase 5.5 in `ship/SKILL.md`. A quick fix shipped without an
audit (quick-fix mode, selected with `--quick` in Phase 0.5) is not gone forever: the base it sits on is recorded
so several quick fixes accumulate and can be audited together in one later `/audit` run, instead of
each shipping unaudited forever or forcing a full audit on every single small fix.

## Where the base is recorded

`orch_unaudited_record` (`audit/bin/lib-orchestrator.sh`) writes one sha into
`$(git rev-parse --path-format=absolute --git-common-dir)/claude-unaudited-base`: the upstream
`@{u}` if the branch has one, else the merge-base with the default branch (same derivation
`lib-git-base.sh`'s `resolve_base_ref` uses). It only writes when the file does not already exist,
so the OLDEST base wins across repeated quick fixes. `orch_unaudited_base` reads it back (rc 1 when
absent), `orch_unaudited_clear` removes it.

## Ship side

- **Phase 0 (run log setup)** reads the file (if any) up front and prints `UNAUDITED_COUNT`, the
  number of commits already pending collection; the Summary's `Audit:` line reports it.
- **Phase 3** calls `orch_unaudited_record` right before `git push`, but only when `SHIP_GATE`
  is `skipped` — a run that goes through the normal audit gate never needs this, its tree is
  already certified by a fresh marker.
- **Phase 5.5** (quick-fix mode only) asks nothing: it keeps collecting and the Summary reports the
  collected count. The audit of the collected range is a later, separate `/audit` run (which picks
  the base up on its own, see below); its fix wave produces working-tree changes on top of
  already-pushed commits, so those changes need their own `/ship`.

## Audit side

`/audit` Phase 1 (`audit/SKILL.md`) is the consumer: before deriving `BASE_REF` via
`collect-scope.sh`, it reads `orch_unaudited_base`. Three outcomes:

- **No file** — nothing changes, `/audit` resolves its base the normal way.
- **File exists, sha is an ancestor of HEAD** — export `AUDIT_BASE_REF=<that sha>` (which
  `resolve_base_ref` in `lib-git-base.sh` already honors ahead of its own resolution order) and
  print one line: `Including N collected quick-fix commits since <short sha>` (`N` from
  `git rev-list --count <sha>..HEAD`).
- **File exists, sha is NOT an ancestor of HEAD** (the branch was rebased and the recorded commit
  no longer exists in this history) — clear the file immediately with one line noting why, and
  resolve the base normally. Check ancestry with `git merge-base --is-ancestor <sha> HEAD`.

Once `/audit` writes its passed marker (Phase 4, `orch_marker_write`), call `orch_unaudited_clear`
unconditionally: the marker's own tree binding is now the thing that certifies this range, so the
older bookkeeping file has nothing left to add, whether or not it was actually used this run.
