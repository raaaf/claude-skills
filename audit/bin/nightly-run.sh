#!/usr/bin/env bash
#
# Nightly driver (2026-10-01): walks every candidate repo from nightly-repos.sh sequentially. For each
# `ready` repo it creates a detached temporary worktree from origin/<default>, runs a headless
# headless `claude -p` (lib-headless.sh: narrow allow list, NIGHTLY_DONE sentinel, up to 3 resumes) inside it (3 h cap per attempt (NIGHTLY_TIMEOUT_SECS)), removes the worktree, and records one report line.
# Skipped repos are reported with their status and detail. Report: $HOME/.local/state/claude/nightly/YYYY-MM-DD.md
# Usage: nightly-run.sh [--dry-run] [root...]   (--dry-run: list what would run, no worktree, no claude)
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
DRY=0
if [ "${1:-}" = "--dry-run" ]; then DRY=1; shift; fi

TIMEOUT_SECS="${NIGHTLY_TIMEOUT_SECS:-10800}"   # per attempt; one repo runs triage plus one fix wave and PR per backlog group, sequentially
DATE=$(date +%F)
TMPBASE="${TMPDIR:-/tmp}"; TMPBASE="${TMPBASE%/}"
WORK=$(mktemp -d "$TMPBASE/nightly-run.XXXXXX")
trap 'rm -rf "$WORK"' EXIT

. "$SCRIPT_DIR/lib-headless.sh"
PROMPT="Nachtlauf. Gib bei jedem fehlgeschlagenen Schritt (z.B. dem Start von fix.js) den vollständigen Fehlertext aus, unter der Überschrift FEHLER. Gib vor der letzten Zeile die Triage-Zeile TRIAGE: kept=K dropped=D groups=G aus (Backlog-Triage laut references/minor-backlog.md). Gib als allerletzte Zeile NIGHTLY_DONE aus, erst nachdem jeder gestartete Workflow beendet und das Log geschrieben ist."

LIST=$(bash "$SCRIPT_DIR/nightly-repos.sh" "$@")

if [ "$DRY" = 1 ]; then
  printf '%s\n' "$LIST" | while IFS="$(printf '\t')" read -r repo status detail; do
    [ -n "$repo" ] || continue
    if [ "$status" = ready ]; then printf 'WOULD RUN  %s (%s)\n' "$repo" "$detail"
    else printf 'SKIP       %s: %s (%s)\n' "$repo" "$status" "$detail"; fi
  done
  printf 'COMMAND    %s\n' "$(audit_headless_cmdline "$PROMPT")"
  exit 0
fi

# All PRs of tonight's run (space separated): the quality-pass PR, a backlog-only PR and one PR per backlog group.
pr_url() {
  local urls
  urls=$(cd "$1" && gh pr list --state all --limit 100 --json url,headRefName --jq ".[] | select(.headRefName == \"chore/nightly-audit-$DATE\" or .headRefName == \"chore/minor-backlog-$DATE\" or ((.headRefName | startswith(\"chore/backlog-\")) and (.headRefName | endswith(\"-$DATE\")))) | .url" 2>/dev/null | tr '\n' ' ' | sed 's/ $//' || true)
  [ -n "$urls" ] && { printf '%s' "$urls"; return 0; }
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
  audit_headless_run "$wt" "$PROMPT" NIGHTLY_DONE "$out" "$TIMEOUT_SECS"; rc=$?
  url=$(pr_url "$wt" || true)
  full="$REPORT_DIR/$DATE-$name.txt"   # full session text incl. any FEHLER section
  cp "$out" "$full" 2>/dev/null || true
  last=$(grep -v '^[[:space:]]*$' "$out" 2>/dev/null | tail -1 | cut -c1-200)
  notes=""
  triage=$(grep -o 'TRIAGE: kept=[0-9]* dropped=[0-9]* groups=[0-9]*' "$out" 2>/dev/null | tail -1 || true)
  [ -n "$triage" ] && notes=", $triage"
  [ "${HEADLESS_RESUMES:-0}" -gt 0 ] && notes="$notes, ${HEADLESS_RESUMES} resume(s)"
  notes="$notes, details $full"
  if [ "$rc" = 124 ]; then
    printf -- '- %s: timeout after %ss%s%s\n' "$name" "$TIMEOUT_SECS" "${url:+, PR $url}" "$notes" >> "$REPORT"
  elif [ "$rc" = 3 ]; then
    printf -- '- %s: failed (no NIGHTLY_DONE after %s resumes)%s%s: %s\n' "$name" "${HEADLESS_RESUMES:-0}" "${url:+, PR $url}" "$notes" "$last" >> "$REPORT"
  elif [ "$rc" != 0 ]; then
    printf -- '- %s: failed (exit %s)%s: %s\n' "$name" "$rc" "$notes" "$last" >> "$REPORT"
  elif [ -n "$url" ]; then
    printf -- '- %s: PR %s (%s)%s\n' "$name" "$url" "$detail" "$notes" >> "$REPORT"
  else
    printf -- '- %s: no PR (%s)%s: %s\n' "$name" "$detail" "$notes" "$last" >> "$REPORT"
  fi
  git -C "$repo" worktree remove --force "$wt" >/dev/null 2>&1 || rm -rf "$wt"
  git -C "$repo" worktree prune >/dev/null 2>&1 || true
done <<< "$LIST"

printf 'Report: %s\n\n' "$REPORT"
cat "$REPORT"
