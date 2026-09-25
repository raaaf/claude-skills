#!/usr/bin/env bash
# Print an advisory dimension suggestion from changed paths on stdin.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# Guarded source: a missing lib-git-base.sh must not silently kill this
# script. Fallback below mirrors collect-scope.sh's pattern.
[ -r "$SCRIPT_DIR/lib-git-base.sh" ] && source "$SCRIPT_DIR/lib-git-base.sh"
# FRONTEND_EXT_RE is the canonical frontend-extension pattern, defined once in
# lib-git-base.sh so this script cannot drift from collect-scope.sh's FRONTEND
# list the way collect-scope.sh and check-skips.sh once did. Literal fallback
# only fires when the lib is missing.
FE_RE="${FRONTEND_EXT_RE:-\.(blade\.php|html?|vue|tsx?|jsx?|css|scss|sass|less|styl|svelte|astro|swift|kt|kts|dart|xml|storyboard|xib)$}"

paths=()
while IFS= read -r path; do
  [ -n "$path" ] && paths+=("$path")
done < <(sed '/^[[:space:]]*$/d' | sort -u)

all="architecture,security,performance,code_quality,seo,a11y,typography,ui_design,ux,animation,docs_sync,copy,privacy"
backend="architecture,security,performance,code_quality,docs_sync,privacy"
frontend="security,code_quality,seo,a11y,typography,ui_design,ux,animation,copy"

if [ "${#paths[@]}" -eq 0 ]; then
  printf 'Recommended dimensions: %s\nReason: no changed paths were provided; use the full audit set.\n' "$all"
  exit 0
fi

all_docs=1
all_frontend=1
all_backend=1
for path in "${paths[@]}"; do
  case "$path" in
    *.md|*.mdx|*.rst|*.txt|*.adoc) ;;
    *) all_docs=0 ;;
  esac

  if [[ "$path" =~ ^(backend|server|api|cmd|internal|worker|workers|functions|lambda)/ ]] ||
     [[ ! "$path" =~ $FE_RE ]]; then
    all_frontend=0
  fi

  case "$path" in
    backend/*|server/*|api/*|cmd/*|internal/*|worker/*|workers/*|functions/*|lambda/*) ;;
    *) all_backend=0 ;;
  esac
done

if [ "$all_docs" -eq 1 ]; then
  printf 'Recommended dimensions: docs_sync,copy\nReason: all changed paths are prose or documentation files.\n'
elif [ "$all_frontend" -eq 1 ]; then
  printf 'Recommended dimensions: %s\nReason: all changed paths match frontend file types; security and code_quality remain included.\n' "$frontend"
elif [ "$all_backend" -eq 1 ]; then
  printf 'Recommended dimensions: %s\nReason: all changed paths are under recognized backend path prefixes.\n' "$backend"
else
  printf 'Recommended dimensions: %s\nReason: paths are mixed or not confidently classifiable; use the full audit set.\n' "$all"
fi
