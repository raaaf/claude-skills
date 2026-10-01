#!/usr/bin/env bash
#
# Pins that lib-orchestrator.sh works when sourced from zsh (2026-10-01): the Bash tool runs zsh, where
# BASH_SOURCE is empty, so ORCH_LIB_DIR resolved to the cwd and orch_backlog_add / orch_seo_relevant
# failed with "no such file: <cwd>/lib-git-base.sh" (orch_seo_relevant then printed `no` and dropped seo).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
command -v zsh >/dev/null 2>&1 || { echo 'SKIP zsh not installed'; exit 0; }

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
cd "$TMP"
git init -q .
mkdir -p src
printf 'a\n' > src/a.js
printf 'code_quality\tsrc/a.js\t1\t2026-10-01\tUnused import\n' > "$TMP/in.tsv"

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
expect "$(zsh -c ". '$SCRIPT_DIR/lib-orchestrator.sh'; orch_backlog_add '$TMP/in.tsv' >/dev/null; orch_backlog_count" 2>&1)" '1' \
  'zsh: orch_backlog_add finds lib-git-base.sh'
expect "$(bash -c ". '$SCRIPT_DIR/lib-orchestrator.sh'; printf '%s' \"\$ORCH_LIB_DIR\"")" "$SCRIPT_DIR" \
  'bash: ORCH_LIB_DIR unchanged'
