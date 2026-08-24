# Pre-Flight Checks: Learning Backlog + Open Issues/PRs

Loaded by `audit/SKILL.md` Phase 0. Two checks before the actual audit.

## Learning Backlog Check (Phase 0)

Check whether unprocessed learning suggestions from earlier audits are still open:

```bash
LOG="$(git rev-parse --show-toplevel)/.claude/audits/learning-log.md"
if [ -f "$LOG" ]; then
  COUNT=$(grep -c "^- \[ \] " "$LOG" 2>/dev/null)
  COUNT=${COUNT:-0}
else
  COUNT=0
fi
echo "$COUNT"
```

If `>= 1`: apply the open suggestions without asking, then continue the audit with Phase 1. List in one line which ones were applied. **IMPORTANT — edit the source repo:** `~/.claude/skills/*` can be a sync target (symlink or unpacked `.skill` bundle) whose contents get overwritten. Before the first edit, resolve the source (`readlink` or find the skill source repo, e.g. `~/Local Sites/claude-skills`) and edit THERE — edits in the unpacked copy are lost on the next sync. After applying: change `[ ]` to `[x]` in learning-log.md.

Leave a suggestion open (and name it) only when applying it would need a decision the log does not contain. Do not put the list up for selection.

If `0`: continue without asking.

## Open Audit Issues & PRs (Phase 0.2)

```bash
if gh repo view >/dev/null 2>&1 && git remote get-url origin 2>/dev/null | grep -q github.com; then
  OPEN_AUDIT_ISSUES=$(gh issue list --state open --label audit-finding --json number,title --jq '.[] | "#\(.number) \(.title)"' 2>/dev/null || true)
  OPEN_PRS=$(gh pr list --state open --json number,title,headRefName --jq '.[] | "#\(.number) \(.title) [\(.headRefName)]"' 2>/dev/null || true)
fi
```

**Open `audit-finding` issues present?** → show the list compactly, then fix them along with this run without asking: they are fed into round 1 as verified findings (fix agent + fix-verifier as usual). After a successful fix: `gh issue close {N} --comment "Fixed in audit {DATUM}, commit folgt im naechsten Push."`

Leave an issue open only when it touches files outside the current diff's scope, or when its resolution needs a decision the repo cannot answer. Name those, do not ask which ones to take.

**`OPEN_PRS` not empty?** → note as context (no question):

- In the Phase 3f dedup: no new issue for something an open PR already addresses.
- If an open PR touches the same files as the current diff: note in the audit log (`## Notes: PR Overlap`) — merge conflict risk.
