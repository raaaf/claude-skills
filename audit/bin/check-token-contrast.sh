#!/usr/bin/env bash
#
# check-token-contrast.sh — deterministic WCAG contrast check for SwiftUI
# design tokens. A surface/background token used as a foreground color is
# almost always a mistake, and a real foreground token can still land on a
# background it was never designed against — neither is a syntax error, so
# nothing else catches it. Grep, not a parser: same policy as
# check-swift-deprecations.sh.
#
# Class A: a SURFACE token used directly as foreground (.foregroundStyle/
#   .foregroundColor/.stroke/.tint) — reported regardless of ratio.
# Class B: a (foreground token, background token) pair actually used
#   together in the same changed file, WCAG contrast below 3:1.
#
# Token table: parsed from *Token*.swift, *Palette*.swift, Color+*.swift,
# *Theme*.swift (--tokens FILE overrides). Understands Color(hex: "RRGGBB"),
# Color(hex: 0xRRGGBB), Color(red:green:blue:) only.
#
# Output: TOKEN_CONTRAST_HIT {file}:{line}: fg=... [bg=... ratio=x.y] -- ...
#         TOKEN_CONTRAST_RESULT=OK | HITS (N) | SKIP (reason)
#
# Usage: bash check-token-contrast.sh [PROJECT_ROOT] [--tokens FILE] [--all]
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
TOKENS_OVERRIDE=""
SCAN_ALL=0
ROOT=""
while [ $# -gt 0 ]; do
  case "$1" in
    --tokens) TOKENS_OVERRIDE="${2:-}"; shift 2 ;;
    --all) SCAN_ALL=1; shift ;;
    *) ROOT="$1"; shift ;;
  esac
done
ROOT="${ROOT:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
cd "$ROOT" 2>/dev/null || { echo "TOKEN_CONTRAST_RESULT=SKIP (root not found)"; exit 0; }
git rev-parse --is-inside-work-tree >/dev/null 2>&1 || { echo "TOKEN_CONTRAST_RESULT=SKIP (not a git repo)"; exit 0; }
# shellcheck disable=SC1091
source "$SCRIPT_DIR/lib-git-base.sh"
if [ -n "$TOKENS_OVERRIDE" ]; then
  TOKEN_FILES="$TOKENS_OVERRIDE"
else
  TOKEN_FILES=$(find . -type f \( -name '*Token*.swift' -o -name '*Palette*.swift' -o -name 'Color+*.swift' -o -name '*Theme*.swift' \) 2>/dev/null | grep -Ev "$VENDOR_DIR_RE" || true)
fi
[ -n "$TOKEN_FILES" ] || { echo "TOKEN_CONTRAST_RESULT=SKIP (no token file found)"; exit 0; }
if [ "$SCAN_ALL" -eq 1 ]; then
  SWIFT_FILES=$(find . -type f -name '*.swift' 2>/dev/null | grep -Ev "$VENDOR_DIR_RE" || true)
else
  SWIFT_FILES=$(collect_changed_files | grep -E '\.swift$' || true)
fi
[ -n "$SWIFT_FILES" ] || { echo "TOKEN_CONTRAST_RESULT=SKIP (no swift files to scan)"; exit 0; }

WORKDIR=$(mktemp -d "${TMPDIR:-/tmp}/token-contrast.XXXXXX") || { echo "TOKEN_CONTRAST_RESULT=SKIP (mktemp failed)"; exit 0; }
trap 'rm -rf "$WORKDIR"' EXIT
TOKEN_TABLE="$WORKDIR/tokens.tsv"; HITS_FILE="$WORKDIR/hits.txt"
: > "$TOKEN_TABLE"; : > "$HITS_FILE"

# hex2dec is shared (via awk -f) by the token parser and the contrast calc
# below, so the hex-digit math lives in exactly one place.
cat > "$WORKDIR/hex2dec.awk" <<'AWK'
function hex2dec(h,    i,c,v,result) {
  result = 0
  for (i = 1; i <= length(h); i++) {
    c = toupper(substr(h, i, 1))
    if (c >= "0" && c <= "9") v = index("0123456789", c) - 1
    else v = index("ABCDEF", c) + 9
    result = result * 16 + v
  }
  return result
}
AWK

cat > "$WORKDIR/parse-tokens.awk" <<'AWK'
{
  name = ""; hex = ""
  if (match($0, /static[ \t]+let[ \t]+[A-Za-z_][A-Za-z0-9_]*/)) {
    n = split(substr($0, RSTART, RLENGTH), parts, /[ \t]+/); name = parts[n]
  }
  if (name == "") next
  if (match($0, /hex:[ \t]*"#?[0-9A-Fa-f]{6,8}"/)) {
    seg = substr($0, RSTART, RLENGTH)
    if (match(seg, /[0-9A-Fa-f]{6,8}/)) hex = toupper(substr(seg, RSTART, 6))
  } else if (match($0, /hex:[ \t]*0x[0-9A-Fa-f]{6,8}/)) {
    seg = substr($0, RSTART, RLENGTH)
    if (match(seg, /[0-9A-Fa-f]{6,8}$/)) hex = toupper(substr(seg, RSTART, 6))
  } else if (match($0, /red:[ \t]*[0-9.]+,[ \t]*green:[ \t]*[0-9.]+,[ \t]*blue:[ \t]*[0-9.]+/)) {
    m = split(substr($0, RSTART, RLENGTH), nums, /[^0-9.]+/); cnt = 0; r = ""; g = ""; b = ""
    for (i = 1; i <= m; i++) if (nums[i] != "") {
      cnt++
      if (cnt == 1) r = nums[i]; else if (cnt == 2) g = nums[i]; else if (cnt == 3) b = nums[i]
    }
    if (r != "" && g != "" && b != "") {
      ri = int(r * 255 + 0.5); gi = int(g * 255 + 0.5); bi = int(b * 255 + 0.5)
      if (ri > 255) ri = 255; if (gi > 255) gi = 255; if (bi > 255) bi = 255
      hex = sprintf("%02X%02X%02X", ri, gi, bi)
    }
  }
  if (hex != "" && length(hex) == 6) {
    cls = (tolower(name) ~ /surface|background|bg|canvas|card|sheet|elevated/) ? "surface" : "fg"
    print name "\t" hex "\t" cls
  }
}
AWK

cat > "$WORKDIR/contrast.awk" <<'AWK'
function chan_lin(c8,    cs) { cs = c8 / 255; return (cs <= 0.03928) ? cs / 12.92 : ((cs + 0.055) / 1.055) ^ 2.4 }
function luminance(hex,    r, g, b) {
  r = chan_lin(hex2dec(substr(hex, 1, 2))); g = chan_lin(hex2dec(substr(hex, 3, 2))); b = chan_lin(hex2dec(substr(hex, 5, 2)))
  return 0.2126 * r + 0.7152 * g + 0.0722 * b
}
BEGIN {
  la = luminance(h1); lb = luminance(h2)
  lighter = (la > lb) ? la : lb; darker = (la > lb) ? lb : la
  printf "%.1f", (lighter + 0.05) / (darker + 0.05)
}
AWK

while IFS= read -r tf; do
  [ -n "$tf" ] && [ -f "$tf" ] || continue
  awk -f "$WORKDIR/hex2dec.awk" -f "$WORKDIR/parse-tokens.awk" "$tf" >> "$TOKEN_TABLE"
done <<< "$TOKEN_FILES"
awk -F'\t' '!seen[$1]++' "$TOKEN_TABLE" > "$TOKEN_TABLE.uniq" && mv "$TOKEN_TABLE.uniq" "$TOKEN_TABLE"
[ -s "$TOKEN_TABLE" ] || { echo "TOKEN_CONTRAST_RESULT=SKIP (no parseable tokens)"; exit 0; }
lookup_token() { awk -F'\t' -v n="$1" '$1==n{print $2"\t"$3; exit}' "$TOKEN_TABLE"; }
contrast_ratio() { awk -f "$WORKDIR/hex2dec.awk" -f "$WORKDIR/contrast.awk" -v h1="$1" -v h2="$2" </dev/null; }
while IFS= read -r file; do
  [ -n "$file" ] && [ -f "$file" ] || continue

  FG_USES=$(awk '
    {
      if (match($0, /\.(foregroundStyle|foregroundColor|stroke|tint)\(\.[A-Za-z_][A-Za-z0-9_]*/)) {
        seg = substr($0, RSTART, RLENGTH); sub(/^.*\(\./, "", seg)
        if (!(seg in seen)) { seen[seg] = 1; print NR "\t" seg }
      }
    }
  ' "$file")
  [ -n "$FG_USES" ] || continue

  BG_USES=""
  while IFS=$'\t' read -r tname thex tcls; do
    [ "$tcls" = "surface" ] || continue
    bl=$(grep -nE "\\.${tname}\\b" "$file" | head -1 | cut -d: -f1)
    [ -n "$bl" ] && BG_USES="${BG_USES}${bl}	${tname}
"
  done < "$TOKEN_TABLE"

  while IFS=$'\t' read -r fline fname; do
    [ -n "$fname" ] || continue
    info=$(lookup_token "$fname")
    [ -n "$info" ] || continue
    fhex="${info%%$'\t'*}"; fcls="${info##*$'\t'}"

    if [ "$fcls" = "surface" ]; then
      echo "TOKEN_CONTRAST_HIT $file:$fline: fg=$fname -- surface token used as foreground" >> "$HITS_FILE"
      continue
    fi
    [ -n "$BG_USES" ] || continue

    while IFS=$'\t' read -r bline bname; do
      [ -n "$bname" ] && [ "$bname" != "$fname" ] || continue
      binfo=$(lookup_token "$bname")
      bhex="${binfo%%$'\t'*}"
      [ -n "$bhex" ] || continue
      ratio=$(contrast_ratio "$fhex" "$bhex")
      below=$(awk -v r="$ratio" 'BEGIN{print (r+0 < 3.0) ? 1 : 0}')
      [ "$below" = "1" ] && echo "TOKEN_CONTRAST_HIT $file:$fline: fg=$fname bg=$bname ratio=$ratio -- contrast below 3.0" >> "$HITS_FILE"
    done <<< "$BG_USES"
  done <<< "$FG_USES"
done <<< "$SWIFT_FILES"

COUNT=$(grep -c . "$HITS_FILE" 2>/dev/null || echo 0)
if [ "$COUNT" -gt 0 ]; then
  cat "$HITS_FILE"
  echo "TOKEN_CONTRAST_RESULT=HITS ($COUNT)"
else
  echo "TOKEN_CONTRAST_RESULT=OK"
fi
