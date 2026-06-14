---
name: review
description: |
  Two-axis code review: checks that implementation follows coding standards (Axis 1) AND
  matches what the linked issue or PRD specified (Axis 2). Axes run in parallel and produce
  independent findings. Use before merging a feature branch, after implementing a spec, or
  when asked to review a PR. Complements /audit (which is pre-push and diff-scoped);
  /review is triggered manually and can target any files or a spec.
model: sonnet
effort: medium
allowed-tools:
  - Read
  - Edit
  - Bash
  - Grep
  - Glob
  - Agent
---

# Review

Two independent axes. Standards violations and spec mismatches are different problems
answered by different agents running in parallel.

**Axis 1 — Standards:** Does the code follow project conventions, patterns, and guidelines?
**Axis 2 — Spec:** Does the implementation match what the issue/PRD asked for?

If no issue or PR is linked: Standards only.

## Phase 0: Scope

### Files to review

Argument given (e.g. `/review app/Http/Controllers/Foo.php`): use those files.

No argument:
```bash
# On a feature branch
git diff main...HEAD --name-only 2>/dev/null

# On main / no upstream
git diff --cached --name-only 2>/dev/null
```

If no changed files found: ask the user which files to review.

### Spec (for Axis 2)

Try in order:
```bash
# 1. Current branch PR
gh pr view --json number,title,body,url 2>/dev/null

# 2. Specific issue number if given as argument (/review 42)
gh issue view {N} --json number,title,body,url 2>/dev/null

# 3. Issue linked in recent commits
git log --oneline -5 2>/dev/null
# Look for "Closes #N", "Fixes #N", "Refs #N" patterns; fetch that issue
```

If no spec found: skip Axis 2. Note this in output: "Spec axis skipped (no linked issue/PR)."

### Project guidelines

```bash
cat .claude/audit-guidelines.md 2>/dev/null | head -100
```

## Phase 1: Parallel Review

Dispatch both agents simultaneously.

### Standards Agent (agents/standards-reviewer.md)

Input:
- Changed file list (with paths)
- Content of `.claude/audit-guidelines.md` (if exists, first 100 lines)
- Instructions to read each changed file and check it against visible conventions

### Spec Agent (agents/spec-reviewer.md)

Input:
- Issue/PR body (the spec)
- Changed file list
- Instructions to check coverage (is everything in the spec implemented?) and
  contradiction (does the implementation do something the spec disallows?)

Skip if no spec found in Phase 0.

## Phase 2: Consolidate

Merge both agents' findings.

Deduplication: same file:line in both axes = one finding, labeled `[Standards + Spec]`.

Group output:

```
## Axis 1: Standards

### Critical
- {file}:{line} — {what violated} ({which guideline or visible pattern it breaks})

### Important
- ...

### Minor
- ...

## Axis 2: Spec

### Missing (in spec, not in implementation)
- Spec says: "{acceptance criterion or feature description}"
  Not found in: {files reviewed}

### Contradicts (implementation does something the spec disallows or inverts)
- Spec says: "{expected behavior}"
  Implementation: {file}:{line}
```

Finding format: max 50 words, file:line refs only, no code snippets (same rules as /audit workers).

## Phase 3: Resolution

For each Critical or Important finding, offer resolution:

- **Fix now** — dispatch `../audit/agents/fix-agent.md`, verify with `../audit/agents/fix-verifier.md`
- **Accepted deviation** — document why the deviation is intentional (recorded in output)
- **Spec update** — the implementation is better than the spec; user updates the issue/PRD

Rules:
- Critical Standards findings must be fixed or explicitly accepted. Never silently deferred.
- Spec mismatches must be fixed or the spec updated. A divergence without a decision is a bug waiting to happen.
- Minor findings: listed, no resolution required.

Use AskUserQuestion when there are multiple Critical/Important findings to decide at once.

## Phase 4: Output

```
Review complete

Standards axis: {N} findings ({C} critical, {I} important, {M} minor)
Spec axis:      {N} findings ({X} missing, {Y} contradicts)
Skipped:        {axis if no spec / no files}

Fixed this run:         {N}
Accepted deviations:    {N} (see log)
Spec updates needed:    {N}
```

Write results to `.claude/reviews/{date}-{branch}.md` if the directory exists,
otherwise print only.
