#!/usr/bin/env bash
#
# Pins orch_seo_relevant (decided 2026-10-01): seo runs only when the repo has an SEO surface AND the
# diff touches a frontend or routes file. Evidence: 4% of audit-find cost, 12 Important, 0 Critical in
# 12 days, mostly logged-in apps. robots.txt alone is no surface (Laravel ships one by default).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
. "$SCRIPT_DIR/lib-orchestrator.sh"

TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
n=0
mk() { n=$((n + 1)); R="$TMP/r$n"; mkdir -p "$R/resources/views" "$R/routes" "$R/app" "$R/public"; }

expect() {
  local changed="$1" expected="$2" label="$3" output
  output=$(orch_seo_relevant "$changed" "$R" 2>/dev/null)
  [[ "$output" == "$expected" ]] || { printf 'FAIL %s\nExpected: %s\nGot: %s\n' "$label" "$expected" "$output" >&2; exit 1; }
  printf 'PASS %s\n' "$label"
}

VIEW=$'resources/views/dash.blade.php\n'

mk; echo '<h1>Dashboard</h1>' > "$R/resources/views/dash.blade.php"
expect "$VIEW" no 'no surface, view change'

mk; echo '<meta name="description" content="x">' > "$R/resources/views/layout.blade.php"
expect "$VIEW" yes 'surface + view change'

mk; echo '<meta property="og:title" content="x">' > "$R/resources/views/layout.blade.php"
expect $'app/Models/User.php\n' no 'surface + only backend PHP change'

mk; printf 'User-agent: *\nDisallow:\n' > "$R/public/robots.txt"; echo '<h1>x</h1>' > "$R/resources/views/a.blade.php"
expect "$VIEW" no 'robots.txt only'

mk; echo '<script type="application/ld+json">{}</script>' > "$R/resources/views/layout.blade.php"
expect $'routes/web.php\n' yes 'surface + routes file change'

mk; : > "$R/public/sitemap.xml"
expect $'src/App.tsx\n' yes 'sitemap file + frontend change'

mk; echo '<meta name="description" content="x">' > "$R/resources/views/layout.blade.php"
PLATFORM=native expect "$VIEW" no 'PLATFORM=native never'

mk; echo '<meta name="description" content="x">' > "$R/resources/views/layout.blade.php"
[[ "$(orch_seo_surface "$R" 2>/dev/null)" == yes ]] || { echo 'FAIL surface alone' >&2; exit 1; }
echo 'PASS surface alone'
