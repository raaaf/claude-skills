#!/usr/bin/env bash
# Targeted mutation run for /delegate Phase 5. Mutates only the changed files that the project lists
# in `.claude/mutation-targets` (one glob per line, `#` comments) and reports the survivors on
# lines the diff touched (+-3). A finding source for one extra test round, never a score target.
#
# Usage:
#   mutate.sh <root> <base-ref> [--oracle-files "<f1> <f2>"]
# Output (KEY=value, exit 0 always):
#   MUTATE_RESULT=OK|SKIP|TIMEOUT
#   MUTATE_REASON=<why>                          only with SKIP (no-targets, no-match, no-coverage,
#                                                no-runner, no-tests, no-timeout)
#   MUTATE_SCORE=<relpath>:<pct>                 when the runner reports one
#   SURVIVOR=<relpath>:<line>:<mutator>          changed lines +-3, at most MUTATE_CAP (15)
#   SURVIVORS_TRUNCATED=<n>                      survivors beyond the cap
#
# Runners per PHP file: Pest when vendor/bin/pest exists and composer.json requires pestphp/pest
# (`--mutate --covered-only --class=<FQCN>`; covered-only still lists UNTESTED mutants on covered
# code, `--everything` hangs); else Infection when phpunit.xml(.dist) exists and $INFECTION_PHAR
# (default ~/.local/share/claude/infection.phar) is present. A pcov or xdebug driver is required.
#
# Time: ONE total budget MUTATE_BUDGET (default 600 s) across all files. `timeout` or `gtimeout`
# is resolved here; neither present -> SKIP, never an unbounded run (unlike check-outdated.sh, which
# fails open). The timeout sits INSIDE the test-lock.sh command and kills the whole process group,
# so no orphaned CPU-bound child keeps the lock (deploy-gate waiters give up after 960 s).
#
# Parser helpers (pinned by mutate.test.sh against real logs, see fixtures/mutate/):
#   mutate.sh --parse-pest <log> --root <prefix> [--file <rel>]
#   mutate.sh --parse-infection <log> --root <prefix>
#       -> SURVIVOR_RAW=<relpath>:<line>:<mutator> per survivor, MUTATE_UNFILTERED=<n>, and for
#          Pest MUTATE_SCORE=<relpath>:<pct>. --root turns absolute log paths repo-relative.
#   mutate.sh --changed-lines <diff-file>     zero-context unified diff -> <path>:<line> per added line
#   mutate.sh --filter <changed-lines-file>   SURVIVOR_RAW lines on stdin -> SURVIVOR=/SURVIVORS_TRUNCATED=
# bash 3.2 compatible.
set -u

HERE=$(cd "$(dirname "$0")" && pwd)
CAP=${MUTATE_CAP:-15}
BUDGET=${MUTATE_BUDGET:-600}

ESC=$(printf '\033')
strip_ansi() { sed "s/${ESC}\\[[0-9;]*[A-Za-z]//g" "$1"; }

parse_pest() { # log root [file]
  strip_ansi "$1" | awk -v root="${2%/}" -v file="${3:-}" '
    function rel(p) { if (root != "" && index(p, root "/") == 1) return substr(p, length(root) + 2); return p }
    $1 == "UNTESTED" {
      i = index($0, "> Line ")
      if (i == 0) next
      rest = substr($0, i + 7)
      n = rest + 0
      m = rest; sub(/^[0-9]+: /, "", m); sub(/ - ID:.*/, "", m)
      p = rel($2)
      if (first == "") first = p
      print "SURVIVOR_RAW=" p ":" n ":" m
      count++
    }
    /Score:/ { s = $2; sub(/%/, "", s); score = s }
    END {
      print "MUTATE_UNFILTERED=" count + 0
      if (score != "") { f = (file != "" ? file : (first != "" ? first : "-")); print "MUTATE_SCORE=" f ":" score }
    }'
}

parse_infection() { # log root
  strip_ansi "$1" | awk -v root="${2%/}" '
    function rel(p) { if (root != "" && index(p, root "/") == 1) return substr(p, length(root) + 2); return p }
    /^[A-Za-z ]+ mutants:$/ { sect = ($0 ~ /^Escaped/) ; next }
    sect && $1 ~ /^[0-9]+\)$/ {
      loc = $2; c = 0
      for (k = length(loc); k > 0; k--) if (substr(loc, k, 1) == ":") { c = k; break }
      if (c == 0) next
      print "SURVIVOR_RAW=" rel(substr(loc, 1, c - 1)) ":" substr(loc, c + 1) ":" $4
      count++
    }
    /Mutation Score Indicator \(MSI\):/ { s = $NF; sub(/%/, "", s); score = s }
    END { print "MUTATE_UNFILTERED=" count + 0 }'
}

changed_lines() { # diff-file
  awk '
    /^\+\+\+ / { p = $2; sub(/^b\//, "", p); if ($2 == "/dev/null") p = ""; next }
    /^@@ / {
      if (p == "") next
      s = $3; sub(/^\+/, "", s)
      n = split(s, a, ",")
      start = a[1] + 0; len = (n > 1 ? a[2] + 0 : 1)
      for (j = 0; j < len; j++) print p ":" (start + j)
    }' "$1"
}

filter_survivors() { # changed-lines-file ; SURVIVOR_RAW lines on stdin
  awk -v cap="$CAP" -v cfile="$1" '
    BEGIN { while ((getline l < cfile) > 0) { c = l; sub(/:[0-9]+$/, "", c); ln = substr(l, length(c) + 2) + 0; ch[c SUBSEP ln] = 1 } }
    /^SURVIVOR_RAW=/ {
      v = substr($0, 14)
      if (seen[v]++) next
      path = v; sub(/:[0-9]+:[^:]*$/, "", path)
      rest = substr(v, length(path) + 2); line = rest + 0
      hit = 0
      for (d = -3; d <= 3; d++) if ((path SUBSEP (line + d)) in ch) hit = 1
      if (!hit) next
      if (kept < cap) { print "SURVIVOR=" v; kept++ } else extra++
    }
    END { if (extra > 0) print "SURVIVORS_TRUNCATED=" extra }'
}

case "${1:-}" in
  --parse-pest|--parse-infection)
    MODE=$1; LOG=${2:-}; shift 2
    ROOTP=""; FILEP=""
    while [ $# -gt 0 ]; do
      case "$1" in --root) ROOTP=${2:-}; shift 2 ;; --file) FILEP=${2:-}; shift 2 ;; *) shift ;; esac
    done
    if [ "$MODE" = "--parse-pest" ]; then parse_pest "$LOG" "$ROOTP" "$FILEP"; else parse_infection "$LOG" "$ROOTP"; fi
    exit 0 ;;
  --changed-lines) changed_lines "${2:-/dev/null}"; exit 0 ;;
  --filter) filter_survivors "${2:-/dev/null}"; exit 0 ;;
esac

ROOT=${1:-}
BASE=${2:-}
shift 2 2>/dev/null || true
ORACLE_FILES=""
while [ $# -gt 0 ]; do
  case "$1" in --oracle-files) ORACLE_FILES=${2:-}; shift 2 ;; *) shift ;; esac
done
if [ -z "$ROOT" ] || [ -z "$BASE" ]; then
  echo "usage: mutate.sh <root> <base-ref> [--oracle-files \"<f1> <f2>\"]" >&2
  exit 64
fi
cd "$ROOT" || exit 1
ROOT=$(pwd -P)

skip() { echo "MUTATE_RESULT=SKIP"; echo "MUTATE_REASON=$1"; exit 0; }

TARGETS=".claude/mutation-targets"
[ -f "$TARGETS" ] || skip no-targets

WORK=$(mktemp -d "${TMPDIR:-/tmp}/mutate.XXXXXX") || exit 1
trap 'rm -rf "$WORK"' EXIT

# Changed PHP files (tracked changes against the base plus untracked files) that match a target glob.
{ git diff --name-only "$BASE" 2>/dev/null; git ls-files --others --exclude-standard 2>/dev/null; } | sort -u > "$WORK/changed"
: > "$WORK/matched"
while IFS= read -r f; do
  case "$f" in *.php) ;; *) continue ;; esac
  [ -f "$f" ] || continue
  while IFS= read -r glob || [ -n "$glob" ]; do
    glob=${glob%%#*}
    glob=$(printf '%s' "$glob" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')
    [ -n "$glob" ] || continue
    # shellcheck disable=SC2254
    case "$f" in $glob) echo "$f" >> "$WORK/matched"; break ;; esac
  done < "$TARGETS"
done < "$WORK/changed"
[ -s "$WORK/matched" ] || skip no-match

php -m 2>/dev/null | grep -qiE '^(pcov|xdebug)$' || skip no-coverage

INFECTION_PHAR=${INFECTION_PHAR:-$HOME/.local/share/claude/infection.phar}
TIMEOUT_BIN=""
START=$SECONDS
EXECUTED=0
TIMED_OUT=0
LAST_REASON=no-runner
: > "$WORK/raw"
: > "$WORK/changed-lines"
: > "$WORK/scores"

resolve_timeout() {
  if command -v timeout >/dev/null 2>&1; then TIMEOUT_BIN=timeout
  elif command -v gtimeout >/dev/null 2>&1; then TIMEOUT_BIN=gtimeout
  else return 1; fi
}

# Runs "$@" under the shared test lock with the remaining budget; sets RUN_STATUS.
run_budgeted() { # log cmd...
  local log=$1 remaining cmd
  shift
  remaining=$((BUDGET - (SECONDS - START)))
  if [ "$remaining" -le 0 ]; then RUN_STATUS=124; return; fi
  cmd=$(printf '%q ' "$TIMEOUT_BIN" -k 10 "$remaining" "$@")
  bash "$HERE/test-lock.sh" --cmd "$cmd" > "$log" 2>&1
  RUN_STATUS=$?
}

while IFS= read -r f; do
  [ "$TIMED_OUT" -eq 0 ] || break
  base=$(basename "$f" .php)

  RUNNER=""
  if [ -x vendor/bin/pest ] && grep -q 'pestphp/pest' composer.json 2>/dev/null; then RUNNER=pest
  elif { [ -f phpunit.xml ] || [ -f phpunit.xml.dist ]; } && [ -f "$INFECTION_PHAR" ]; then RUNNER=infection
  fi
  if [ -z "$RUNNER" ]; then LAST_REASON=no-runner; continue; fi

  # Test files: oracle files plus tests/ files that mention the class. An empty filter would run the
  # whole suite, so an empty list skips the file.
  { for t in $ORACLE_FILES; do [ -f "$t" ] && echo "$t"; done
    [ -d tests ] && grep -rlw --include='*.php' -- "$base" tests 2>/dev/null
  } | sort -u > "$WORK/tests"
  if [ ! -s "$WORK/tests" ]; then LAST_REASON=no-tests; continue; fi

  if ! resolve_timeout; then
    [ "$EXECUTED" -eq 0 ] && skip no-timeout
    break
  fi

  LOG="$WORK/run-$EXECUTED.log"
  if [ "$RUNNER" = pest ]; then
    ns=$(sed -n 's/^namespace[[:space:]]*\([^;]*\);.*/\1/p' "$f" | head -1)
    fqcn=${ns:+$ns\\}$base
    TESTS=()
    while IFS= read -r t; do TESTS+=("$t"); done < "$WORK/tests"
    run_budgeted "$LOG" vendor/bin/pest --mutate --covered-only "--class=$fqcn" "${TESTS[@]}"
    parse_pest "$LOG" "$ROOT" "$f" > "$WORK/parsed"
  else
    srcdir=${f%%/*}
    cat > "$WORK/infection.json5" <<EOF
{
  "source": {"directories": ["$ROOT/$srcdir"]},
  "phpUnit": {"configDir": "$ROOT"},
  "tmpDir": "$WORK/infection-tmp",
  "logs": {"text": "$WORK/infection-text.log"},
  "mutators": {"@default": true}
}
EOF
    : > "$WORK/infection-text.log"
    run_budgeted "$LOG" php "$INFECTION_PHAR" "--configuration=$WORK/infection.json5" "--filter=$f" \
      --only-covering-test-cases --order-by=default --threads=1 --no-interaction --no-progress
    {
      parse_infection "$WORK/infection-text.log" "$ROOT"
      strip_ansi "$LOG" | sed -n "s/.*Mutation Score Indicator (MSI): \([0-9.]*\)%.*/MUTATE_SCORE=$f:\1/p" | head -1
    } > "$WORK/parsed"
  fi
  EXECUTED=$((EXECUTED + 1))
  case "$RUN_STATUS" in 124|137) TIMED_OUT=1 ;; esac

  grep '^SURVIVOR_RAW=' "$WORK/parsed" >> "$WORK/raw"
  grep '^MUTATE_SCORE=' "$WORK/parsed" >> "$WORK/scores"
  if [ -f "$f" ]; then
    if git ls-files --error-unmatch -- "$f" >/dev/null 2>&1; then git diff -U0 "$BASE" -- "$f" > "$WORK/diff"
    else git diff -U0 --no-index -- /dev/null "$f" > "$WORK/diff"; fi
    changed_lines "$WORK/diff" >> "$WORK/changed-lines"
  fi
done < "$WORK/matched"

if [ "$EXECUTED" -eq 0 ]; then skip "$LAST_REASON"; fi
if [ "$TIMED_OUT" -eq 1 ]; then echo "MUTATE_RESULT=TIMEOUT"; else echo "MUTATE_RESULT=OK"; fi
cat "$WORK/scores"
filter_survivors "$WORK/changed-lines" < "$WORK/raw"
exit 0
