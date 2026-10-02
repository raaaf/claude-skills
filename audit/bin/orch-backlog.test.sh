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
STORE="$TMP/.audit/minor-backlog.tsv"

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
expect "$(git check-ignore -q .audit/minor-backlog.tsv && echo ignored || echo tracked)" 'tracked' 'store is not gitignored'
expect "$([ -f .gitignore ] && grep -c 'minor-backlog' .gitignore || echo 0)" '0' 'no .gitignore line written'
orch_backlog_add "$IN" >/dev/null
expect "$(grep -cxF '.audit/minor-backlog.tsv merge=union' .gitattributes)" '1' '.gitattributes union line written once'

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

# pre-push gate dimension spellings (2026-10-02) and the nightly quality pass scope
expect "$(orch_expand_dimensions all)" "security,privacy,architecture" 'all = the three gate dimensions'
expect "$(orch_expand_dimensions all+nightly | tr ',' '\n' | grep -c .)" '13' 'all+nightly = all 13'
expect "$(orch_expand_dimensions all+visual)" "$(orch_expand_dimensions all+nightly)" 'all+visual stays an alias of all+nightly'
expect "$(orch_expand_dimensions all | tr ',' '\n' | grep -cE '^(performance|code_quality|seo|a11y|ux|docs_sync|copy|typography|ui_design|animation)$' || true)" '0' 'all excludes the ten nightly dimensions'
expect "$(orch_expand_dimensions typography,copy)" 'typography,copy' 'explicit list passes through'

mkdir -p .audit
git add -A >/dev/null; git -c user.name=t -c user.email=t@t commit -qm base --date='2020-01-01T00:00:00' >/dev/null
GIT_COMMITTER_DATE='2020-01-01T00:00:00' git -c user.name=t -c user.email=t@t commit -q --amend --no-edit --date='2020-01-01T00:00:00'
printf 'd\n' > src/d.js
git add -A >/dev/null
T3=$(( $(date +%s) - 3*86400 ))
GIT_COMMITTER_DATE="$T3 +0000" git -c user.name=t -c user.email=t@t commit -qm threedays --date="$T3 +0000" >/dev/null
OLD=$(git rev-parse HEAD)
printf 'c\n' > src/c.js
git add -A >/dev/null; git -c user.name=t -c user.email=t@t commit -qm recent >/dev/null
expect "$(orch_visual_pass_files)" 'src/c.js' 'missing head file: only the file from today, the 3-day-old commit is outside the 1-day window'
printf '%s\n' "$OLD" > .audit/visual-pass-head
expect "$(orch_visual_pass_files)" 'src/c.js' 'existing sha: files changed since it'
git rev-parse HEAD > .audit/visual-pass-head
expect "$(orch_visual_pass_files)" '' 'head at HEAD: nothing to do'

# cap (2026-10-02): whole commits, oldest first, head advances only to the last included commit
rm -f .audit/visual-pass-head
n=1; for f in e1 e2 e3; do
  printf '%s\n' "$f" > "src/$f.js"; git add -A >/dev/null
  TS=$(( $(date +%s) - (4-n)*3600 ))
  GIT_COMMITTER_DATE="$TS +0000" git -c user.name=t -c user.email=t@t commit -qm "$f" --date="$TS +0000" >/dev/null
  n=$((n+1))
done
TIP=$(git rev-parse HEAD)
E1=$(git log --format=%H --grep='^e1$' -1)
export AUDIT_VISUAL_PASS_CAP=2
expect "$(orch_visual_pass_files | tr '\n' ' ')" 'src/c.js src/e1.js ' 'night 1, cap 2: oldest whole commits up to the cap'
expect "$(orch_visual_pass_head)" "$E1" 'night 1: head advances only to the last included commit, not the tip'
expect "$(orch_visual_pass_overflow)" '0' 'night 1: nothing capped, the rest is deferred not lost'
printf '%s\n' "$(orch_visual_pass_head)" > .audit/visual-pass-head
expect "$(orch_visual_pass_files | tr '\n' ' ')" 'src/e2.js src/e3.js ' 'night 2: the remainder is picked up'
expect "$(orch_visual_pass_head)" "$TIP" 'night 2: head reaches the tip'
printf '%s\n' "$TIP" > .audit/visual-pass-head
expect "$(orch_visual_pass_files)" '' 'night 3: nothing left'
unset AUDIT_VISUAL_PASS_CAP
rm -f .audit/visual-pass-head
expect "$(orch_visual_pass_overflow)" '0' 'default cap 40: no overflow'

# legacy fallback (2026-10-02): the old .claude/audits/ files are read until the first write, never deleted
rm -f "$STORE" .audit/visual-pass-head
mkdir -p .claude/audits
printf 'k1\tux\tsrc/a.js\t1\t2026-09-30\tlegacy thing\n' > .claude/audits/minor-backlog.tsv
expect "$(orch_backlog_count)" '1' 'legacy store is read when .audit/ has none'
OUT=$(printf 'copy\tsrc/a.js\t2\t2026-10-02\tnew thing\n' > "$IN"; orch_backlog_add "$IN")
expect "$(orch_backlog_count)" '2' 'first write merges the legacy entries into .audit/'
expect "$(grep -c . "$STORE")" '2' 'write lands in .audit/'
expect "$(grep -c . .claude/audits/minor-backlog.tsv)" '1' 'legacy file is left untouched'
expect "$(printf '%s' "$OUT" | grep -c BACKLOG_LEGACY_FILE)" '1' 'write reports that the legacy file can be deleted'
orch_backlog_remove "$(orch_backlog_for_files 'src/a.js' | cut -f1)" >/dev/null
expect "$(orch_backlog_count)" '0' 'emptied .audit/ store shadows the legacy file'
rm -f "$STORE"; rm -f .claude/audits/minor-backlog.tsv
printf '%s\n' "$OLD" > .claude/audits/visual-pass-head
expect "$(orch_visual_pass_files | tr '\n' ' ')" 'src/c.js src/e1.js src/e2.js src/e3.js ' 'legacy visual-pass-head is the fallback' 

# one commit above the cap is taken alone with capped files, reported; head moves to it
rm -f .audit/visual-pass-head .claude/audits/visual-pass-head
printf '%s\n' "$TIP" > .audit/visual-pass-head
for f in b1 b2 b3; do printf '%s\n' "$f" > "src/$f.js"; done
git add -A >/dev/null; git -c user.name=t -c user.email=t@t commit -qm big >/dev/null
BIG=$(git rev-parse HEAD)
printf 'z\n' > src/z.js; git add -A >/dev/null; git -c user.name=t -c user.email=t@t commit -qm after >/dev/null
export AUDIT_VISUAL_PASS_CAP=2
expect "$(orch_visual_pass_files | tr '\n' ' ')" 'src/b1.js src/b2.js ' 'large single commit: taken alone, capped to the cap'
expect "$(orch_visual_pass_overflow)" '1' 'large single commit: capped files are reported'
expect "$(orch_visual_pass_head)" "$BIG" 'large single commit: head moves to it, the next commit is left for the next night'
unset AUDIT_VISUAL_PASS_CAP
