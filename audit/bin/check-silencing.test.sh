#!/usr/bin/env bash
#
# Pins check-silencing.sh: the planted-bug cases still produce their hit, and a
# prose change that merely mentions assertions, skips, suppressions and empty
# catches in Markdown, text or reStructuredText produces none (false positive of 2026-10-08
# on a delegate/SKILL.md line containing "assertion failure").
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

# Fresh repo with one base commit (on main) per case; $1 = case name.
new_repo() {
  rm -rf "$TMP/r" && mkdir "$TMP/r" && cd "$TMP/r"
  git init -q -b main . && git config user.email t@example.com && git config user.name t
}
commit_base() { git add -A && git commit -q -m base; }
run() { AUDIT_BASE_REF=main bash "$SCRIPT_DIR/check-silencing.sh" "$TMP/r" 2>/dev/null; }

expect_has() {
  printf '%s\n' "$1" | grep -q -- "$2" || { printf 'FAIL %s\nExpected output to contain: %s\nGot:\n%s\n' "$3" "$2" "$1" >&2; exit 1; }
  printf 'PASS %s\n' "$3"
}
expect_ok() {
  [[ "$(printf '%s\n' "$1" | tail -n 1)" == "SILENCING_RESULT=OK" ]] || { printf 'FAIL %s\nGot:\n%s\n' "$2" "$1" >&2; exit 1; }
  printf 'PASS %s\n' "$2"
}

# Prose (by extension only): every rule's words in Markdown, text, reStructuredText
# and an uppercase README.MD, plus a removed line that mentions assertions. Must
# stay silent.
new_repo
mkdir docs
printf '%s\n' 'Fails on assertion failure.' 'expect(x) is explained here.' > SKILL.md
printf '%s\n' 'assert the result' > notes.txt
printf '%s\n' 'it.skip(' > docs/guide.md
printf '%s\n' 'expect(x) works' > README.MD
printf '%s\n' 'assert the result' > docs/guide.rst
commit_base
printf '%s\n' 'Reports a skip and an eslint-disable comment.' 'Do not write catch (e) {} or test.skip(.' > SKILL.md
printf '%s\n' 'it.only(' 'markTestSkipped' > notes.txt
printf '%s\n' '# noqa' 'except: pass' > docs/guide.md
printf '%s\n' 'Nothing asserted here, test.skip( mentioned.' > README.MD
printf '%s\n' 'it.skip( and eslint-disable' > docs/guide.rst
expect_ok "$(run)" 'prose that mentions every pattern is OK'

# A docs/ directory does not exempt source or test files.
new_repo
mkdir docs
printf '%s\n' "it('adds', () => {})" > docs/example.test.js
commit_base
printf '%s\n' "it.skip('adds', () => {})" > docs/example.test.js
expect_has "$(run)" 'test-disabled' 'it.skip in docs/example.test.js hits'

# Mixed diff: a .md losing an assertion-like line is ignored, a source test that
# keeps its assertions is fine.
new_repo
printf '%s\n' 'expect(x) is explained here.' > notes.md
printf '%s\n' "it('adds', () => {" '  expect(add(1, 2)).toBe(3)' '})' > a.test.js
commit_base
printf '%s\n' 'Prose without the word.' > notes.md
printf '%s\n' "it('adds', () => {" '  expect(add(1, 2)).toBe(3)' '  expect(add(2, 2)).toBe(4)' '})' > a.test.js
expect_ok "$(run)" 'mixed diff: prose removal plus intact test is OK'

# Planted bugs in source and test files still hit.
new_repo
printf '%s\n' "it('adds', () => {" '  expect(add(1, 2)).toBe(3)' '  expect(add(2, 2)).toBe(4)' '})' > a.test.js
printf '%s\n' 'function f() { return 1 }' > a.js
commit_base
printf '%s\n' "it('adds', () => {" '  add(1, 2)' '})' > a.test.js
expect_has "$(run)" 'assertions-removed' 'assertions removed from a surviving test'

new_repo
printf '%s\n' "it('adds', () => {})" > a.test.js
commit_base
printf '%s\n' "it.skip('adds', () => {})" > a.test.js
expect_has "$(run)" 'test-disabled' 'it.skip added'

new_repo
printf '%s\n' 'function f() { return 1 }' > a.js
commit_base
printf '%s\n' 'function f() { try { g() } catch (e) {} }' > a.js
expect_has "$(run)" 'error-swallowed' 'empty catch added'

new_repo
printf '%s\n' 'const x = 1' > a.js
commit_base
printf '%s\n' '// eslint-disable-next-line' 'const x = 1' > a.js
expect_has "$(run)" 'suppression-added' 'suppression comment added'

# Rule 5 keeps covering CONSTRAINTS.md although it ends in .md.
new_repo
printf '%s\n' 'coverage: 80' > CONSTRAINTS.md
commit_base
printf '%s\n' 'coverage: 60' > CONSTRAINTS.md
expect_has "$(run)" 'threshold-lowered' 'threshold lowered in CONSTRAINTS.md'
