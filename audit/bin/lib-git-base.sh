#!/usr/bin/env bash
#
# Shared library: resolve the diff base for audit scripts.
# Sourced by collect-scope.sh, diff-size-gate.sh, pre-check scripts,
# check-skips.sh, and match-guidelines.sh.
#
# Exports:
#   DEFAULT_BRANCH — default branch name (main, master, develop, trunk, …)
#   BASE_REF       — commit sha that serves as the diff base
#
# Resolution order:
#   1. origin/HEAD symbolic ref
#   2. existing origin/{main,master,develop,trunk} branches
#   3. local {main,master,develop,trunk} branches
#   4. upstream @{u}
#   5. fallback: 20 commits back, capped at the root

resolve_default_branch() {
  local DEFAULT_BRANCH=""
  if git symbolic-ref refs/remotes/origin/HEAD >/dev/null 2>&1; then
    DEFAULT_BRANCH=$(git symbolic-ref refs/remotes/origin/HEAD | sed 's@^refs/remotes/origin/@@')
  fi
  if [ -z "$DEFAULT_BRANCH" ]; then
    for candidate in main master develop trunk; do
      if git rev-parse --verify "refs/remotes/origin/$candidate" >/dev/null 2>&1; then
        DEFAULT_BRANCH="$candidate"
        break
      fi
    done
  fi
  if [ -z "$DEFAULT_BRANCH" ]; then
    for candidate in main master develop trunk; do
      if git rev-parse --verify "refs/heads/$candidate" >/dev/null 2>&1; then
        DEFAULT_BRANCH="$candidate"
        break
      fi
    done
  fi
  [ -z "$DEFAULT_BRANCH" ] && DEFAULT_BRANCH="main"
  printf '%s' "$DEFAULT_BRANCH"
}

resolve_base_ref() {
  local DEFAULT_BRANCH="$1"
  local BASE_REF=""
  # AUDIT_BASE_REF lets a caller that already substituted the diff base
  # (e.g. because the branch has no upstream and the empty-diff fallback
  # picked the wrong commit) pass its own answer through instead of every
  # helper re-deriving origin/main independently. Verified so a stale or
  # typo'd override does not silently produce an empty BASE_REF; falls
  # through to the normal resolution order when unset, empty, or invalid.
  # Manually substituted 5 audits in a row before this override existed.
  if [ -n "${AUDIT_BASE_REF:-}" ] && git rev-parse --verify "$AUDIT_BASE_REF" >/dev/null 2>&1; then
    printf '%s' "$AUDIT_BASE_REF"
    return
  fi
  if git rev-parse --verify "refs/remotes/origin/$DEFAULT_BRANCH" >/dev/null 2>&1; then
    BASE_REF=$(git merge-base "origin/$DEFAULT_BRANCH" HEAD 2>/dev/null || true)
  fi
  if [ -z "$BASE_REF" ] && git rev-parse --verify '@{u}' >/dev/null 2>&1; then
    BASE_REF=$(git merge-base '@{u}' HEAD 2>/dev/null || true)
  fi
  if [ -z "$BASE_REF" ] && git rev-parse --verify "refs/heads/$DEFAULT_BRANCH" >/dev/null 2>&1; then
    BASE_REF=$(git merge-base "$DEFAULT_BRANCH" HEAD 2>/dev/null || true)
  fi
  if [ -z "$BASE_REF" ]; then
    BASE_REF=$(git rev-list --max-count=20 HEAD | tail -1)
  fi
  printf '%s' "$BASE_REF"
}

# Shared with check-skips.sh and match-guidelines.sh: the changed-files set
# for the current audit scope. Union of:
#   1. committed since BASE_REF (resolve_base_ref) up to HEAD
#   2. working tree vs HEAD (covers staged AND unstaged in one diff)
#   3. untracked files (respecting .gitignore)
# This mirrors collect-scope.sh's FILES computation, so any script filtering
# or routing on "which files changed" agrees with the diff actually being
# audited -- including on a branch with no upstream tracking branch, where a
# bare `@{u}` diff sees nothing and previously under-reported the file set.
# Prints one path per line, deduped and sorted. Caller applies its own
# additional filters (e.g. excluding eval fixtures). bash 3.2 safe.
collect_changed_files() {
  local DEFAULT_BRANCH BASE_REF
  DEFAULT_BRANCH=$(resolve_default_branch)
  BASE_REF=$(resolve_base_ref "$DEFAULT_BRANCH")
  {
    [ -n "$BASE_REF" ] && git diff --name-only "$BASE_REF"...HEAD 2>/dev/null
    git diff --name-only HEAD 2>/dev/null
    git ls-files --others --exclude-standard 2>/dev/null
  } | sort -u
}

# The root under which the per-repo audit store lives (.claude/audits: logs,
# learning-log.md, patterns.json, suppressions.json, run markers). Derived from
# `--git-common-dir`, not `--show-toplevel`: in a linked worktree the toplevel
# is the worktree's own root, so every store would fork per worktree
# (reproduced 2026-08-21, patterns.json; 2026-09-03, learning-log and
# suppressions invisible from a worktree). The common git dir is shared by
# every worktree of a repo. Bare or unusual layouts fall back to the toplevel.
# Tracked project files (CLAUDE.md, .claude/audit-guidelines.md) are NOT
# resolved through this: they legitimately differ per worktree/branch.
audit_store_root() {
  local common
  common=$(git rev-parse --path-format=absolute --git-common-dir 2>/dev/null) || return 1
  case "$common" in
    */.git) printf '%s' "${common%/.git}" ;;
    *) git rev-parse --show-toplevel 2>/dev/null ;;
  esac
}

# Canonical "is this a frontend file" extension pattern (grep -E form).
# Shared by collect-scope.sh (which files land in the FRONTEND scope list) and
# check-skips.sh (which dimensions the routing floor forces back on).
#
# These two were written independently and drifted: collect-scope knew
# xml/storyboard/xib but not sass/less, check-skips knew sass/less but not
# xml/storyboard/xib. So a changed .sass file forced a11y/ui/ux/animation on
# but never appeared in the frontend file list those workers were handed, and
# a changed .storyboard did the reverse. This is the union of both, defined
# once so the two can no longer disagree.
#
# Swift/Kotlin/Dart count as frontend on purpose: native projects need the
# a11y/UI/UX/animation workers too (see PLATFORM in detect-framework.sh).
# Over-matching is the safe direction here — an extra dimension running costs
# a worker, a missed one costs coverage.
FRONTEND_EXT_RE='\.(blade\.php|html?|vue|tsx?|jsx?|css|scss|sass|less|styl|svelte|astro|swift|kt|kts|dart|xml|storyboard|xib)$'

# The 13 unconditional audit dimensions in worker order (audit/agents/{1..13}-*.md);
# the conditional 14th, payments, is deliberately not listed, its gate lives in
# audit/SKILL.md Phase 1.5. Only consumer today: check-skips.sh, itself unwired
# since the 2026-09-05 rebuild (see CLAUDE.md Commands). verify-agents.sh keeps
# its own hardcoded roster and never reads this. The canonical list is
# DIMENSION_TABLE in audit/workflows/find.js.
AUDIT_DIMS="architecture security performance code_quality seo a11y typography ui_design ux animation docs_sync copy privacy"

# Dependency, build and tooling directories that no audit check should walk
# into (grep -E form, matches a path segment). Consumers that use `find`
# translate this into their own -prune arguments.
VENDOR_DIR_RE='(^|/)(node_modules|vendor|\.git|dist|build|\.next|\.nuxt|target|Pods|\.venv|venv|__pycache__)/'

# Shared with cache-write.sh and cache-check.sh: sha256 of a file, with a
# shasum fallback for systems without sha256sum. Do not change the hashing
# behaviour, cache keys depend on it staying identical across both callers.
hash_of() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" | awk '{print $1}'
  else
    shasum -a 256 "$1" | awk '{print $1}'
  fi
}

# Shared with cache-write.sh, patterns-store.sh and capture-screens.sh: add
# rel_path to repo_root/.gitignore, but only when it would actually change
# something. Skips a no-op mutation on a tracked file (a .gitignore entry
# cannot un-track it) and a redundant append when a broader rule already
# covers the path (check-ignore, not a literal grep, so ".claude/audits/"
# still matches "cache.json"). Any mutation that does happen is announced on
# stdout so it shows up in the audit log instead of being a silent side
# effect on a file the audit run does not own.
#
# Usage: gitignore_ensure <repo_root> <rel_path> [<check_path>]
# check_path defaults to rel_path -- pass a more specific path (e.g. the
# actual output directory) when rel_path itself is a pattern rather than a
# path that exists yet.
gitignore_ensure() {
  local repo_root="$1" rel_path="$2" check_path="${3:-$2}"
  # A symlinked .gitignore is never written to: ">>" follows the symlink and
  # would append outside the repo, and git itself ignores a symlinked
  # .gitignore (check-ignore never reports it as covering anything), so the
  # else branch below would otherwise re-append on every single run
  # (reproduced: three runs against a symlinked .gitignore produced three
  # appended lines in the link target). -L checks the link itself, no
  # dereference.
  if [ -L "$repo_root/.gitignore" ]; then
    echo "NOTE: $repo_root/.gitignore is a symlink; refusing to follow it. Not touching it -- add '$rel_path' to it manually if needed."
  elif git -C "$repo_root" ls-files --error-unmatch "$rel_path" >/dev/null 2>&1; then
    echo "NOTE: $rel_path is tracked by git; .gitignore cannot exclude it. Run 'git rm --cached $rel_path' if that was not intended."
  elif git -C "$repo_root" check-ignore -q "$check_path" 2>/dev/null; then
    echo "$rel_path already ignored, .gitignore left unchanged"
  else
    printf '\n%s\n' "$rel_path" >> "$repo_root/.gitignore"
    echo "Added $rel_path to .gitignore (was not previously ignored)"
  fi
}
