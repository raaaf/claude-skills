#!/usr/bin/env bash
#
# Checks .github/workflows/*.yml for two supply-chain hardening gaps:
#   1. `uses:` pinned to a mutable tag/branch (e.g. @v4, @main) instead of a
#      40-character commit SHA.
#   2. No `permissions:` block, at the top level or on every job.
#
# Usage: bash check-ci-hardening.sh [root]
#
# Output: one line per hit, `CI_HARDENING_HIT <file>:<line> <reason>`, then
# exactly one `CI_HARDENING_RESULT=OK|HITS (N)|SKIP (reason)` line.
#
# Called from Phase 0 pre-checks; hits become Important security findings in
# the log directly, without a specialist dispatch.
#
# bash 3.2 compatible (no declare -A, no readarray). No jq needed (plain
# grep/awk over YAML), keeps this usable even when jq is missing.
set -euo pipefail

ROOT="${1:-.}"
WORKFLOWS_DIR="$ROOT/.github/workflows"

if [ ! -d "$WORKFLOWS_DIR" ]; then
  echo "CI_HARDENING_RESULT=SKIP (no .github/workflows directory)"
  exit 0
fi

HIT_COUNT=0

# Collect workflow files (bash 3.2: plain indexed array).
FILES=()
while IFS= read -r f; do
  [ -n "$f" ] || continue
  FILES+=("$f")
done < <(find "$WORKFLOWS_DIR" -maxdepth 1 -type f \( -name "*.yml" -o -name "*.yaml" \) 2>/dev/null | sort)

if [ "${#FILES[@]}" -eq 0 ]; then
  echo "CI_HARDENING_RESULT=SKIP (no workflow files under $WORKFLOWS_DIR)"
  exit 0
fi

for f in "${FILES[@]}"; do
  # --- Check 1: uses: pinned to a tag/branch instead of a 40-char SHA. ---
  # Matches `uses: owner/repo@ref` (optionally quoted, arbitrary indent).
  # A ref is "safe" only if it is exactly 40 hex characters (a full commit
  # SHA); anything else (vX, vX.Y.Z, main, a short SHA) is a hit. Local
  # actions (`uses: ./local-action`) and docker refs (`uses: docker://...`)
  # are excluded — they have no tag/SHA distinction to pin.
  while IFS=: read -r lineno content; do
    [ -n "$lineno" ] || continue
    ref=$(printf '%s' "$content" | sed -nE 's/.*uses:[[:space:]]*["'"'"']?[^@[:space:]]+@([^"'"'"'[:space:]]+).*/\1/p')
    [ -n "$ref" ] || continue
    case "$ref" in
      [0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F])
        # 40 hex chars, treat as a real SHA. No hit.
        ;;
      *)
        echo "CI_HARDENING_HIT $f:$lineno uses pinned to tag/branch '$ref', not a 40-char commit SHA"
        HIT_COUNT=$((HIT_COUNT + 1))
        ;;
    esac
  done < <(grep -nE '^\s*(-\s*)?uses:\s*["'"'"']?[^./][^[:space:]]*@' "$f" 2>/dev/null | grep -vE 'uses:\s*["'"'"']?(\./|docker://)')

  # --- Check 2: missing permissions: block, top-level or per-job. ---
  # A top-level `permissions:` (column 0) covers the whole workflow. Without
  # one, every job needs its own `permissions:` nested under it — the
  # default GITHUB_TOKEN grant otherwise stays read-write on every job.
  if grep -qE '^permissions:' "$f" 2>/dev/null; then
    continue
  fi
  # No top-level block: every job block (`^  <name>:` under `^jobs:`) needs
  # its own nested `permissions:` before the next job starts.
  JOB_LINES=$(awk '
    /^jobs:/ { injobs=1; next }
    injobs && /^[a-zA-Z0-9_-]+:/ { injobs=0 }
    injobs && /^  [a-zA-Z0-9_.-]+:/ { print NR }
  ' "$f")
  if [ -z "$JOB_LINES" ]; then
    echo "CI_HARDENING_HIT $f:1 no top-level permissions: block and no jobs: block found"
    HIT_COUNT=$((HIT_COUNT + 1))
    continue
  fi
  TOTAL_LINES=$(wc -l < "$f" | tr -d ' ')
  PREV=""
  # Append a sentinel so the last job's window extends to EOF.
  for jline in $JOB_LINES $((TOTAL_LINES + 1)); do
    if [ -n "$PREV" ]; then
      WINDOW=$(sed -n "${PREV},$((jline - 1))p" "$f")
      if ! printf '%s\n' "$WINDOW" | grep -qE '^\s+permissions:'; then
        JOB_NAME=$(sed -n "${PREV}p" "$f" | sed -E 's/^[[:space:]]*([a-zA-Z0-9_.-]+):.*/\1/')
        echo "CI_HARDENING_HIT $f:$PREV job '$JOB_NAME' has no permissions: block and no top-level default"
        HIT_COUNT=$((HIT_COUNT + 1))
      fi
    fi
    PREV="$jline"
  done
done

if [ "$HIT_COUNT" -gt 0 ]; then
  echo "CI_HARDENING_RESULT=HITS ($HIT_COUNT)"
else
  echo "CI_HARDENING_RESULT=OK"
fi
