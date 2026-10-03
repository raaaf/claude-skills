#!/usr/bin/env bash
#
# Pins that lib-orchestrator.sh works when sourced from zsh (2026-10-01): the Bash tool runs zsh, where
# BASH_SOURCE is empty, so ORCH_LIB_DIR resolved to the cwd and every function that sources
# lib-git-base.sh (today orch_unaudited_record without an upstream) failed with "no such file:
# <cwd>/lib-git-base.sh".
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
command -v zsh >/dev/null 2>&1 || { echo 'SKIP zsh not installed'; exit 0; }

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
cd "$TMP"
git init -q -b main .
git config user.email test@test.com
git config user.name test
git commit -q --allow-empty -m c1

expect() {
  local got="$1" expected="$2" label="$3"
  [[ "$got" == "$expected" ]] || {
    printf 'FAIL %s\nExpected: %s\nGot: %s\n' "$label" "$expected" "$got" >&2
    exit 1
  }
  printf 'PASS %s\n' "$label"
}

expect "$(zsh -c ". '$SCRIPT_DIR/lib-orchestrator.sh'; print -r -- \$ORCH_LIB_DIR")" "$SCRIPT_DIR" \
  'zsh: ORCH_LIB_DIR is the lib directory, not the cwd'
expect "$(zsh -c ". '$SCRIPT_DIR/lib-orchestrator.sh'; orch_unaudited_record && orch_unaudited_base" 2>&1)" "$(git rev-parse HEAD)" \
  'zsh: orch_unaudited_record finds lib-git-base.sh (no upstream)'
expect "$(bash -c ". '$SCRIPT_DIR/lib-orchestrator.sh'; printf '%s' \"\$ORCH_LIB_DIR\"")" "$SCRIPT_DIR" \
  'bash: ORCH_LIB_DIR unchanged'
