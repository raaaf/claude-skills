#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SCRIPT="$SCRIPT_DIR/suggest-dimensions.sh"
tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT

expect() {
  local input="$1" expected="$2" label="$3" output
  output=$(printf '%b' "$input" | bash "$SCRIPT")
  [[ "$output" == *"Recommended dimensions: $expected"* ]] || {
    printf 'FAIL %s\nExpected: %s\nGot: %s\n' "$label" "$expected" "$output" >&2
    exit 1
  }
  printf 'PASS %s\n' "$label"
}

expect 'docs/guide.md\nREADME.md\n' 'docs_sync,copy' 'docs-only'
expect 'src/page.tsx\nstyles/site.css\n' 'security,code_quality,seo,a11y,typography,ui_design,ux,animation,copy' 'frontend-only'
expect 'api/users.ts\nserver/auth.go\n' 'architecture,security,performance,code_quality,docs_sync,privacy' 'backend-only'
expect 'src/page.tsx\napi/users.ts\n' 'architecture,security,performance,code_quality,seo,a11y,typography,ui_design,ux,animation,docs_sync,copy,privacy' 'mixed paths'
expect 'mystery.bin\n' 'architecture,security,performance,code_quality,seo,a11y,typography,ui_design,ux,animation,docs_sync,copy,privacy' 'unknown path'
expect '' 'architecture,security,performance,code_quality,seo,a11y,typography,ui_design,ux,animation,docs_sync,copy,privacy' 'empty input'

env_output=$(printf 'src/page.tsx\n' | env AUDIT_DIMENSIONS='copy' AUDIT_FIX_SCOPE=none bash "$SCRIPT")
[[ "$env_output" == *'Recommended dimensions: security,code_quality,seo,a11y,typography,ui_design,ux,animation,copy'* ]] || exit 1
printf 'PASS does not read or modify audit environment\n'
[[ -z "${AUDIT_DIMENSIONS+x}" && -z "${AUDIT_FIX_SCOPE+x}" ]] || {
  printf 'FAIL test environment changed\n' >&2
  exit 1
}
files_before=$(find "$tmpdir" -mindepth 1 -maxdepth 1 -print | wc -l | tr -d ' ')
(cd "$tmpdir" && printf 'src/page.tsx\n' | bash "$SCRIPT" >/dev/null)
files_after=$(find "$tmpdir" -mindepth 1 -maxdepth 1 -print | wc -l | tr -d ' ')
[[ "$files_before" == "$files_after" ]] && printf 'PASS does not create a push marker or other files\n'
