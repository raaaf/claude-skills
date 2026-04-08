#!/usr/bin/env bash
#
# Shared library: resolve the diff base for audit scripts.
# Sourced by collect-scope.sh, design-check.sh, and pre-check scripts.
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
