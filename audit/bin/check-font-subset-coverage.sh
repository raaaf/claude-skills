#!/usr/bin/env bash
#
# check-font-subset-coverage.sh — deterministic check that every codepoint
# actually used in the project's text sources is present in the bundled
# (subsetted) fonts.
#
# Why: font subsetting keeps bundle size down by stripping glyphs nobody
# uses, but the codepoint set it keeps is only as good as the sample text the
# subsetting step was given. A codepoint used somewhere in the app but
# missing from that sample silently renders as .notdef (usually a tofu box,
# sometimes nothing at all) — no build error, no console warning. Near-miss
# 2026-08-21: a font-subset update dropped U+2192 (an arrow used in lang/,
# resources/views/ and resources/landing/); only caught by a worker's manual
# sweep of actually-used characters, not by any existing deterministic check.
#
# Requires python3 with fontTools (`python3 -c "import fontTools"`). Fails
# open (SKIP, never a false finding) when python3, fontTools, or no bundled
# woff2/ttf/otf files are found — an environment gap must not masquerade as
# a font defect, and a project that doesn't self-host/subset fonts at all is
# simply out of scope for this check.
#
# Scans (whichever exist): lang/, resources/views/, resources/help/,
# resources/landing/ — override via FONT_COVERAGE_SCAN_DIRS (space-separated,
# for non-Laravel layouts).
# Fonts: public/fonts/, public/build/, resources/fonts/ (recursively,
# *.woff2/*.ttf/*.otf) — override via FONT_COVERAGE_FONT_DIRS.
#
# Output:
#   FONTCOVERAGE_RESULT=OK
#   FONTCOVERAGE_RESULT=MISSING (N)
#   FONTCOVERAGE {file}:{line}: U+{hex} "{char}" used here, not in any bundled font (checked: {fonts})
#   FONTCOVERAGE_RESULT=SKIP ({reason})
#
# Usage: bash check-font-subset-coverage.sh [ROOT]
set -uo pipefail

ROOT="${1:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
cd "$ROOT" 2>/dev/null || { echo "FONTCOVERAGE_RESULT=SKIP (root not found)"; exit 0; }

command -v python3 >/dev/null 2>&1 || { echo "FONTCOVERAGE_RESULT=SKIP (python3 not available)"; exit 0; }
python3 -c "import fontTools" >/dev/null 2>&1 || {
  echo "FONTCOVERAGE_RESULT=SKIP (fontTools not installed — pip install fonttools)"
  exit 0
}

# ---- scan dirs (text sources whose used codepoints must be covered) ----
SCAN_DIRS="${FONT_COVERAGE_SCAN_DIRS:-}"
if [ -z "$SCAN_DIRS" ]; then
  for d in lang resources/views resources/help resources/landing; do
    [ -d "$d" ] && SCAN_DIRS="$SCAN_DIRS $d"
  done
fi
SCAN_DIRS="${SCAN_DIRS# }"
[ -n "$SCAN_DIRS" ] || { echo "FONTCOVERAGE_RESULT=SKIP (no scan dirs present: lang/, resources/views/, resources/help/, resources/landing/)"; exit 0; }

# ---- font dirs (bundled, subsetted fonts) ----
FONT_DIRS="${FONT_COVERAGE_FONT_DIRS:-}"
if [ -z "$FONT_DIRS" ]; then
  for d in public/fonts public/build resources/fonts; do
    [ -d "$d" ] && FONT_DIRS="$FONT_DIRS $d"
  done
fi
FONT_DIRS="${FONT_DIRS# }"
[ -n "$FONT_DIRS" ] || { echo "FONTCOVERAGE_RESULT=SKIP (no font directories present: public/fonts/, public/build/, resources/fonts/)"; exit 0; }

# shellcheck disable=SC2086
FONT_FILES=$(find $FONT_DIRS -type f \( -name '*.woff2' -o -name '*.ttf' -o -name '*.otf' \) 2>/dev/null | sort -u)
[ -n "$FONT_FILES" ] || { echo "FONTCOVERAGE_RESULT=SKIP (no woff2/ttf/otf files found under: $FONT_DIRS)"; exit 0; }

# shellcheck disable=SC2086
SCAN_FILES=$(find $SCAN_DIRS -type f \( -name '*.php' -o -name '*.md' -o -name '*.blade.php' -o -name '*.json' \) 2>/dev/null | sort -u)
[ -n "$SCAN_FILES" ] || { echo "FONTCOVERAGE_RESULT=SKIP (scan dirs present but contain no .php/.md/.json/.blade.php files)"; exit 0; }

# Do the actual codepoint diff in python: fontTools reads each font's cmap
# (the authoritative "glyphs this font can render" table — a plain string
# `grep` over the binary cannot do this), the scan files are read as UTF-8
# text and every non-ASCII codepoint (ASCII is assumed always present; every
# bundled web font covers it) is compared against the UNION of all font
# cmaps. A codepoint covered by ANY one of the bundled fonts counts as
# covered — projects commonly split latin/cyrillic/emoji across files.
python3 - "$SCAN_FILES" "$FONT_FILES" <<'PYEOF'
import sys

scan_files = [f for f in sys.argv[1].splitlines() if f]
font_files = [f for f in sys.argv[2].splitlines() if f]

try:
    from fontTools.ttLib import TTFont
except ImportError:
    print("FONTCOVERAGE_RESULT=SKIP (fontTools import failed unexpectedly)")
    sys.exit(0)

covered = set()
readable_fonts = []
for ff in font_files:
    try:
        font = TTFont(ff, lazy=True, fontNumber=0)
        cmap = font.getBestCmap()
        if cmap:
            covered.update(cmap.keys())
            readable_fonts.append(ff)
    except Exception:
        # A font fontTools cannot parse is not this check's problem to
        # diagnose — skip it silently rather than crash the whole scan.
        continue

if not readable_fonts:
    print("FONTCOVERAGE_RESULT=SKIP (none of the found font files could be parsed by fontTools)")
    sys.exit(0)

MAX_FINDINGS = 30
findings = []
seen_codepoints_reported = set()

for sf in scan_files:
    try:
        with open(sf, "r", encoding="utf-8", errors="strict") as fh:
            lines = fh.readlines()
    except Exception:
        continue
    for lineno, line in enumerate(lines, start=1):
        for ch in line:
            cp = ord(ch)
            if cp < 128:
                continue
            if cp in (0x00A0,):  # NBSP: near-universal, not worth flagging
                continue
            if cp in covered:
                continue
            # Cap per distinct codepoint so one repeated character doesn't
            # spam dozens of identical lines; still report every DISTINCT
            # missing codepoint at its first occurrence.
            if cp in seen_codepoints_reported:
                continue
            seen_codepoints_reported.add(cp)
            findings.append((sf, lineno, cp, ch))
            if len(findings) >= MAX_FINDINGS:
                break
        if len(findings) >= MAX_FINDINGS:
            break
    if len(findings) >= MAX_FINDINGS:
        break

if not findings:
    print("FONTCOVERAGE_RESULT=OK")
    sys.exit(0)

fonts_desc = ", ".join(readable_fonts)
for sf, lineno, cp, ch in findings:
    display = ch if ch.isprintable() else "?"
    print(f"FONTCOVERAGE {sf}:{lineno}: U+{cp:04X} \"{display}\" used here, not in any bundled font (checked: {fonts_desc})")

capped = " (capped, more may exist)" if len(findings) >= MAX_FINDINGS else ""
print(f"FONTCOVERAGE_RESULT=MISSING ({len(findings)}){capped}")
PYEOF
