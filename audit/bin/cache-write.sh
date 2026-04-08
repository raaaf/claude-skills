#!/usr/bin/env bash
#
# Writes/updates the incremental audit cache. Reads findings JSON from stdin.
#
# Usage:
#   echo '{"files":[...],"findings":[...]}' | bash cache-write.sh
#
# Input JSON:
#   {
#     "files": ["src/foo.ts", "src/bar.php"],
#     "findings": [
#       {"file": "src/foo.ts", "severity": "important", "dimension": "security", "line": 42, "message": "..."}
#     ]
#   }
set -euo pipefail

PROJECT_ROOT=$(git rev-parse --show-toplevel 2>/dev/null) || { echo "NOT_A_REPO"; exit 1; }
CACHE_DIR="$PROJECT_ROOT/.claude/audits"
CACHE_FILE="$CACHE_DIR/cache.json"
mkdir -p "$CACHE_DIR"

command -v jq >/dev/null 2>&1 || { echo "jq not available, cache disabled"; exit 0; }

hash_of() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" | awk '{print $1}'
  else
    shasum -a 256 "$1" | awk '{print $1}'
  fi
}

INPUT=$(cat)
[ -z "$INPUT" ] && exit 0

HEAD=$(git -C "$PROJECT_ROOT" rev-parse --short HEAD 2>/dev/null || echo "unknown")
NOW=$(date +%s)

[ -f "$CACHE_FILE" ] || echo '{"version":1,"entries":{}}' > "$CACHE_FILE"

FILES=$(jq -r '.files[]' <<<"$INPUT")
TMP=$(mktemp)
cp "$CACHE_FILE" "$TMP"

while IFS= read -r file; do
  [ -z "$file" ] && continue
  [ -f "$PROJECT_ROOT/$file" ] || continue
  sha=$(hash_of "$PROJECT_ROOT/$file")
  file_findings=$(jq --arg f "$file" '[.findings[] | select(.file == $f)]' <<<"$INPUT")
  jq --arg f "$file" --arg sha "$sha" --arg head "$HEAD" --argjson ts "$NOW" --argjson fnd "$file_findings" \
    '.entries[$f] = {sha256: $sha, head: $head, timestamp: $ts, findings: $fnd}' \
    "$TMP" > "$TMP.new" && mv "$TMP.new" "$TMP"
done <<<"$FILES"

# Prune entries older than 30 days
CUTOFF=$((NOW - 2592000))
jq --argjson cutoff "$CUTOFF" '.entries |= with_entries(select(.value.timestamp >= $cutoff))' "$TMP" > "$CACHE_FILE"
rm -f "$TMP"

grep -q '.claude/audits/cache.json' "$PROJECT_ROOT/.gitignore" 2>/dev/null || echo '.claude/audits/cache.json' >> "$PROJECT_ROOT/.gitignore"

echo "CACHE_WRITTEN=$CACHE_FILE"
