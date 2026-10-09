# Audit: 2026-10-09: Branch: fix/mutate-enum-pao

## Scope
- Base: 93bfce9 | HEAD at audit time: 80d9747 (fixes squashed into db0bd0b)
- Changed files: 6 (audit/bin/mutate.sh, audit/bin/mutate.test.sh, audit/CLAUDE.md, audit/bin/fixtures/mutate/pest-mutate-service.log, pest-mutate-service-pao.log, pest-mutate-enum-path.log) | Diff class: code
- Reviews run: code_review

## Pre-checks
- all OK/CLEAN

## Result
- Gate: passed
- Findings: Critical 0 / Important 2 / Minor 7 | Fixed 9 | Discarded 0 | Open 0
- Tests: mutate.test.sh under bash and /bin/bash MUTATE_TEST=OK, check-docs-claims, check-fresh-shell, check-silencing OK. Real run on a Pest project: enum file MUTATE_RESULT=OK with a score, one equivalent survivor.
- Kosten dieses Laufs: 18.44 USD (ca. 0.7 % der Woche), Woche ca. 26.7 % (lokale Schätzung über die Sessions auf diesem Mac; genauer Wert: /usage)

## Findings
- [Important][code_review] audit/bin/fixtures/mutate/pest-mutate-enum-path.log:1: fixtures embedded third-party client source in a public repo
- [Important][code_review] audit/CLAUDE.md:1: unverified claim that the symlinked-vendor guard does not apply to the enum route
- [Minor][code_review] audit/bin/mutate.sh:63: JSON unwrap did not decode escapes
- [Minor][code_review] audit/bin/mutate.sh:306: enum detection matched any line starting with enum
- [Minor][code_review] audit/bin/mutate.sh:260: runner-died check not JSON-aware
- [Minor][code_review] audit/bin/mutate.test.sh:128: PAO test depended on the caller's environment and used substring matching
- [Minor][code_review] audit/bin/mutate.sh:65: quadratic buffering for plain logs
- [Minor][code_review] audit/bin/mutate.sh:34: header line mixed Pest and Infection descriptions
- [Minor][code_review] audit/bin/mutate.sh:222: PAO_DISABLE exported script-wide

## Fixed
- [Important][code_review] audit/bin/fixtures/mutate/pest-mutate-enum-path.log:1: fixtures anonymized and renamed, history squashed so the original logs never reach the remote
- [Important][code_review] audit/CLAUDE.md:1: both routes need the worktree's own vendor/
- [Minor][code_review] audit/bin/mutate.sh:63: escapes decoded
- [Minor][code_review] audit/bin/mutate.sh:306: anchored on a declaration line, comment case pinned
- [Minor][code_review] audit/bin/mutate.sh:260: reads the unwrapped lines
- [Minor][code_review] audit/bin/mutate.test.sh:128: PAO_DISABLE unset at the top, exact match
- [Minor][code_review] audit/bin/mutate.sh:65: buffering only for JSON
- [Minor][code_review] audit/bin/mutate.sh:34: re-wrapped
- [Minor][code_review] audit/bin/mutate.sh:222: env prefix on the Pest call

## Discarded

## Minor, not fixed

## Not completed

## Open Points
- A class measured by --files runs only the tests matching its basename; tests elsewhere that kill mutants are not counted unless a `::` hint names them (84 vs 93 on one class)
