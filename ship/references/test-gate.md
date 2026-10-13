# Phase 2b: test gate, background

Moved out of `ship/SKILL.md` verbatim (2026-10-13) to keep the orchestrator under 500 lines.

## Why every test run goes through test-lock.sh

The lock keys on the repo plus
the `-destination` id, so two `xcodebuild test` runs against one simulator serialize instead of
killing each other with "Early unexpected exit ... signal kill", a failure that reads like a product
crash and is not one.

`--cached` marks the declared command as the full suite: a green, flake-free run on an identical tree within
30 minutes (same command, tool versions, lockfiles) is reused, whether `/audit`, `/ship` or `deploy <app> test`
ran it, and prints `TEST_CACHE_HIT <key>`. The run is admitted as a `suite` (or `xcode`) run, watched for stalls
and restarted once (`TEST_RESTART`). Details: `audit/CLAUDE.md`.

## Why this phase exists

Why this phase exists: `/audit` deliberately runs only the *affected* tests, on the assumption
that CI runs the full suite on every push. That assumption does not hold for repos whose CI only
runs on pull requests while work is pushed straight to `main` — there, nothing would ever run the
full suite before production. `TEST_COMMAND` closes that hole.

