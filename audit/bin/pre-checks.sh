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
#   <SECRET findings, one per line: file:line: pattern-name (type only, never
#    the matched value or the surrounding line)>
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
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/lib-git-base.sh"

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
#
# Findings never reproduce the matched value or the surrounding line: this
# script's output feeds the audit log under .claude/audits/, which is
# committed to a public repo. Only the file, the real line number in that
# file, and the pattern's name/type are emitted.
SECRET_PATTERN_NAMES=(
  "aws-credential-keyword"
  "aws-access-key-id"
  "pem-private-key"
  "github-token"
  "github-fine-grained-pat"
  "openai-or-anthropic-api-key"
  "slack-token"
  "sendgrid-api-key"
  "google-api-key"
  "generic-secret-assignment"
)
SECRET_PATTERN_REGEXES=(
  'aws_access_key_id|aws_secret_access_key'
  'AKIA[0-9A-Z]{16}'
  '-----BEGIN [A-Z ]*PRIVATE KEY-----'
  'ghp_[A-Za-z0-9]{36}|gho_[A-Za-z0-9]{36}|ghs_[A-Za-z0-9]{36}'
  'github_pat_[A-Za-z0-9_]{82}'
  'sk-[A-Za-z0-9]{32,}|sk-ant-[A-Za-z0-9-]{80,}'
  'xox[baprs]-[A-Za-z0-9-]{10,}'
  'SG\.[A-Za-z0-9_-]{22}\.[A-Za-z0-9_-]{43}'
  'AIza[0-9A-Za-z_-]{35}'
  '(api[_-]?key|secret|password|token|passwd)["\x27 ]*[:=]["\x27 ]*[A-Za-z0-9/+=_-]{16,}'
)

# Prints the name of the first pattern matching $1 on stdout; fails silently
# (no output) if nothing matches. Never echoes the matched text itself.
match_secret_pattern() {
  local content="$1"
  local count="${#SECRET_PATTERN_NAMES[@]}"
  local i
  for ((i = 0; i < count; i++)); do
    if printf '%s' "$content" | grep -qiE -- "${SECRET_PATTERN_REGEXES[$i]}"; then
      printf '%s' "${SECRET_PATTERN_NAMES[$i]}"
      return 0
    fi
  done
  return 1
}

# Emits "<line_no><TAB><content>" for every added line of $1, with the line
# number resolved directly from where the addition landed -- never by
# re-searching the file for matching text, which is ambiguous when the same
# line occurs more than once. Tracked files are read from the diff hunks
# (their own new-file line numbers). Untracked files never appear in any
# `git diff` output at all -- git has nothing to compare them to -- so the
# whole on-disk file is treated as added content, one pair per line; this is
# also the shape a leaked credential most often has: written to disk, not
# yet `git add`ed.
added_lines_with_numbers() {
  local file="$1"
  if git ls-files --error-unmatch -- "$file" >/dev/null 2>&1; then
    {
      git diff --unified=0 "$BASE_REF"...HEAD -- "$file" 2>/dev/null || true
      git diff --unified=0 HEAD -- "$file" 2>/dev/null || true
    } | awk '
      /^@@/ {
        match($0, /\+[0-9]+/)
        newstart = substr($0, RSTART + 1, RLENGTH - 1) + 0
        offset = 0
        next
      }
      /^\+\+\+/ { next }
      /^\+/ {
        printf "%d\t%s\n", newstart + offset, substr($0, 2)
        offset++
        next
      }
    '
  else
    awk '{ printf "%d\t%s\n", NR, $0 }' "$file"
  fi
}

SECRET_FINDINGS=""
while IFS= read -r changed_file; do
  [ -z "$changed_file" ] && continue
  # Need the file on disk to point at a real line inside it; a path that
  # only exists inside historical diff hunks (since deleted again) is
  # skipped rather than reported with a stale/fabricated location.
  [ -f "$changed_file" ] || continue

  pairs=$(added_lines_with_numbers "$changed_file")
  [ -z "$pairs" ] && continue

  while IFS=$'\t' read -r line_no line_content; do
    [ -z "$line_content" ] && continue
    pattern_name=$(match_secret_pattern "$line_content") || continue
    # line_no came straight from the diff hunk / file line count above --
    # never from a secondary lookup, so the credential text is never passed
    # as a grep argv word (it only ever flows through stdin, inside
    # match_secret_pattern).
    SECRET_FINDINGS+="$changed_file:$line_no: $pattern_name"$'\n'
  done <<< "$pairs"
done <<< "$CHANGED"
SECRET_FINDINGS="${SECRET_FINDINGS%$'\n'}"

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
check_pair "Podfile.lock"      "Podfile"
check_pair "Package.resolved"  "Package.swift"
check_pair "pubspec.lock"      "pubspec.yaml"
check_pair "gradle.lockfile"   "build.gradle"

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
