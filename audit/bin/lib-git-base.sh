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
FRONTEND_EXT_RE='\.(blade\.php|html?|vue|tsx?|jsx?|css|scss|sass|less|svelte|astro|swift|kt|kts|dart|xml|storyboard|xib)$'

# The 12 audit dimensions in worker order. Shared by check-skips.sh (routing
# floor) and referenced by verify-agents.sh's agent-file list. Keep in sync
# with audit/agents/{1..12}-*.md.
AUDIT_DIMS="architecture security performance code_quality seo a11y typography ui_design ux animation docs_sync copy"

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
