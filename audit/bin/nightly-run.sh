#!/usr/bin/env bash
#
# Nightly driver (2026-10-01): walks every candidate repo from nightly-repos.sh sequentially. For each
# `ready` repo it creates a detached temporary worktree from origin/<default>, runs a headless
# `claude -p "Nachtlauf"` inside it (45 min cap), removes the worktree, and records one report line.
# Skipped repos are reported with their status and detail. Report: $HOME/.local/state/claude/nightly/YYYY-MM-DD.md
# Usage: nightly-run.sh [--dry-run] [root...]   (--dry-run: list what would run, no worktree, no claude)
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
DRY=0
if [ "${1:-}" = "--dry-run" ]; then DRY=1; shift; fi

TIMEOUT_SECS="${NIGHTLY_TIMEOUT_SECS:-2700}"
DATE=$(date +%F)
TMPBASE="${TMPDIR:-/tmp}"; TMPBASE="${TMPBASE%/}"
WORK=$(mktemp -d "$TMPBASE/nightly-run.XXXXXX")
trap 'rm -rf "$WORK"' EXIT

LIST=$(bash "$SCRIPT_DIR/nightly-repos.sh" "$@")

if [ "$DRY" = 1 ]; then
  printf '%s\n' "$LIST" | while IFS="$(printf '\t')" read -r repo status detail; do
    [ -n "$repo" ] || continue
    if [ "$status" = ready ]; then printf 'WOULD RUN  %s (%s)\n' "$repo" "$detail"
    else printf 'SKIP       %s: %s (%s)\n' "$repo" "$status" "$detail"; fi
  done
  exit 0
fi

# run_claude <worktree> <outfile>: 0 = finished ok, 124 = timed out, else the claude exit code
run_claude() {
  local pid waited=0 rc
  ( cd "$1" && exec claude -p "Nachtlauf" --permission-mode acceptEdits ) > "$2" 2>&1 < /dev/null &
  pid=$!
  while kill -0 "$pid" 2>/dev/null; do
    if [ "$waited" -ge "$TIMEOUT_SECS" ]; then
      pkill -TERM -P "$pid" 2>/dev/null; kill -TERM "$pid" 2>/dev/null
      sleep 2; pkill -KILL -P "$pid" 2>/dev/null; kill -KILL "$pid" 2>/dev/null
      wait "$pid" 2>/dev/null
      return 124
    fi
    sleep 5; waited=$((waited + 5))
  done
  wait "$pid"; rc=$?
  return "$rc"
}

pr_url() {
  local b url
  for b in "chore/nightly-audit-$DATE" "chore/minor-backlog-$DATE"; do
    url=$(cd "$1" && gh pr list --head "$b" --state all --json url --jq '.[0].url // empty' 2>/dev/null || true)
    [ -n "$url" ] && { printf '%s' "$url"; return 0; }
  done
  return 1
}

REPORT_DIR="$HOME/.local/state/claude/nightly"
mkdir -p "$REPORT_DIR"
REPORT="$REPORT_DIR/$DATE.md"
printf '# Nightly audit %s\n\n' "$DATE" > "$REPORT"

while IFS="$(printf '\t')" read -r repo status detail; do
  [ -n "$repo" ] || continue
  name=$(basename "$repo")
  if [ "$status" != ready ]; then
    printf -- '- %s: %s (%s)\n' "$name" "$status" "$detail" >> "$REPORT"; continue
  fi
  def=$(git -C "$repo" symbolic-ref --quiet --short refs/remotes/origin/HEAD 2>/dev/null | sed 's#^origin/##' || true)
  [ -n "$def" ] || def=main
  wt="$WORK/$name"
  if ! git -C "$repo" worktree add -q --detach "$wt" "origin/$def" >/dev/null 2>&1; then
    printf -- '- %s: failed (worktree creation from origin/%s)\n' "$name" "$def" >> "$REPORT"; continue
  fi
  out="$WORK/$name.out"
  case "$detail" in
    *"visual_files="*"(cap "*)
      detail="$detail, Qualitätslauf über dem Limit: der Rest folgt in den nächsten Nächten" ;;
  esac
  run_claude "$wt" "$out"; rc=$?
  url=$(pr_url "$wt" || true)
  last=$(grep -v '^[[:space:]]*$' "$out" 2>/dev/null | tail -1 | cut -c1-200)
  if [ "$rc" = 124 ]; then
    printf -- '- %s: timeout after %ss%s\n' "$name" "$TIMEOUT_SECS" "${url:+, PR $url}" >> "$REPORT"
  elif [ "$rc" != 0 ]; then
    printf -- '- %s: failed (exit %s): %s\n' "$name" "$rc" "$last" >> "$REPORT"
  elif [ -n "$url" ]; then
    printf -- '- %s: PR %s (%s)\n' "$name" "$url" "$detail" >> "$REPORT"
  else
    printf -- '- %s: no PR (%s): %s\n' "$name" "$detail" "$last" >> "$REPORT"
  fi
  git -C "$repo" worktree remove --force "$wt" >/dev/null 2>&1 || rm -rf "$wt"
  git -C "$repo" worktree prune >/dev/null 2>&1 || true
done <<< "$LIST"

printf 'Report: %s\n\n' "$REPORT"
cat "$REPORT"
