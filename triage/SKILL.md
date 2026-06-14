---
name: triage
description: |
  GitHub issue state machine. Fetches open issues labeled needs-triage (or a specific issue
  number), classifies them, updates their state labels, posts a reasoning comment, and
  generates an agent brief for issues ready to be worked autonomously. Use after a batch of
  new issues lands or when the issue tracker needs a cleanup pass.
model: sonnet
effort: medium
allowed-tools:
  - Read
  - Bash
  - Agent
---

# Triage

Issue state machine. Every issue must leave in one of four states.

## States

| Label | Meaning |
|---|---|
| `needs-triage` | New, not yet assessed |
| `needs-info` | Not enough info to act on |
| `ready-for-agent` | Clear, self-contained, AFK-able |
| `ready-for-human` | Requires judgment or architecture decision |
| `wontfix` | Out of scope or by design |

`needs-triage` is the entry state. `needs-info`, `ready-for-agent`, `ready-for-human`,
`wontfix` are exit states. An issue in an exit state is not re-triaged.

## Phase 0: Check Prerequisites

```bash
gh repo view >/dev/null 2>&1 || { echo "No GitHub remote. Triage requires gh CLI + GitHub remote."; exit 1; }
```

Ensure labels exist:
```bash
for label in "needs-triage" "needs-info" "ready-for-agent" "ready-for-human" "wontfix"; do
  gh label create "$label" --color "$(echo $label | md5sum | cut -c1-6)" 2>/dev/null || true
done
```

## Phase 1: Fetch Issues

If an issue number was given (e.g. `/triage 42`): fetch only that issue.

Otherwise: fetch all open issues labeled `needs-triage`.

```bash
# Specific issue
gh issue view {N} --json number,title,body,labels,comments,url

# All needs-triage
gh issue list --label needs-triage --state open --json number,title,body,labels,url --limit 50
```

If no issues found: report and stop. Nothing to do.

## Phase 2: Triage Each Issue

For each issue, determine the exit state. Work through all issues before writing any labels.

### Classification

**Type:**
- `bug` — something that was working is broken
- `enhancement` — new capability requested
- `question` — asking how something works

**Exit state decision:**

| Condition | State |
|---|---|
| Missing: repro steps, expected vs actual, version info | `needs-info` |
| Out of scope, intentional behavior, duplicate | `wontfix` |
| Clear spec, bounded scope, testable, no architecture decision | `ready-for-agent` |
| Requires design tradeoff, breaking change, cross-team impact | `ready-for-human` |

**Ready-for-agent checklist (all must pass):**
- [ ] Expected behavior is unambiguous
- [ ] Acceptance criteria can be written from the issue body alone
- [ ] Scope fits in one PR (estimated < 200 lines changed)
- [ ] No dependency on another open issue or unresolved design question
- [ ] A competent agent can complete it without asking the reporter

If any box is unchecked: `ready-for-human` (not `needs-info`, unless the reporter needs to answer first).

### Agent Brief (ready-for-agent issues only)

```markdown
## Agent Brief

**What to do:** {clear task description, 2-3 sentences}
**Files likely involved:** {list from codebase scan or issue body}
**Acceptance criteria:**
{extracted or inferred from issue body as bullet list}
**Suggested skills:** {e.g. /diagnose for bugs, /plan-it for non-trivial features}

*AI-generated brief based on issue #{N}. Verify before acting.*
```

## Phase 3: Apply State Changes

For each issue:

1. Remove `needs-triage` label
2. Add the new state label
3. Post a comment with:
   - One-sentence reasoning for the state
   - If `needs-info`: exact list of what is missing
   - If `ready-for-agent`: append the agent brief
   - If `wontfix`: reason + reference to existing behavior or scope boundary

```bash
gh issue edit {N} --remove-label "needs-triage" --add-label "{new-state}"

gh issue comment {N} --body "$(cat <<'EOF'
**Triage:** {state}

{reasoning}

{agent brief if applicable}

*Triaged by /triage skill.*
EOF
)"
```

## Phase 4: Summary

```
Triage complete: {N} issues processed

  needs-info:       {N}
  ready-for-agent:  {N}
  ready-for-human:  {N}
  wontfix:          {N}

Ready-for-agent:
{list of issue numbers + one-line title}
```

Print the list of `ready-for-agent` issues so the user can start work immediately.
