#!/usr/bin/env bash
#
# Pins orch_audited_record / orch_audited_filter: a file is skipped only when its working-tree
# blob is byte-identical to what a passed audit recorded AND the recorded dimensions cover the
# requested ones (2026-09-30: re-audits of unchanged files were 37% of audit-find cost).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
. "$SCRIPT_DIR/lib-orchestrator.sh"

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
cd "$TMP"
git init -q .
RECORD="$(orch__audited_path)"

fresh() { rm -f "$RECORD"; printf 'one\n' > a.txt; printf 'two\n' > b.txt; }

expect() {
  local got="$1" expected="$2" label="$3"
  [[ "$got" == "$expected" ]] || {
    printf 'FAIL %s\nExpected: %s\nGot: %s\n' "$label" "$expected" "$got" >&2
    exit 1
  }
  printf 'PASS %s\n' "$label"
}

fresh
orch_audited_record $'a.txt\nb.txt' 'security,copy'
expect "$(orch_audited_filter $'a.txt\nb.txt' 'copy,security')" '' 'unchanged + superset dims: skipped'
expect "$(orch_audited_filter $'a.txt\nb.txt' 'copy')" '' 'unchanged + recorded dims a strict superset: skipped'

fresh
orch_audited_record 'a.txt' 'copy'
expect "$(orch_audited_filter $'a.txt\nb.txt' 'copy,security')" $'a.txt\nb.txt' 'recorded dims a subset: kept'

fresh
orch_audited_record $'a.txt\nb.txt' 'copy'
printf 'changed\n' > a.txt
expect "$(orch_audited_filter $'a.txt\nb.txt' 'copy')" 'a.txt' 'content changed: kept'

fresh
orch_audited_record $'a.txt\nb.txt' 'copy'
rm b.txt
expect "$(orch_audited_filter $'a.txt\nb.txt' 'copy')" 'b.txt' 'file deleted: kept'

fresh
orch_audited_record 'a.txt' 'copy'
printf 'changed\n' > a.txt
orch_audited_record 'a.txt' 'copy'
expect "$(grep -c '^a.txt' "$RECORD")" '1' 're-record leaves one line per path'
expect "$(orch_audited_filter 'a.txt' 'copy')" '' 're-record certifies the new content'

fresh
orch_audited_record $'a.txt\nb.txt' 'copy'
rm b.txt
orch_audited_record 'b.txt' 'copy'
expect "$(grep -c '^b.txt' "$RECORD" || true)" '0' 'recording a deleted path removes its line'
expect "$(grep -c '^a.txt' "$RECORD")" '1' 'other lines untouched'

fresh
expect "$(orch_audited_filter $'a.txt\nb.txt' 'copy')" $'a.txt\nb.txt' 'no record file: everything kept'
