# PR Creation After a Successful Push

Only run if the push succeeded AND we're on a feature/fix branch.

## Step 1 — Check Whether a PR Makes Sense

```bash
CURRENT_BRANCH=$(git branch --show-current)
DEFAULT_BRANCH=$(git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's@^refs/remotes/origin/@@' || echo "main")
```

Abort if:
- `CURRENT_BRANCH` is `main`, `master`, or `$DEFAULT_BRANCH`
- `gh pr view` already shows an open PR for this branch
- `gh auth status` fails (not logged in)

## Step 2 — Gather Data

```bash
# Commits since base branch
git log origin/$DEFAULT_BRANCH..HEAD --oneline

# Changed files
git diff origin/$DEFAULT_BRANCH...HEAD --stat

# Look for a plan doc (if any)
ls docs/plans/*.md 2>/dev/null
```

If a plan doc exists that matches the current feature (date or topic in the filename), use its content as context for the PR description.

## Step 3 — Create the PR

Title: Conventional Commit style, derived from the commits. Examples:
- `feat: add time entry bulk export`
- `fix: correct invoice calculation for partial hours`
- `refactor: extract billing service from controller`

Body via HEREDOC:

```bash
gh pr create --title "$TITLE" --body "$(cat <<'EOF'
## Summary
- What was done
- Why
- Key details (optional)

## Changes
- **Added:** new features/files
- **Changed:** changed behaviour
- **Fixed:** fixed bugs

## Test Plan
- [ ] Relevant test steps
- [ ] Edge cases

## Breaking Changes
Description if any

Generated with [Claude Code](https://claude.ai/code)
EOF
)"
```

Write the PR body in the repo's language (public repos: English). Do not hardcode a model name
into the body — the commit trailer already carries the Co-Authored-By line.

Omit empty sections — don't fill them with "None". No breaking changes? Omit the section.

## Step 4 — Output the PR URL

PR created? Show the URL. Error? Report and continue — a failed PR does not block the push.
