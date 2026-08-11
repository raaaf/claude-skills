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

# shellcheck disable=SC1091
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/lib-git-base.sh"

PROJECT_ROOT=$(git rev-parse --show-toplevel 2>/dev/null) || { echo "NOT_A_REPO"; exit 1; }
CACHE_DIR="$PROJECT_ROOT/.claude/audits"
CACHE_FILE="$CACHE_DIR/cache.json"
mkdir -p "$CACHE_DIR"

command -v jq >/dev/null 2>&1 || { echo "jq not available, cache disabled"; exit 0; }

INPUT=$(cat)
[ -z "$INPUT" ] && exit 0

HEAD=$(git -C "$PROJECT_ROOT" rev-parse --short HEAD 2>/dev/null || echo "unknown")
NOW=$(date +%s)

[ -f "$CACHE_FILE" ] || echo '{"version":1,"entries":{}}' > "$CACHE_FILE"

FILES=$(jq -r '.files[]' <<<"$INPUT")
TMP=$(mktemp "${TMPDIR:-/tmp}/cache-write.XXXXXX")
trap 'rm -f "$TMP" "${TMP}.new"' EXIT

cp "$CACHE_FILE" "$TMP"

while IFS= read -r file; do
  [ -z "$file" ] && continue
  [ -f "$PROJECT_ROOT/$file" ] || continue
  sha=$(hash_of "$PROJECT_ROOT/$file")
  file_findings=$(jq --arg f "$file" '[.findings[] | select(.file == $f)]' <<<"$INPUT")
  jq --arg f "$file" --arg sha "$sha" --arg head "$HEAD" --argjson ts "$NOW" --argjson fnd "$file_findings" \
    '.entries[$f] = {sha256: $sha, head: $head, timestamp: $ts, findings: $fnd}' \
    "$TMP" > "${TMP}.new" && mv "${TMP}.new" "$TMP"
done <<<"$FILES"

# Prune entries older than 30 days. Write to a temp file first and mv it
# into place, same pattern as the per-file loop above: a direct redirect
# into CACHE_FILE would truncate it non-atomically on a jq failure/interrupt.
CUTOFF=$((NOW - 2592000))
jq --argjson cutoff "$CUTOFF" '.entries |= with_entries(select(.value.timestamp >= $cutoff))' "$TMP" > "${TMP}.new" && mv "${TMP}.new" "$CACHE_FILE"

# Only touch .gitignore when it would actually change something: skip if the
# path is already tracked (a .gitignore entry cannot un-track it, so adding
# one would be a no-op mutation with a misleading effect) or already covered
# by an existing ignore rule (grep only matched the literal line before, so a
# broader pattern like ".claude/audits/" still got a redundant duplicate
# appended). Any mutation that does happen is announced on stdout so it shows
# up in the audit log instead of being a silent side effect on a file the
# audit run does not own.
GITIGNORE_REL='.claude/audits/cache.json'
# A symlinked .gitignore is never written to: ">>" follows the symlink and
# would append outside the repo, and git itself ignores a symlinked
# .gitignore (check-ignore never reports it as covering anything), so the
# else branch below would otherwise re-append on every single run
# (reproduced: three runs against a symlinked .gitignore produced three
# appended lines in the link target). -L checks the link itself, no
# dereference.
if [ -L "$PROJECT_ROOT/.gitignore" ]; then
  echo "NOTE: $PROJECT_ROOT/.gitignore is a symlink; refusing to follow it. Not touching it -- add '$GITIGNORE_REL' to it manually if needed."
elif git -C "$PROJECT_ROOT" ls-files --error-unmatch "$GITIGNORE_REL" >/dev/null 2>&1; then
  echo "NOTE: $GITIGNORE_REL is tracked by git; .gitignore cannot exclude it. Run 'git rm --cached $GITIGNORE_REL' if that was not intended."
elif git -C "$PROJECT_ROOT" check-ignore -q "$GITIGNORE_REL" 2>/dev/null; then
  echo "$GITIGNORE_REL already ignored, .gitignore left unchanged"
else
  printf '\n%s\n' "$GITIGNORE_REL" >> "$PROJECT_ROOT/.gitignore"
  echo "Added $GITIGNORE_REL to .gitignore (was not previously ignored)"
fi

echo "CACHE_WRITTEN=$CACHE_FILE"
