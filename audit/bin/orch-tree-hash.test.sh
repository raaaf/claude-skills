#!/usr/bin/env bash
#
# Pins orch_tree_hash (2026-10-06): the passed marker must certify untracked, non-ignored files,
# otherwise a brand-new reviewed file reads as a code delta once the user commits it.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
. "$SCRIPT_DIR/lib-orchestrator.sh"

fail() { printf 'FAIL %s\n' "$1" >&2; exit 1; }

T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
cd "$T"
git init -q .
git config user.email t@example.invalid; git config user.name t
printf 'a\n' > a.txt; printf 'ignored.log\n' > .gitignore
git add -A; git commit -q -m init

printf 'new\n' > new.txt
before=$(orch_tree_hash)
[ "$before" != "$(git rev-parse 'HEAD^{tree}')" ] || fail 'untracked file not in hash'
printf 'x\n' > ignored.log
[ "$(orch_tree_hash)" = "$before" ] || fail 'ignored file changed the hash'
git status --porcelain | grep -q '^?? new.txt' || fail 'real index was modified'
printf 'PASS untracked included, ignored excluded, index untouched\n'

git add -A; git commit -q -m add
[ "$(orch_tree_hash)" = "$before" ] || fail 'hash differs after commit'
printf 'PASS hash stable across commit\n'
