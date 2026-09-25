#!/usr/bin/env bash
# Print an advisory dimension suggestion from changed paths on stdin.
set -euo pipefail

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
     [[ ! "$path" =~ \.(blade\.php|html?|vue|tsx?|jsx?|css|scss|sass|less|styl|svelte|astro|swift|kt|kts|dart|xml|storyboard|xib)$ ]]; then
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
