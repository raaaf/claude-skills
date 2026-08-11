#!/usr/bin/env bash
#
# Incremental-Audit-Cache. Reads .claude/audits/cache.json and outputs two
# lists to stdout:
#   CACHED_FILES: files whose content hash matches the cache entry
#   CACHED_FINDINGS: previously-recorded findings for those files
#
# Usage: bash cache-check.sh <file1> <file2> ...
#
# Cache format:
#   {
#     "version": 1,
#     "entries": {
#       "<relpath>": {
#         "sha256": "...",
#         "head": "<short-hash>",
#         "timestamp": 1234567890,
#         "findings": [
#           {"severity": "important", "dimension": "security", "line": 42, "message": "..."}
#         ]
#       }
#     }
#   }
set -euo pipefail

# shellcheck disable=SC1091
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/lib-git-base.sh"

PROJECT_ROOT=$(git rev-parse --show-toplevel 2>/dev/null) || { echo "NOT_A_REPO"; exit 1; }
CACHE_FILE="$PROJECT_ROOT/.claude/audits/cache.json"

empty_output() {
  echo "CACHED_FILES<<END"
  echo "END"
  echo "CACHED_FINDINGS<<END"
  echo "[]"
  echo "END"
}

[ -f "$CACHE_FILE" ] || { empty_output; exit 0; }
command -v jq >/dev/null 2>&1 || { empty_output; exit 0; }
# Corrupt/unparseable cache.json (e.g. a truncated write) must degrade to the
# same empty-output fallback instead of aborting under set -e mid-stream,
# which would break the CACHED_FILES/CACHED_FINDINGS heredoc contract.
jq empty "$CACHE_FILE" >/dev/null 2>&1 || { empty_output; exit 0; }

HITS=""
FINDINGS="[]"

for file in "$@"; do
  [ -f "$PROJECT_ROOT/$file" ] || continue
  current_hash=$(hash_of "$PROJECT_ROOT/$file")
  cached_hash=$(jq -r --arg f "$file" '.entries[$f].sha256 // empty' "$CACHE_FILE")
  if [ -n "$cached_hash" ] && [ "$cached_hash" = "$current_hash" ]; then
    HITS="$HITS$file"$'\n'
    file_findings=$(jq -c --arg f "$file" '.entries[$f].findings // []' "$CACHE_FILE")
    FINDINGS=$(jq -c --argjson add "$file_findings" '. + $add' <<<"$FINDINGS")
  fi
done

echo "CACHED_FILES<<END"
printf '%s' "$HITS"
echo "END"
echo "CACHED_FINDINGS<<END"
echo "$FINDINGS"
echo "END"
