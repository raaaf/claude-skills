#!/usr/bin/env bash
#
# hunk-ranges.sh <base-ref> <file...>
# Prints one JSON object {"<path>": [[start,end],...] | "whole"} of the changed line ranges in the NEW
# (working tree) file versus <base-ref>, each widened by 15 lines of context, clamped to the file and
# merged. A file that is new in the diff (or untracked) is "whole"; a deleted or unchanged file is absent.
# Why (2026-10-02): the specialists (ui-ux-reviewer, code-reviewer) only have Read/Grep/Glob and could not
# run the `git diff` the hunk-scope briefing told them to; the orchestrator computes the ranges here and
# find.js (args.hunks) puts them into the briefing. bash 3.2 compatible.
set -uo pipefail

[ "$#" -ge 1 ] || { echo "usage: hunk-ranges.sh <base-ref> <file...>" >&2; exit 2; }
BASE="$1"; shift
git rev-parse --verify -q "$BASE^{commit}" >/dev/null 2>&1 || { echo "hunk-ranges.sh: unknown base ref: $BASE" >&2; exit 2; }
CTX=15

json_str() { printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'; }

out=""
for f in "$@"; do
  [ -f "$f" ] || continue
  d=$(git -c core.quotepath=off diff -U0 --no-color --no-ext-diff "$BASE" -- "$f" 2>/dev/null || true)
  if [ -z "$d" ]; then
    # not in the diff: untracked files are new, so whole; tracked and unchanged files are absent
    git ls-files --error-unmatch -- "$f" >/dev/null 2>&1 && continue
    val='"whole"'
  elif printf '%s\n' "$d" | grep -q '^--- /dev/null'; then
    val='"whole"'
  else
    total=$(awk 'END { print NR }' "$f")
    val=$(printf '%s\n' "$d" | awk -v ctx="$CTX" -v total="$total" '
      function flush() { if (have) { printf "%s[%d,%d]", (n++ ? "," : ""), ps, pe } have = 0 }
      /^@@ / {
        h = $3; sub(/^\+/, "", h)
        split(h, p, ",")
        c = p[1] + 0; l = (p[2] == "" ? 1 : p[2] + 0)
        if (l == 0) l = 1
        s = c - ctx; if (s < 1) s = 1
        e = c + l - 1 + ctx; if (total > 0 && e > total) e = total
        if (have && s <= pe + 1) { if (e > pe) pe = e }
        else { flush(); ps = s; pe = e; have = 1 }
      }
      END { flush() }' )
    [ -n "$val" ] || continue
    val="[$val]"
  fi
  out="$out${out:+,}\"$(json_str "$f")\":$val"
done
printf '{%s}\n' "$out"
