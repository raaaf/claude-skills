#!/usr/bin/env bash
#
# Fast deterministic pre-checks that run BEFORE any LLM subagent is
# dispatched. The goal is to catch high-signal, low-ambiguity issues
# (credential leaks, dependency drift) without spending tokens.
#
# Usage: bash pre-checks.sh
#
# Output (one section per check):
#   SECRET_SCAN_RESULT=CLEAN | FINDINGS
#   <SECRET findings, one per line: file:line: matched pattern>
#   ---
#   LOCKFILE_DRIFT_RESULT=CLEAN | DRIFT
#   <drift lines: "lockfile X changed but manifest Y unchanged">
#   ---
#   BINARY_ARTIFACTS_RESULT=CLEAN | FINDINGS
#   <files that look like committed build output / node_modules / .DS_Store>
#
# Exit code is always 0. Consumers interpret the output; hard failures
# are the orchestrator's decision.
set -euo pipefail

# shellcheck disable=SC1091
source "$(dirname "$0")/lib-git-base.sh"

PROJECT_ROOT=$(git rev-parse --show-toplevel)
cd "$PROJECT_ROOT"

DEFAULT_BRANCH=$(resolve_default_branch)
BASE_REF=$(resolve_base_ref "$DEFAULT_BRANCH")

# Collect changed files once; reuse across checks.
CHANGED=$(
  {
    git diff --name-only "$BASE_REF"...HEAD 2>/dev/null || true
    git diff --name-only HEAD 2>/dev/null || true
    git ls-files --others --exclude-standard
  } | grep -v '^$' | sort -u || true
)

# ===========================================================================
# 1. Secret scan
# ===========================================================================
# High-confidence patterns only. We'd rather miss a few than drown in false
# positives from normal config keys. Matches against added lines in the
# unified diff, not committed history.
SECRET_PATTERNS='(aws_access_key_id|aws_secret_access_key|AKIA[0-9A-Z]{16}|'
SECRET_PATTERNS+='-----BEGIN [A-Z ]*PRIVATE KEY-----|'
SECRET_PATTERNS+='ghp_[A-Za-z0-9]{36}|gho_[A-Za-z0-9]{36}|ghs_[A-Za-z0-9]{36}|'
SECRET_PATTERNS+='github_pat_[A-Za-z0-9_]{82}|'
SECRET_PATTERNS+='sk-[A-Za-z0-9]{32,}|sk-ant-[A-Za-z0-9-]{80,}|'
SECRET_PATTERNS+='xox[baprs]-[A-Za-z0-9-]{10,}|'
SECRET_PATTERNS+='SG\.[A-Za-z0-9_-]{22}\.[A-Za-z0-9_-]{43}|'
SECRET_PATTERNS+='AIza[0-9A-Za-z_-]{35}|'
SECRET_PATTERNS+='(api[_-]?key|secret|password|token|passwd)["\x27 ]*[:=]["\x27 ]*[A-Za-z0-9/+=_-]{16,})'

SECRET_FINDINGS=$(
  {
    git diff "$BASE_REF"...HEAD 2>/dev/null || true
    git diff HEAD 2>/dev/null || true
  } | grep -nE "^\+" | grep -viE "^\+\+\+" \
    | grep -iE "$SECRET_PATTERNS" || true
)

if [ -n "$SECRET_FINDINGS" ]; then
  echo "SECRET_SCAN_RESULT=FINDINGS"
  printf '%s\n' "$SECRET_FINDINGS"
else
  echo "SECRET_SCAN_RESULT=CLEAN"
fi
echo "---"

# ===========================================================================
# 2. Lockfile drift — lockfile changed without its manifest
# ===========================================================================
LOCKFILE_DRIFT=""
has_change() { printf '%s\n' "$CHANGED" | grep -qxF "$1"; }

check_pair() {
  local lock="$1"; local manifest="$2"
  if has_change "$lock" && ! has_change "$manifest"; then
    LOCKFILE_DRIFT+="DRIFT: $lock changed but $manifest unchanged"$'\n'
  fi
}

check_pair "package-lock.json" "package.json"
check_pair "yarn.lock"         "package.json"
check_pair "pnpm-lock.yaml"    "package.json"
check_pair "composer.lock"     "composer.json"
check_pair "Gemfile.lock"      "Gemfile"
check_pair "poetry.lock"       "pyproject.toml"
check_pair "Cargo.lock"        "Cargo.toml"
check_pair "go.sum"            "go.mod"

if [ -n "$LOCKFILE_DRIFT" ]; then
  echo "LOCKFILE_DRIFT_RESULT=DRIFT"
  printf '%s' "$LOCKFILE_DRIFT"
else
  echo "LOCKFILE_DRIFT_RESULT=CLEAN"
fi
echo "---"

# ===========================================================================
# 3. Binary artifacts / committed build output
# ===========================================================================
ARTIFACT_PATTERNS='(^|/)(node_modules|vendor|\.next|\.nuxt|dist|build|out|coverage|\.DS_Store|Thumbs\.db)(/|$)'
ARTIFACT_FINDINGS=$(printf '%s\n' "$CHANGED" | grep -E "$ARTIFACT_PATTERNS" || true)

if [ -n "$ARTIFACT_FINDINGS" ]; then
  echo "BINARY_ARTIFACTS_RESULT=FINDINGS"
  printf '%s\n' "$ARTIFACT_FINDINGS"
else
  echo "BINARY_ARTIFACTS_RESULT=CLEAN"
fi
