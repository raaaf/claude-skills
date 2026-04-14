#!/usr/bin/env bash
#
# Route detection for visual-baseline skill.
# Outputs JSON array of route objects to stdout.
#
# Usage: bash detect-routes.sh [PROJECT_ROOT]
#
# Supports: Laravel, Next.js, Nuxt, Vite/static, generic
set -euo pipefail

ROOT="${1:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
cd "$ROOT"

# --- Framework detection ---

FRAMEWORK="generic"
if [ -f "artisan" ]; then
  FRAMEWORK="laravel"
elif [ -f "package.json" ] && grep -q '"next"' package.json 2>/dev/null; then
  FRAMEWORK="nextjs"
elif [ -f "nuxt.config.ts" ] || [ -f "nuxt.config.js" ]; then
  FRAMEWORK="nuxt"
elif [ -f "vite.config.ts" ] || [ -f "vite.config.js" ] || [ -f "vite.config.mjs" ]; then
  FRAMEWORK="vite"
fi

echo "FRAMEWORK=$FRAMEWORK" >&2

# --- Route collection ---

case "$FRAMEWORK" in
  laravel)
    # Use artisan route:list, filter to GET web routes (no API, no vendor)
    php artisan route:list --method=GET --except-vendor --json 2>/dev/null \
      | jq '[.[] | select(.uri != null) | select(.uri | test("^(api/|_|sanctum|livewire)") | not) | {
          slug: (.uri | gsub("[/{};?]"; "-") | gsub("-+"; "-") | gsub("^-|-$"; "")),
          url: ("/" + .uri),
          view_files: [],
          auth: ((.middleware // "") | test("auth"))
        }] | unique_by(.url)' 2>/dev/null || echo "[]"
    ;;

  nextjs)
    # Filesystem-based routing: app/ or pages/ directory
    ROUTES="[]"
    if [ -d "app" ]; then
      ROUTES=$(find app -name "page.tsx" -o -name "page.jsx" -o -name "page.js" 2>/dev/null \
        | sed 's|^app||; s|/page\.[jt]sx\?$||; s|^$|/|' \
        | jq -R -s 'split("\n") | map(select(length > 0)) | map({
            slug: (gsub("[/]"; "-") | gsub("^-|-$"; "") | if . == "" then "homepage" else . end),
            url: .,
            view_files: [],
            auth: false
          })' 2>/dev/null || echo "[]")
    elif [ -d "pages" ]; then
      ROUTES=$(find pages -name "*.tsx" -o -name "*.jsx" -o -name "*.js" 2>/dev/null \
        | grep -v '_app\|_document\|_error\|api/' \
        | sed 's|^pages||; s|\.[jt]sx\?$||; s|/index$|/|; s|^$|/|' \
        | jq -R -s 'split("\n") | map(select(length > 0)) | map({
            slug: (gsub("[/]"; "-") | gsub("^-|-$"; "") | if . == "" then "homepage" else . end),
            url: .,
            view_files: [],
            auth: false
          })' 2>/dev/null || echo "[]")
    fi
    echo "$ROUTES"
    ;;

  nuxt)
    # Filesystem-based routing: pages/ directory
    find pages -name "*.vue" 2>/dev/null \
      | sed 's|^pages||; s|\.vue$||; s|/index$|/|; s|^$|/|' \
      | jq -R -s 'split("\n") | map(select(length > 0)) | map({
          slug: (gsub("[/]"; "-") | gsub("^-|-$"; "") | if . == "" then "homepage" else . end),
          url: .,
          view_files: [],
          auth: false
        })' 2>/dev/null || echo "[]"
    ;;

  vite)
    # Check vite config for rollupOptions.input entries, or scan for HTML files
    # First try: HTML files in project root and subdirectories (excluding node_modules, dist)
    find . -maxdepth 2 -name "*.html" -not -path "*/node_modules/*" -not -path "*/dist/*" -not -path "*/.claude/*" 2>/dev/null \
      | sed 's|^\./||' \
      | jq -R -s 'split("\n") | map(select(length > 0)) | map({
          slug: (gsub("[/.]"; "-") | gsub("-html$"; "") | gsub("^-|-$"; "") | if . == "" or . == "index" then "homepage" else . end),
          url: ("/" + (gsub("index\\.html$"; "") | gsub("\\.html$"; ""))),
          view_files: [.],
          auth: false
        }) | unique_by(.slug)' 2>/dev/null || echo "[]"
    ;;

  generic)
    # Fallback: scan for HTML files or common entry points
    find . -maxdepth 3 -name "*.html" -not -path "*/node_modules/*" -not -path "*/dist/*" -not -path "*/.claude/*" 2>/dev/null \
      | head -50 \
      | sed 's|^\./||' \
      | jq -R -s 'split("\n") | map(select(length > 0)) | map({
          slug: (gsub("[/.]"; "-") | gsub("-html$"; "") | gsub("^-|-$"; "") | if . == "" or . == "index" then "homepage" else . end),
          url: ("/" + (gsub("index\\.html$"; "") | gsub("\\.html$"; ""))),
          view_files: [.],
          auth: false
        }) | unique_by(.slug)' 2>/dev/null || echo "[]"
    ;;
esac
