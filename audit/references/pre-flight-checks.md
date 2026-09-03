# Pre-Flight Checks: Learning Backlog + Open Issues/PRs

Loaded by `audit/SKILL.md` Phase 0. Two checks before the actual audit.

## Learning Backlog Check (Phase 0)

Check whether unprocessed learning suggestions from earlier audits are still open:

```bash
# Store root via --git-common-dir, never --show-toplevel: from a linked worktree the toplevel
# is the worktree, and 5 open items plus 8 suppressions were invisible that way (2026-09-03).
AUDIT_STORE_ROOT=$(git rev-parse --path-format=absolute --git-common-dir); case "$AUDIT_STORE_ROOT" in */.git) AUDIT_STORE_ROOT="${AUDIT_STORE_ROOT%/.git}";; *) AUDIT_STORE_ROOT=$(git rev-parse --show-toplevel);; esac
LOG="$AUDIT_STORE_ROOT/.claude/audits/learning-log.md"
if [ -f "$LOG" ]; then
  COUNT=$(grep -c "^- \[ \] " "$LOG" 2>/dev/null)
  COUNT=${COUNT:-0}
else
  COUNT=0
fi
echo "$COUNT"
```

If `>= 1`: apply the open suggestions without asking, then continue the audit with Phase 1. List in one line which ones were applied. After applying: change `[ ]` to `[x]` in learning-log.md and append ` (applied {DATE}: {file})` to the line.

**Edit the skill SOURCE repo, never `~/.claude/skills/`.** That directory is the unpacked sync target of `~/.claude/hooks/sync-skills.sh`; every edit made there is overwritten by the next sync. On 2026-09-03, 30+ edits from three weeks of Phase-0 runs were found only in the sync target and had to be ported back by hand. Resolve the source deterministically, in this order, and print the path you picked:

```bash
SKILL_SOURCE=""
for c in "$HOME/Developer/claude/skills" "$HOME/Local Sites/claude-skills" "$(readlink "$HOME/.claude/skills/audit" 2>/dev/null | xargs -I{} dirname {} 2>/dev/null)"; do
  [ -n "$c" ] && [ -f "$c/audit/SKILL.md" ] && [ -d "$c/.git" ] && { SKILL_SOURCE="$c"; break; }
done
# personal skills (live-audit, ...) live next to it:
SKILL_SOURCE_PERSONAL="${SKILL_SOURCE%/skills}/skills-personal"
echo "SKILL_SOURCE=${SKILL_SOURCE:-NOT_FOUND}"
```

`NOT_FOUND`, or the path not writable from this session (sandbox, read-only mount): do NOT edit the sync target instead, and do NOT silently leave the items open. Print each intended change as a ready-to-apply unified diff in the chat under `## Learning backlog: not applied (source repo unreachable)`, leave the items `[ ]`, and continue with Phase 1. Three sessions in a row (2026-09-01 to 09-03) skipped the backlog for this reason without saying so.

After editing the source, commit in the skill repo right away (decided 2026-09-03, so applied items no longer sit uncommitted for weeks). One commit per repo touched, no push, only the files this backlog application changed:

```bash
cd "$SKILL_SOURCE" && git add -A -- . ':!.claude' && git commit -q -m "chore(audit): apply learning backlog $(date +%Y-%m-%d)" && git log -1 --oneline
# same for "$SKILL_SOURCE_PERSONAL" when a personal skill was edited
```

If the repo already had unrelated uncommitted changes before you started, do not sweep them in: stage only the files you edited (`git add -- <files>`) and say so. Then run `bash "$HOME/.claude/hooks/sync-skills.sh"` once (it works from any cwd since 2026-09-03 and also runs on every session Stop) and say in one line whether it synced.

Leave a suggestion open (and name it) only when applying it would need a decision the log does not contain. Do not put the list up for selection.

If `0`: continue without asking.

## Open Audit Issues & PRs (Phase 0, second check)

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
