#!/usr/bin/env bash
#
# Shared library: resolve the diff base for audit scripts.
# Sourced by collect-scope.sh, pre-checks.sh and the check-*.sh scripts.
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

# The changed-files set
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
# suppressions.json, run markers). Derived from
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

# Canonical "is this a frontend file" extension pattern (grep -E form), defined once.
# Used by collect-scope.sh (which files land in the FRONTEND scope list). Swift/Kotlin/Dart
# count as frontend on purpose: native projects have UI files too (see PLATFORM in
# detect-framework.sh).
FRONTEND_EXT_RE='\.(blade\.php|html?|vue|tsx?|jsx?|css|scss|sass|less|styl|svelte|astro|swift|kt|kts|dart|xml|storyboard|xib)$'

# Dependency, build and tooling directories that no audit check should walk
# into (grep -E form, matches a path segment). Consumers that use `find`
# translate this into their own -prune arguments.
VENDOR_DIR_RE='(^|/)(node_modules|vendor|\.git|dist|build|\.next|\.nuxt|target|Pods|\.venv|venv|__pycache__)/'
