# Phase 2b: test gate, background

Moved out of `ship/SKILL.md` verbatim (2026-10-13) to keep the orchestrator under 500 lines.

## Why every test run goes through test-lock.sh

The lock keys on the repo plus
the `-destination` id, so two `xcodebuild test` runs against one simulator serialize instead of
killing each other with "Early unexpected exit ... signal kill", a failure that reads like a product
crash and is not one.

`--cached` marks the declared command as the full suite: a green, flake-free run on an identical tree within
30 minutes (same command, tool versions, lockfiles) is reused, whether `/ship`, `deploy <app> test` or an
`/audit` that fell back to the full suite (`AFFECTED=full`) ran it, and prints `TEST_CACHE_HIT <key>`. The run is admitted as a `suite` (or `xcode`) run, watched for stalls
and restarted once (`TEST_RESTART`). Details: `audit/CLAUDE.md`.

## Why this phase exists

Why this phase exists: `/audit` deliberately runs only the *affected* tests (`affected-tests.sh`,
since 2026-11-07 again), so this phase is the one place before production where the full suite runs. CI is no
substitute: the assumption that it runs the full suite on every push That assumption does not hold for repos whose CI only
runs on pull requests while work is pushed straight to `main` — there, nothing would ever run the
full suite before production. `TEST_COMMAND` closes that hole.

