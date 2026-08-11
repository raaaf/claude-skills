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

If `>= 1`: ask the user via `AskUserQuestion` with options:

- **Apply suggestions now** → list the suggestions, user picks which ones, orchestrator dispatches matching changes to `audit/guidelines/*.md` or `audit/agents/*.md`. **IMPORTANT — edit the source repo:** `~/.claude/skills/*` can be a sync target (symlink or unpacked `.skill` bundle) whose contents get overwritten. Before the first edit, resolve the source (`readlink` or find the skill source repo, e.g. `~/Local Sites/claude-skills`) and edit THERE — edits in the unpacked copy are lost on the next sync. After applying: change `[ ]` to `[x]` in learning-log.md. Then continue the audit with Phase 1.
- **Later, audit now** → start Phase 1, suggestions stay open.
- **Never ask again for these audits** → append a `[skip]` marker to the affected lines, they no longer count.

If `0`: continue without asking.

## Open Audit Issues & PRs (Phase 0.2)

```bash
if gh repo view >/dev/null 2>&1 && git remote get-url origin 2>/dev/null | grep -q github.com; then
  OPEN_AUDIT_ISSUES=$(gh issue list --state open --label audit-finding --json number,title --jq '.[] | "#\(.number) \(.title)"' 2>/dev/null || true)
  OPEN_PRS=$(gh pr list --state open --json number,title,headRefName --jq '.[] | "#\(.number) \(.title) [\(.headRefName)]"' 2>/dev/null || true)
fi
```

**Open `audit-finding` issues present?** → AskUserQuestion (show the list compactly):

- **Fix along with this run** — selected issues are fed into round 1 as verified findings (fix agent + fix-verifier as usual). After a successful fix: `gh issue close {N} --comment "Fixed in audit {DATUM}, commit folgt im naechsten Push."`
- **Leave open** — issues stay, audit runs normally.

**`OPEN_PRS` not empty?** → note as context (no question):

- In the Phase 3f dedup: no new issue for something an open PR already addresses.
- If an open PR touches the same files as the current diff: note in the audit log (`## Notes: PR Overlap`) — merge conflict risk.
