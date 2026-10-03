#!/usr/bin/env bash
#
# Pins classify-diff.sh --paths (prose gate, /ship's marker-delta check): audit logs, docs and .gitattributes
# alone are prose, a code file next to them makes the delta code.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
cd "$TMP" && git init -q .

class() { printf '%s\n' "$@" | bash "$SCRIPT_DIR/classify-diff.sh" --paths | sed -n 's/^DIFF_CLASS=//p'; }

expect() {
  [[ "$1" == "$2" ]] || { printf 'FAIL %s\nExpected: %s\nGot: %s\n' "$3" "$2" "$1" >&2; exit 1; }
  printf 'PASS %s\n' "$3"
}

expect "$(class .claude/audits/2026-10-03_120000-main.md)" prose 'an audit log alone is prose'
expect "$(class README.md .gitattributes)" prose 'docs plus .gitattributes are prose'
expect "$(class README.md src/a.js)" code 'a code file next to docs stays code'
