---
# Pre-Flight Checks: Open Issues/PRs

Loaded by `audit/SKILL.md` Phase 0.

**Stop here when `AUDIT_SKIP_LEARNING_CHECK=1`** (name kept for compatibility with existing callers such as `audit/bench/run-case.sh`: benchmark runs against a throwaway worktree must not look at the real repo's issues and PRs).

## Open Audit Issues & PRs

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
