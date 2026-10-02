#!/usr/bin/env bash
#
# Pins hunk-ranges.sh (2026-10-02): changed ranges of the new file widened by 15 lines and merged, a new
# file is "whole", a deleted or unchanged file is absent.
set -euo pipefail

SCRIPT="$(cd "$(dirname "$0")" && pwd)/hunk-ranges.sh"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
cd "$TMP" && git init -q .
git config user.email t@t; git config user.name t

expect() {
  [[ "$1" == "$2" ]] || { printf 'FAIL %s\nExpected: %s\nGot: %s\n' "$3" "$2" "$1" >&2; exit 1; }
  printf 'PASS %s\n' "$3"
}

seq 1 200 > big.txt
seq 1 10 > small.txt
seq 1 5 > gone.txt
seq 1 5 > same.txt
git add -A; git commit -q -m base

# big.txt: lines 50 and 60 changed (merge into one range), line 150 changed (own range)
sed -i.bak -e '50s/.*/x/' -e '60s/.*/x/' -e '150s/.*/x/' big.txt; rm big.txt.bak
sed -i.bak '1s/.*/x/' small.txt; rm small.txt.bak
git rm -q gone.txt
seq 1 3 > fresh.txt; git add fresh.txt
echo hi > untracked.txt

OUT=$(bash "$SCRIPT" HEAD big.txt small.txt gone.txt same.txt fresh.txt untracked.txt)
expect "$OUT" '{"big.txt":[[35,75],[135,165]],"small.txt":[[1,10]],"fresh.txt":"whole","untracked.txt":"whole"}' 'ranges widened by 15 and merged, new file whole, deleted and unchanged absent'
expect "$(bash "$SCRIPT" HEAD same.txt)" '{}' 'nothing changed prints an empty object'
bash "$SCRIPT" nosuchref big.txt >/dev/null 2>&1 && { echo 'FAIL unknown ref accepted' >&2; exit 1; }
echo 'PASS unknown ref fails'
