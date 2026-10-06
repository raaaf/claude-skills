#!/usr/bin/env bash
#
# Prints the tree id of the working tree in the current directory, untracked non-ignored files
# included. Single implementation shared by orch_tree_hash (lib-orchestrator.sh) and the push guard
# (hooks/block-unsafe-push.sh), so the marker and the guard always compute the same hash.
# The tree is built in a temp copy of the real index; the real index and working tree stay
# untouched and the temp index is always removed. Non-zero exit when git fails.
idx=$(git rev-parse --git-path index 2>/dev/null) || exit 1
tmp=$(mktemp "${TMPDIR:-/tmp}/orch-tree-index.XXXXXX") || exit 1
trap 'rm -f "$tmp"' EXIT
if [ -s "$idx" ]; then
  cp "$idx" "$tmp" || exit 1
else
  rm -f "$tmp"   # an empty file is no valid index; git creates it on add
fi
GIT_INDEX_FILE="$tmp" git add -A >/dev/null 2>&1 || exit 1
GIT_INDEX_FILE="$tmp" git write-tree 2>/dev/null
