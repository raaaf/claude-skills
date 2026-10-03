#!/usr/bin/env bash
#
# Pins classify-diff.sh --paths for the tracked Minor backlog (2026-10-01): a delta that only touches
# the backlog TSV and/or .gitattributes is prose, so /ship's marker-delta check accepts it and it
# never triggers a full audit. A code file next to it still makes the delta code.
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

expect "$(class .claude/audits/minor-backlog.tsv)" prose 'backlog tsv alone is prose'
expect "$(class .claude/audits/minor-backlog.tsv .gitattributes)" prose 'backlog tsv plus .gitattributes is prose'
expect "$(class .claude/audits/minor-backlog.tsv src/a.js)" code 'a code file next to the tsv stays code'
expect "$(class .audit/minor-backlog.tsv)" prose 'new-path backlog tsv alone is prose'
expect "$(class .audit/minor-backlog.tsv .gitattributes)" prose 'new-path tsv and .gitattributes are prose'
expect "$(class .audit/minor-backlog.tsv src/a.js)" code 'a code file next to the new-path tsv stays code'
