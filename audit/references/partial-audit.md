# Partial Audit: Dimension Scoping via Argument (Phase 0.6 Detail)

Loaded by `audit/SKILL.md` Phase 0.6 when the skill argument looks like a dimension selection.

## Argument parsing

| Argument | Meaning |
|---|---|
| (empty) | Full audit as usual: deterministic floor routes automatically, push gate active |
| Dimension list, comma/space separated | e.g. `security` or `performance,a11y` — keys: `architecture, security, performance, code_quality, seo, a11y, typography, ui_design, ux, animation, docs_sync, copy` |
| `backend` | `architecture,security,performance,code_quality,docs_sync` |
| `frontend` | `seo,a11y,typography,ui_design,ux,animation,copy` |
| `design` | `typography,ui_design,ux,animation` (diff-scoped design check; for the full-surface elevation pass use /design-audit) |
| `?` | AskUserQuestion multi-select over all 12 dimensions, then continue as partial audit |
| Anything else (paths, prose) | Not a dimension selection — treat as free-text scope hint, `PARTIAL_AUDIT=0` |

Unknown dimension keys in a list: report them, continue with the valid remainder; zero valid keys → treat the argument as a scope hint.

## Effects when `PARTIAL_AUDIT=1`

Everything else runs unchanged — Phase 1 pre-checks, fix-loop, fix-verifiers, learning:

- **Skip triage (C.0) and floor (C.0.5) entirely.** Routing IS the user's explicit choice: `ROUTING_RUN = SELECTED_DIMENSIONS`, log line `Routing: lief [{list}]; uebersprungen [alle uebrigen: user-scoped]` (same shape as the floor's line; chat every round + audit log `## Routing`). The floor must not force deselected dimensions back on.
- **Orchestrator extra checks in Step D** run only when a governing dimension is selected: public pages/changelog check → `seo`/`copy`/`docs_sync`; tests-for-changed-logic check → `code_quality`/`architecture`; mobile impact → `ui_design`/`ux`/`a11y`.
- **Phase 4 NEVER writes the push marker.** A partial audit is not a push gate. Final output must state: `Teilaudit ({list}) — kein Push-Gate. Fuer den Push /audit ohne Argument ausfuehren.` The `AUDIT_STATUS:` round contract stays unchanged (Stop hook).
- **Secret scan and all other Phase 1 pre-checks ALWAYS run** — found secrets are reported as Critical regardless of scope; since no marker is written, the push stays blocked anyway.
- Audit log header notes the scope: `Scope: partial ({list})`.
