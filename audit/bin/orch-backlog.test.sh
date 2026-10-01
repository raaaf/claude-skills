#!/usr/bin/env bash
#
# Pins the Minor backlog store (2026-10-01): dedupe by semantic key, missing files dropped on every
# write, lookup by file, removal by key, count, one-line sanitized descriptions, tracked store (no .gitignore line, union merge attribute), sorted output, oldest-n.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
. "$SCRIPT_DIR/lib-orchestrator.sh"

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
cd "$TMP"
git init -q .
mkdir -p src
printf 'a\n' > src/a.js
printf 'b\n' > src/b.js
STORE="$TMP/.claude/audits/minor-backlog.tsv"

expect() {
  local got="$1" expected="$2" label="$3"
  [[ "$got" == "$expected" ]] || {
    printf 'FAIL %s\nExpected: %s\nGot: %s\n' "$label" "$expected" "$got" >&2
    exit 1
  }
  printf 'PASS %s\n' "$label"
}

IN=$(mktemp)
printf 'code_quality\tsrc/a.js\t12\t2026-10-01\tUnused import left in the module\n' > "$IN"
printf 'copy\tsrc/b.js\t3\t2026-10-01\tButton label inconsistent\n' >> "$IN"
orch_backlog_add "$IN" >/dev/null
expect "$(orch_backlog_count)" '2' 'two entries stored'
expect "$(awk -F'\t' '{print NF}' "$STORE" | sort -u)" '6' 'six tab-separated columns'

printf 'code_quality\tsrc/a.js\t99\t2026-10-05\tunused import left in the module.\n' > "$IN"
orch_backlog_add "$IN" >/dev/null
expect "$(orch_backlog_count)" '2' 'reworded repeat of the same finding is deduped by key'
expect "$(orch_backlog_for_files 'src/a.js' | cut -f4,5)" $'12\t2026-10-01' 'dedupe keeps the first entry (first_seen)'

expect "$(orch_backlog_for_files 'src/b.js' | cut -f3)" 'src/b.js' 'lookup returns only the requested file'
expect "$(orch_backlog_for_files 'src/zzz.js')" '' 'lookup for an unknown file is empty'

printf 'copy\tsrc/missing.js\t1\t2026-10-01\tentry for a file that does not exist\n' > "$IN"
orch_backlog_add "$IN" >/dev/null
expect "$(orch_backlog_count)" '2' 'entry for a missing file is not stored'

printf 'security\tsrc/a.js\t1\t2026-10-01\tline one\twith tab\n' > "$IN"
orch_backlog_add "$IN" >/dev/null
expect "$(orch_backlog_for_files 'src/a.js' | grep 'with tab' | cut -f6)" 'line one with tab' 'tabs in the description become spaces'
expect "$(awk -F'\t' '{print NF}' "$STORE" | sort -u)" '6' 'still six columns after a tab in the description'

rm src/b.js
printf 'ux\tsrc/a.js\t5\t2026-10-01\tanother thing\n' > "$IN"
orch_backlog_add "$IN" >/dev/null
expect "$(cut -f3 "$STORE" | sort -u)" 'src/a.js' 'a file deleted since the last write loses its entries on the next write'

KEY=$(orch_backlog_for_files 'src/a.js' | cut -f1 | head -1)
orch_backlog_remove "$KEY" >/dev/null
expect "$(orch_backlog_count)" '2' 'remove drops exactly the named key'
orch_backlog_remove "$(orch_backlog_for_files 'src/a.js' | cut -f1)" >/dev/null
expect "$(orch_backlog_count)" '0' 'removing every key empties the store'
[ ! -f "$STORE" ] && printf 'PASS empty store file removed\n'

printf 'copy\tsrc/a.js\t1\t2026-10-01\tgitignore probe\n' > "$IN"
orch_backlog_add "$IN" >/dev/null
expect "$(orch_backlog_for_files $'src/a.js\nsrc/other.js' | wc -l | tr -d ' ')" '1' 'lookup takes a multi-line file list'
expect "$(git check-ignore -q .claude/audits/minor-backlog.tsv && echo ignored || echo tracked)" 'tracked' 'store is not gitignored'
expect "$([ -f .gitignore ] && grep -c 'minor-backlog' .gitignore || echo 0)" '0' 'no .gitignore line written'
orch_backlog_add "$IN" >/dev/null
expect "$(grep -cxF '.claude/audits/minor-backlog.tsv merge=union' .gitattributes)" '1' '.gitattributes union line written once'

# a legacy ignore line is removed, other lines stay
printf 'node_modules\n.claude/audits/minor-backlog.tsv\ndist\n' > .gitignore
orch_backlog_add "$IN" >/dev/null
expect "$(tr '\n' ',' < .gitignore)" 'node_modules,dist,' 'legacy ignore line removed, others kept'

# sorted by key, oldest-n by first_seen then key
rm -f "$STORE"
printf 'ux\tsrc/a.js\t1\t2026-10-03\tzeta thing\n' > "$IN"
printf 'ux\tsrc/a.js\t2\t2026-10-01\talpha thing\n' >> "$IN"
printf 'ux\tsrc/a.js\t3\t2026-10-01\tbeta thing\n' >> "$IN"
printf 'ux\tsrc/a.js\t4\t2026-10-02\tgamma thing\n' >> "$IN"
orch_backlog_add "$IN" >/dev/null
expect "$(cut -f1 "$STORE" | LC_ALL=C sort -c && echo sorted)" 'sorted' 'store is sorted by key'
expect "$(orch_backlog_oldest 3 | cut -f6 | tr '\n' ',')" 'alpha thing,beta thing,gamma thing,' 'oldest 3 by first_seen then key'
expect "$(orch_backlog_oldest 0)" '' 'oldest 0 prints nothing'
