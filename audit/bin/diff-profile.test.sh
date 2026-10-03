#!/usr/bin/env bash
#
# Pins diff-profile.sh (2026-10-03): which dimensions each kind of diff suggests, the tier lists and the
# cost estimate. Every case builds a throwaway git repo with a base commit and untracked changed files.
set -euo pipefail

SCRIPT="$(cd "$(dirname "$0")" && pwd)/diff-profile.sh"
tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT

fail=0
# profile <label> <size|""> <file>...   writes the files (content = "x" or the CONTENT env), prints the profile
profile() {
  local label="$1" size="$2" f repo="$tmpdir/$1"; shift 2
  mkdir -p "$repo"
  (cd "$repo" && git init -q && git config user.email t@t && git config user.name t && echo base > base.txt \
    && git add base.txt && git commit -q -m base)
  for f in "$@"; do mkdir -p "$repo/$(dirname "$f")"; printf '%s\n' "${CONTENT:-x}" > "$repo/$f"; done
  (cd "$repo" && printf '%s\n' "$@" | DIFF_SIZE_RESULT="$size" AUDIT_BASE_REF=HEAD bash "$SCRIPT" "$repo")
}
val() { printf '%s\n' "$1" | sed -n "s/^$2=//p" | head -1; }
expect() { # <label> <profile> <key> <expected>
  local got; got=$(val "$2" "$3")
  if [ "$got" = "$4" ]; then printf 'PASS %s: %s=%s\n' "$1" "$3" "$4"
  else printf 'FAIL %s: %s expected %s, got %s\n' "$1" "$3" "$4" "$got" >&2; fail=1; fi
}

P=$(profile frontend OK resources/views/home.blade.php resources/css/app.css)
expect frontend "$P" SUGGEST_a11y yes
expect frontend "$P" SUGGEST_copy yes
expect frontend "$P" SUGGEST_typography yes
expect frontend "$P" TIER_GUENSTIG security,privacy,architecture,a11y,copy
expect frontend "$P" SUGGEST_code_quality no

P=$(CONTENT='$rows = DB::table("a")->where("x", 1)->get();' profile migration OK database/migrations/2026_create_a.php)
expect migration "$P" SUGGEST_performance yes
expect migration "$P" SUGGEST_a11y no
expect migration "$P" TIER_GUENSTIG security,privacy,architecture

P=$(profile docs SMALL README.md docs/guide.md)
expect docs "$P" SUGGEST_docs_sync yes
expect docs "$P" SUGGEST_a11y no
expect docs "$P" SUGGEST_performance no

P=$(profile backend SMALL app/Services/Mailer.php app/Services/Clock.php)
for d in a11y copy seo typography ui_design ux animation docs_sync performance code_quality; do expect backend "$P" SUGGEST_$d no; done
expect backend "$P" RECOMMENDED GUENSTIG

P=$(profile backend-large LARGE app/Services/Mailer.php)
expect backend-large "$P" SUGGEST_code_quality yes

P=$(profile sensitive SMALL app/Http/Middleware/AuthCheck.php)
expect sensitive "$P" RECOMMENDED GRUENDLICH

P=$(profile tiers OK resources/views/home.blade.php resources/css/app.css lang/de.json README.md)
expect tiers "$P" SUGGEST_COUNT 7
expect tiers "$P" RECOMMENDED GRUENDLICH
expect tiers "$P" TIER_ALLES architecture,security,performance,code_quality,seo,a11y,typography,ui_design,ux,animation,docs_sync,copy,privacy
expect tiers "$P" COST_GUENSTIG 18
expect tiers "$P" COST_GRUENDLICH 33
expect tiers "$P" COST_ALLES 42

P=$(profile cost-small SMALL app/Services/Mailer.php)
expect cost-small "$P" COST_GUENSTIG 8
expect cost-small "$P" COST_ALLES 23
[ "$fail" = 0 ] && printf 'All diff-profile.sh tests passed.\n'
[ "$fail" = 0 ]
