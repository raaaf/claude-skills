#!/usr/bin/env bash
#
# check-number-format-locale.sh — deterministic scan for PHP number_format()
# calls that rely on the English default separators.
#
# Why this exists: number_format($amount, 2) renders "1,234.56". In a German
# project that is wrong everywhere, and it is easy to miss in review because
# the call looks complete. The correct form carries both separator arguments:
# number_format($amount, 2, ',', '.'). This recurred twice inside a single
# audit run, which is what earned it a deterministic check.
#
# Scope: templates only (resources/views by default). Application code has
# legitimate uses (CSV/XML export, API payloads, DATEV) where the English
# format is deliberate, so flagging it there produces noise.
#
# Only runs when the project actually ships a German locale — otherwise the
# English default is presumably intended.
#
# Output:
#   NUMFMT_RESULT=OK | MISSING_LOCALE | SKIP
#   For MISSING_LOCALE: one line per hit: "NUMFMT {file}:{line}: {code}"
#
# Usage: bash check-number-format-locale.sh [PROJECT_ROOT]
set -uo pipefail

ROOT="${1:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"

# German locale present? Otherwise the default separators are fine.
if [ ! -d "$ROOT/lang/de" ] && [ ! -d "$ROOT/resources/lang/de" ]; then
  echo "NUMFMT_RESULT=SKIP"
  exit 0
fi

VIEWS=""
for candidate in "$ROOT/resources/views" "$ROOT/views"; do
  [ -d "$candidate" ] && { VIEWS="$candidate"; break; }
done
[ -n "$VIEWS" ] || { echo "NUMFMT_RESULT=SKIP"; exit 0; }

# A correct call passes four arguments. Counting them needs paren depth, not a
# flat regex: "(float)$x" and nested calls both contain parens, and separators
# are frequently passed as variables ($decSep) rather than quoted literals.
HITS=$(find "$VIEWS" \( -name '*.blade.php' -o -name '*.php' \) -type f -print0 2>/dev/null \
      | xargs -0 perl -ne '
          close ARGV if eof;   # reset $. per file, otherwise line numbers accumulate
          my $line = $_;
          while ($line =~ /number_format\(/g) {
              my $start = pos($line);
              my $depth = 1;
              my $commas = 0;
              my $i = $start;
              while ($i < length($line) && $depth > 0) {
                  my $c = substr($line, $i, 1);
                  if    ($c eq "(") { $depth++ }
                  elsif ($c eq ")") { $depth-- }
                  elsif ($c eq "," && $depth == 1) { $commas++ }
                  $i++;
              }
              next if $depth > 0;          # call continues on the next line, skip
              next if $commas >= 3;        # decimals + both separators present
              # Zero decimals: no decimal separator to get wrong. These are
              # percentages and rates in practice, where the English thousands
              # separator never shows up either.
              my $args = substr($line, $start, $i - $start - 1);
              next if $args =~ /,\s*0\s*$/;
              my $code = $line;
              $code =~ s/^\s+//; $code =~ s/\s+$//;
              print "$ARGV:$.: $code\n";
              last;
          }
      ' 2>/dev/null || true)

if [ -n "$HITS" ]; then
  echo "NUMFMT_RESULT=MISSING_LOCALE"
  printf '%s\n' "$HITS" | while IFS= read -r line; do
    [ -n "$line" ] && echo "NUMFMT $line"
  done
else
  echo "NUMFMT_RESULT=OK"
fi
