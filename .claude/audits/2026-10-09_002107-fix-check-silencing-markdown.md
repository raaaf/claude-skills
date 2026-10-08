# Audit: 2026-10-09: Branch: fix/check-silencing-markdown

## Scope
- Base: 3b09080 | HEAD at audit time: fbcd17a (fixes committed as 9f00047, 93bfce9)
- Changed files: 3 (audit/bin/check-silencing.sh, audit/bin/check-silencing.test.sh, audit/CLAUDE.md) | Diff class: code
- Reviews run: code_review

## Pre-checks
- check-silencing: HITS (10) on the first pass, all in audit/bin/check-silencing.test.sh (planted test data); fixed by excluding the check's own test like its own source
- all others OK/CLEAN/SKIP

## Result
- Gate: passed
- Findings: Critical 0 / Important 3 / Minor 6 | Fixed 8 | Discarded 1 | Open 0
- Tests: check-silencing.test.sh under bash and /bin/bash all PASS, check-silencing.sh on the branch OK, check-docs-claims OK, check-fresh-shell OK. The prose case fails against the pre-fix script (9 hits).
- Kosten dieses Laufs: 6.51 USD (ca. 0.3 % der Woche), Woche ca. 24.6 % (lokale Schätzung über die Sessions auf diesem Mac; genauer Wert: /usage)

## Findings
- [Important][pre-check] audit/bin/check-silencing.test.sh:36: the check reports its own test's planted patterns as silencing hits
- [Important][code_review] audit/bin/check-silencing.sh:152: the docs/ path clause exempted source and test files under any docs directory
- [Important][code_review] audit/bin/check-silencing.sh:143: excluding the test file hides rule 4 for it
- [Minor][code_review] audit/bin/check-silencing.sh:152: prose extensions missed markdown, rst, adoc and uppercase variants
- [Minor][code_review] audit/bin/check-silencing.sh:168: duplicated old_num assignment in the prose branch
- [Minor][code_review] audit/bin/check-silencing.sh:186: repeated !is_prose guards instead of one gate
- [Minor][code_review] audit/bin/check-silencing.test.sh:38: no mixed-diff case and no docs/ source case
- [Minor][code_review] audit/bin/check-silencing.sh:4: header rule list did not mention the prose exemption
- [Minor][code_review] audit/CLAUDE.md:61: test row still described the docs/ exemption

## Fixed
- [Important][pre-check] audit/bin/check-silencing.test.sh:36: skip regex covers check-silencing(.test).sh, same reason as the script itself
- [Important][code_review] audit/bin/check-silencing.sh:152: prose is decided by extension only
- [Minor][code_review] audit/bin/check-silencing.sh:152: md, mdx, markdown, txt, rst, adoc compared on tolower(file)
- [Minor][code_review] audit/bin/check-silencing.sh:168: single assignment
- [Minor][code_review] audit/bin/check-silencing.sh:186: rules 1 to 4 behind one if (!is_prose) gate, rule 5 outside
- [Minor][code_review] audit/bin/check-silencing.test.sh:38: docs/example.test.js must hit, mixed diff must stay OK
- [Minor][code_review] audit/bin/check-silencing.sh:4: header updated, note wrapped
- [Minor][code_review] audit/CLAUDE.md:61: row updated

## Discarded
- [Important][code_review] audit/bin/check-silencing.sh:143: the test's checks are expect_has/expect_ok helpers, which rule 4's pattern never matched, so the exclusion removes no coverage

## Minor, not fixed

## Not completed

## Open Points
