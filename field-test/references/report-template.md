# field-test report: <thread>

Status: NOT_STARTED
<!-- one of NOT_STARTED | RUNNING | DONE | BLOCKED. DONE only after every surface below is closed and the final
     self-check ran. BLOCKED: nothing could run at all; the reason follows on the same line, e.g. `BLOCKED: git`. -->

- Repo: <absolute path of the main checkout>
- Worktree: ~/Developer/_worktrees/<repo>-field-test
- Branch: fix/field-test-<YYYY-MM-DD> (base: <default branch> at <short sha>)
- Started: <ISO time> | Updated: <ISO time> | Budget: 3 h thread, 90 min per iOS product
- Skills loaded for judging: <list>

## Surfaces

One block per surface, in the order given. Axis values: `covered`, `partial (<what is missing>)`,
`blocked: <reason>` (reasons: setup, login, sim-lock, git, no-backend-override, no-seed, no-device-type,
no-test-code, budget). An axis that was not run is never `covered`.

### <surface name> (web | ios)

| Axis | Status | Notes |
|---|---|---|
| Widths 320 / 375 / 768 / 1024 / 1440 | | |
| Touch (<= 1024) | | |
| Dark | | |
| Slow 3G (375) | | |
| Dynamic Type (large, AX-XXXL) | | iOS only |
| Network proxy (3G, offline) | | iOS only |
| Landscape, keyboard open, split view | blocked: no-test-code | iOS only |

Views captured: <n> (cap 15 per web surface, 10 per landing). Metrics file: <path to metrics.json>.

## Fixes

| Id | Class | View | Cell | Before | After | Commit |
|---|---|---|---|---|---|---|
| F1 | broken or taste | <route or screen> | <width / theme / touch or device / size> | <png path> | <png path> | <short sha> |

Commit message form: `fix(ui): <what> [field-test]`. First commit may be `chore: screens scaffolding [field-test]`.

## Not fixed

| View | Cell | Problem | Why not fixed (test failed twice and undone, over the 20-fix cap, needs a product decision) |
|---|---|---|---|

## Open taste notes

Judgements that were not changed because the change would alter the design intent. One line each, with the view and cell.

## Log

Append-only, one line per event: `<time> <surface> <event>`. Setup results (HTTP 200 check), port and cwd check,
budget stops.
