#!/usr/bin/env bash
#
# Candidate repos for the nightly run (2026-10-01). One TSV line per repo: path<TAB>status<TAB>detail.
#   ready          backlog=N visual_files=M[ (cap C) when above the cap] (sorted first, backlog size desc)
#   skip-dirty     the default branch has unpushed local commits ahead of origin
#   skip-open-pr   an open PR from a chore/nightly-audit-* or chore/minor-backlog-* branch (detail: number)
#   skip-no-gh     gh missing or unauthenticated
#   nothing        backlog 0 and no visual-pass files
# Backlog and visual files are read from origin/<default> (after a quiet fetch), never the working tree.
# Usage: nightly-repos.sh [root...]   (default roots: $HOME/Developer, "$HOME/Local Sites")
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
. "$SCRIPT_DIR/lib-orchestrator.sh"

if [ "$#" -gt 0 ]; then ROOTS=("$@"); else ROOTS=("$HOME/Developer" "$HOME/Local Sites"); fi

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
: > "$TMP/cands"

# Candidates: <common-dir><TAB><is-main 1|0><TAB><path>
for root in "${ROOTS[@]}"; do
  [ -d "$root" ] || continue
  find "$root" -maxdepth 4 \( -name node_modules -o -name vendor -o -name Pods -o -name .build \) -prune -o -name .git -print 2>/dev/null |
  while IFS= read -r g; do
    dir=$(dirname "$g")
    [ -d "$dir/.claude/audits" ] || [ -d "$dir/.audit" ] || continue
    url=$(git -C "$dir" config --get remote.origin.url 2>/dev/null || true)
    case "$url" in *github.com*) ;; *) continue ;; esac
    common=$(git -C "$dir" rev-parse --git-common-dir 2>/dev/null) || continue
    common=$(cd "$dir" && cd "$common" && pwd -P) || continue
    main=0; [ -d "$g" ] && main=1
    printf '%s\t%s\t%s\n' "$common" "$main" "$dir"
  done >> "$TMP/cands"
done

# Dedupe by common dir, preferring the main checkout.
sort -t "$(printf '\t')" -k1,1 -k2,2nr "$TMP/cands" | awk -F'\t' '!seen[$1]++ { print $3 }' | sort > "$TMP/repos"

# Optional allowlist (2026-10-02, user decision: nightly runs only on production systems). One repo
# path per line, `~` allowed, `#` comments. When the file exists, every other repo is dropped silently.
ALLOW_FILE="${NIGHTLY_ALLOW_FILE:-$HOME/.claude/nightly-repos.allow}"
if [ -f "$ALLOW_FILE" ]; then
  sed -e 's/#.*//' -e 's/[[:space:]]*$//' -e "s#^~#$HOME#" "$ALLOW_FILE" | grep . |
    while IFS= read -r a; do [ -d "$a" ] && (cd "$a" && pwd -P); done | sort -u > "$TMP/allow"
  while IFS= read -r r; do
    grep -qxF "$(cd "$r" && pwd -P)" "$TMP/allow" && printf '%s\n' "$r"
  done < "$TMP/repos" > "$TMP/repos.allowed"
  mv "$TMP/repos.allowed" "$TMP/repos"
fi

gh_ok=0
if command -v gh >/dev/null 2>&1 && gh auth status >/dev/null 2>&1; then gh_ok=1; fi

: > "$TMP/ready"; : > "$TMP/rest"
while IFS= read -r repo; do
  [ -n "$repo" ] || continue
  git -C "$repo" fetch -q origin >/dev/null 2>&1 || true
  def=$(git -C "$repo" symbolic-ref --quiet --short refs/remotes/origin/HEAD 2>/dev/null | sed 's#^origin/##' || true)
  # A dangling origin/HEAD (points at a branch that no longer exists) is treated as unset.
  if [ -n "$def" ] && ! git -C "$repo" rev-parse --verify -q "refs/remotes/origin/$def" >/dev/null 2>&1; then def=""; fi
  if [ -z "$def" ]; then
    for c in main master; do git -C "$repo" rev-parse --verify -q "refs/remotes/origin/$c" >/dev/null 2>&1 && { def="$c"; break; }; done
  fi
  if [ -z "$def" ]; then printf '%s\tnothing\tno origin default branch\n' "$repo" >> "$TMP/rest"; continue; fi

  ahead=0
  if git -C "$repo" rev-parse --verify -q "refs/heads/$def" >/dev/null 2>&1; then
    ahead=$(git -C "$repo" rev-list --count "origin/$def..$def" -- 2>/dev/null || echo 0)
  fi
  if [ "$ahead" -gt 0 ]; then
    printf '%s\tskip-dirty\t%s has %s unpushed local commits\n' "$repo" "$def" "$ahead" >> "$TMP/rest"; continue
  fi

  # new path first (.audit/), legacy .claude/audits/ copy as fallback
  backlog=$(git -C "$repo" show "origin/$def:.audit/minor-backlog.tsv" 2>/dev/null || git -C "$repo" show "origin/$def:.claude/audits/minor-backlog.tsv" 2>/dev/null || true)
  backlog=$(printf '%s' "$backlog" | grep -c . || true)
  visual=$(cd "$repo" && orch_visual_pass_all_files "origin/$def" | grep -c . || true)
  vcap="${AUDIT_VISUAL_PASS_CAP:-40}"; vnote=""
  [ "${visual:-0}" -le "$vcap" ] || vnote=" (cap $vcap)"
  if [ "${backlog:-0}" -eq 0 ] && [ "${visual:-0}" -eq 0 ]; then
    printf '%s\tnothing\tbacklog=0 visual_files=0\n' "$repo" >> "$TMP/rest"; continue
  fi

  if [ "$gh_ok" -ne 1 ]; then
    printf '%s\tskip-no-gh\tgh missing or not authenticated\n' "$repo" >> "$TMP/rest"; continue
  fi
  prs=$(cd "$repo" && gh pr list --state open --json number,headRefName --jq '.[] | select(.headRefName | startswith("chore/nightly-audit-") or startswith("chore/minor-backlog-")) | .number' 2>/dev/null) || {
    printf '%s\tskip-no-gh\tgh pr list failed\n' "$repo" >> "$TMP/rest"; continue; }
  if [ -n "$prs" ]; then
    printf '%s\tskip-open-pr\t#%s\n' "$repo" "$(printf '%s' "$prs" | head -1)" >> "$TMP/rest"; continue
  fi
  printf '%09d\t%s\tready\tbacklog=%s visual_files=%s%s\n' "$backlog" "$repo" "$backlog" "$visual" "$vnote" >> "$TMP/ready"
done < "$TMP/repos"

sort -r "$TMP/ready" | awk -F'\t' '{ printf "%s\t%s\t%s\n", $2, $3, $4 }'
cat "$TMP/rest"
