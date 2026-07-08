# Manual Test Plan — Generation

If visual files are in the diff (FRONTEND_DATEIEN or VISUELL_RELEVANTE_DATEIEN not empty), generate a concrete test plan the user can walk through locally.

## Template

```markdown
## Manual Test Plan

**Branch:** {BRANCH}
**Changed visual files:** {list}

### Steps

1. [ ] **{page name}** — {URL or route}
   - Check: {what changed, e.g. "new button variant 'danger'"}
   - Test desktop + mobile
   - {specific note, e.g. "check dark mode if active"}

2. [ ] **{page name}** — {URL or route}
   - Check: {concrete change}
   ...

### What to Watch For
- {edge cases from the diff, e.g. "empty state when no items are present"}
- {responsive behavior, e.g. "table collapses into cards below 768px"}
- {a11y-relevant, e.g. "new buttons must be keyboard-reachable"}
```

## Rules

- Only steps for actually changed spots — no generic "check everything" plan.
- Derive URLs/routes from the framework:
  - Next.js: file path = URL
  - Laravel: consult `routes/web.php`
  - Nuxt: `pages/` = URL
  - Inertia/Livewire: check controller routes
- Max 10 steps — prioritized by visibility and risk.
- Purely textual — no external tools or servers needed.

## Where the Test Plan Ends Up

1. Write it into the audit log under `## Manual Test Plan`.
2. Output it in chat (part of the 3e output).
