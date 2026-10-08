#!/usr/bin/env bash
# Targeted mutation run for /delegate Phase 5. Mutates only the changed files that the project lists
# in `.claude/mutation-targets` (one glob per line, `#` comments; optional test hint
# `<glob> :: NameTest|OtherTest` names the test classes to run for indirectly tested classes) and reports the survivors on
# lines the diff touched (+-3). A finding source for one extra test round, never a score target.
#
# Usage:
#   mutate.sh <root> <base-ref> [--oracle-files "<f1> <f2>"] [--files "<f1> <f2>"]
# --files (one string, split here) measures exactly those files, independent of the diff, and keeps
# every survivor (no changed-line filter; cap still applies). For pin mode: tests change, production
# code does not. A file matching no target glob is measured without a hint plus MUTATE_NOTE=not-a-target:<file>.
# Output (KEY=value, exit 0 always):
#   MUTATE_RESULT=OK|SKIP|TIMEOUT|ERROR
#   MUTATE_REASON=<why>                          with SKIP: no-targets, no-match, no-coverage,
#                                                no-runner, no-tests, no-timeout, no-mutations,
#                                                all-mutants-skipped (Infection per-mutant timeout, MUTATE_INFECTION_TIMEOUT, default 120 s);
#                                                with ERROR: runner-failed, initial-tests-failed
#   MUTATE_ERROR=<line>                          only with ERROR: first error line of the runner log
# Test discovery with a hint: oracle files plus the hinted test classes only (MUTATE_NOTE=hint-missing:<Name>
# for a name without a file). Without a hint: oracle files plus tests/ files whose basename starts with the class basename
# (MoneyTest.php for Money). Only when that set is empty: files that merely mention the class, Unit
# first, at most MUTATE_MAX_TEST_FILES (5), plus MUTATE_NOTE=fallback-test-selection:<n>. Skips any
# Browser/ directory (Playwright, far too slow for mutation). A runner that
# exits non-zero (not a timeout) without a result summary is ERROR, never OK. `No mutations created`
# (Pest resolved the class to another project's file, e.g. symlinked vendor/ in a worktree) makes
# that file a SKIP no-mutations. ERROR and SKIP never block the caller.
#   MUTATE_SCORE=<relpath>:<pct>                 when the runner reports one
#   SURVIVOR=<relpath>:<line>:<mutator>          changed lines +-3 (any line with --files), at most MUTATE_CAP (15)
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
#                                             (a deletion-only hunk emits its anchor line once)
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
      if (len == 0) print p ":" start   # pure deletion: anchor on the line before the gap
      for (j = 0; j < len; j++) print p ":" (start + j)
    }' "$1"
}

filter_survivors() { # changed-lines-file [nofilter] ; SURVIVOR_RAW lines on stdin
  awk -v cap="$CAP" -v cfile="$1" -v nofilter="${2:-}" '
    BEGIN { while ((getline l < cfile) > 0) { c = l; sub(/:[0-9]+$/, "", c); ln = substr(l, length(c) + 2) + 0; ch[c SUBSEP ln] = 1 } }
    /^SURVIVOR_RAW=/ {
      v = substr($0, 14)
      if (seen[v]++) next
      path = v; sub(/:[0-9]+:[^:]*$/, "", path)
      rest = substr(v, length(path) + 2); line = rest + 0
      hit = 0
      for (d = -3; d <= 3; d++) if ((path SUBSEP (line + d)) in ch) hit = 1
      if (!hit && nofilter == "") next
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
FILES=""
while [ $# -gt 0 ]; do
  case "$1" in --oracle-files) ORACLE_FILES=${2:-}; shift 2 ;; --files) FILES=${2:-}; shift 2 ;; *) shift ;; esac
done
if [ -z "$ROOT" ] || [ -z "$BASE" ]; then
  echo "usage: mutate.sh <root> <base-ref> [--oracle-files \"<f1> <f2>\"] [--files \"<f1> <f2>\"]" >&2
  exit 64
fi
cd "$ROOT" || exit 1
ROOT=$(pwd -P)

skip() { echo "MUTATE_RESULT=SKIP"; echo "MUTATE_REASON=$1"; exit 0; }

TARGETS="$ROOT/.claude/mutation-targets"
# --files measures the given files even without a targets file (all count as not-a-target)
if [ ! -f "$TARGETS" ]; then
  [ -n "$FILES" ] || skip no-targets
  TARGETS=/dev/null
fi

# git prints tracked (--name-only) and untracked paths relative to different bases inside a
# subdirectory; work from the top level so both share one.
if TOP=$(git rev-parse --show-toplevel 2>/dev/null); then cd "$TOP" && ROOT=$(pwd -P); fi

WORK=$(mktemp -d "${TMPDIR:-/tmp}/mutate.XXXXXX") || exit 1
trap 'rm -rf "$WORK"' EXIT

# Changed PHP files (tracked changes against the base plus untracked files) that match a target glob.
if [ -n "$FILES" ]; then
  # entries may be ./relative or absolute: normalize to repo-relative before matching
  for f in $FILES; do f=${f#./}; f=${f#"$ROOT"/}; echo "$f"; done | sort -u > "$WORK/changed"
else
  { git diff --name-only "$BASE" 2>/dev/null; git ls-files --others --exclude-standard 2>/dev/null; } | sort -u > "$WORK/changed"
fi
: > "$WORK/matched"
: > "$WORK/nontarget"
while IFS= read -r f; do
  case "$f" in *.php) ;; *) continue ;; esac
  [ -f "$f" ] || continue
  found=0
  while IFS= read -r glob || [ -n "$glob" ]; do
    glob=${glob%%#*}
    hint=""
    case "$glob" in *"::"*) hint=${glob#*::}; glob=${glob%%::*} ;; esac
    glob=$(printf '%s' "$glob" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')
    hint=$(printf '%s' "$hint" | tr -d '[:space:]')
    [ -n "$glob" ] || continue
    # shellcheck disable=SC2254
    case "$f" in $glob) printf '%s\t%s\n' "$f" "$hint" >> "$WORK/matched"; found=1; break ;; esac
  done < "$TARGETS"
  if [ -n "$FILES" ] && [ "$found" -eq 0 ]; then
    printf '%s\t\n' "$f" >> "$WORK/matched"
    echo "$f" >> "$WORK/nontarget"
  fi
done < "$WORK/changed"
[ -s "$WORK/matched" ] || skip no-match

php -m 2>/dev/null | grep -qiE '^(pcov|xdebug)$' || skip no-coverage

INFECTION_PHAR=${INFECTION_PHAR:-$HOME/.local/share/claude/infection.phar}
TIMEOUT_BIN=""
START=$SECONDS
EXECUTED=0
TIMED_OUT=0
LAST_REASON=no-runner
RUN_ERROR=""
RUN_FAILED=0
RUN_REASON=runner-failed
: > "$WORK/raw"
: > "$WORK/changed-lines"
: > "$WORK/scores"
: > "$WORK/notes"

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
  # Budget gone before the run: empty the log (the previous file's log must not be parsed again)
  # and return 1 so the caller stops without counting this file.
  if [ "$remaining" -le 0 ]; then RUN_STATUS=124; : > "$log"; return 1; fi
  cmd=$(printf '%q ' "$TIMEOUT_BIN" -k 10 "$remaining" "$@")
  # </dev/null: the runner must not read the caller's `while read` file list.
  bash "$HERE/test-lock.sh" --cmd "$cmd" > "$log" 2>&1 </dev/null
  RUN_STATUS=$?
}

while IFS=$'\t' read -r f hint; do
  [ "$TIMED_OUT" -eq 0 ] || break
  base=$(basename "$f" .php)

  RUNNER=""
  if [ -x vendor/bin/pest ] && grep -q 'pestphp/pest' composer.json 2>/dev/null; then RUNNER=pest
  elif { [ -f phpunit.xml ] || [ -f phpunit.xml.dist ]; } && [ -f "$INFECTION_PHAR" ]; then RUNNER=infection
  fi
  if [ -z "$RUNNER" ]; then LAST_REASON=no-runner; continue; fi

  # Test files: oracle files plus tests/ files that mention the class. An empty filter would run the
  # whole suite, so an empty list skips the file.
  # Primary set: oracle files plus tests/ files named after the class (MoneyTest.php for Money). Only
  # when it is empty, fall back to files that merely mention the class, Unit first, capped: DB-backed
  # Feature tests blow the time budget (15 files timed out at 500 s).
  if [ -n "$hint" ]; then
    # Per-target hint (`glob :: NameA|NameB`): oracle files plus the named test classes, nothing else.
    : > "$WORK/tests"
    for t in $ORACLE_FILES; do [ -f "$t" ] && echo "$t" >> "$WORK/tests"; done
    for name in $(printf '%s' "$hint" | tr '|' ' '); do
      found=$([ -d tests ] && find tests -type f -name "$name.php" 2>/dev/null | grep -vE '(^|/)Browser/')
      if [ -n "$found" ]; then printf '%s\n' "$found" >> "$WORK/tests"; else echo "MUTATE_NOTE=hint-missing:$name" >> "$WORK/notes"; fi
    done
    sort -u "$WORK/tests" -o "$WORK/tests"
  else
    { for t in $ORACLE_FILES; do [ -f "$t" ] && echo "$t"; done
      [ -d tests ] && find tests -type f -name "${base}*.php" 2>/dev/null
    } | grep -vE '(^|/)Browser/' | sort -u > "$WORK/tests"
    if [ ! -s "$WORK/tests" ] && [ -d tests ]; then
      grep -rlw --include='*.php' -- "$base" tests 2>/dev/null | grep -vE '(^|/)Browser/' | sort \
        | awk '{ print (index($0, "tests/Unit/") == 1 ? "0 " : "1 ") $0 }' | sort -s -k1,1 | cut -d' ' -f2- \
        | head -n "${MUTATE_MAX_TEST_FILES:-5}" > "$WORK/tests"
      [ -s "$WORK/tests" ] && echo "MUTATE_NOTE=fallback-test-selection:$(wc -l < "$WORK/tests" | tr -d ' ')" >> "$WORK/notes"
    fi
  fi
  if [ ! -s "$WORK/tests" ]; then LAST_REASON=no-tests; continue; fi

  if ! resolve_timeout; then
    [ "$EXECUTED" -eq 0 ] && skip no-timeout
    break
  fi

  LOG="$WORK/run.log"
  if [ "$RUNNER" = pest ]; then
    ns=$(sed -n 's/^namespace[[:space:]]*\([^;]*\);.*/\1/p' "$f" | head -1)
    fqcn=${ns:+$ns\\}$base
    TESTS=()
    while IFS= read -r t; do TESTS+=("$t"); done < "$WORK/tests"
    run_budgeted "$LOG" vendor/bin/pest --mutate --covered-only "--class=$fqcn" "${TESTS[@]}" || { TIMED_OUT=1; break; }
    parse_pest "$LOG" "$ROOT" "$f" > "$WORK/parsed"
  else
    srcdir=${f%%/*}
    inf_timeout=${MUTATE_INFECTION_TIMEOUT:-120}
    case "$inf_timeout" in
      ''|*[!0-9]*|0*) echo "MUTATE_NOTE=invalid-infection-timeout:$inf_timeout" >> "$WORK/notes"; inf_timeout=120 ;;
    esac
    cat > "$WORK/infection.json5" <<EOF
{
  "source": {"directories": ["$ROOT/$srcdir"]},
  "phpUnit": {"configDir": "$ROOT"},
  "timeout": $inf_timeout,
  "tmpDir": "$WORK/infection-tmp",
  "logs": {"text": "$WORK/infection-text.log"},
  "mutators": {"@default": true}
}
EOF
    : > "$WORK/infection-text.log"
    # Only the selected tests: a PHPUnit --filter of their class basenames keeps Infection off the full suite.
    tfilter=$(while IFS= read -r t; do basename "$t" .php; done < "$WORK/tests" | paste -sd'|' -)
    run_budgeted "$LOG" php "$INFECTION_PHAR" "--configuration=$WORK/infection.json5" "--filter=$f" \
      "--test-framework-options=--filter=$tfilter --order-by=default" \
      --only-covering-test-cases --threads=1 --no-interaction --no-progress || { TIMED_OUT=1; break; }
    {
      parse_infection "$WORK/infection-text.log" "$ROOT"
      # Covered Code MSI wins; the plain MSI line is only the fallback when it is absent.
      strip_ansi "$LOG" > "$WORK/inf-summary"
      score=$(sed -n 's|.*Covered Code MSI: \([0-9.]*\)%.*|\1|p' "$WORK/inf-summary" | head -1)
      [ -n "$score" ] || score=$(sed -n 's|.*Mutation Score Indicator (MSI): \([0-9.]*\)%.*|\1|p' "$WORK/inf-summary" | head -1)
      [ -z "$score" ] || echo "MUTATE_SCORE=$f:$score"
    } > "$WORK/parsed"
  fi
  strip_ansi "$LOG" > "$WORK/stripped"
  # Pest creates no mutations when it resolves the class to another project's file (a worktree whose
  # vendor/ is a symlink to the main project): nothing was tested, so this file is a SKIP.
  if grep -q 'No mutations created' "$WORK/stripped"; then LAST_REASON=no-mutations; continue; fi
  case "$RUN_STATUS" in
    0|124|137) ;;
    *)
      # The runner died before producing a result (e.g. Playwright missing): never report that as OK.
      # Anchored: a failing test can dump JS that contains the text `Mutations:` mid-line.
      INITIAL_FAILED=0
      grep -q 'Project tests must be in a passing state' "$WORK/stripped" && INITIAL_FAILED=1
      if [ "$INITIAL_FAILED" -eq 1 ] || ! grep -qE '^[[:space:]]*Mutations:[[:space:]]+[0-9]|Mutation Score Indicator \(MSI\):[[:space:]]*[0-9]|Covered Code MSI:[[:space:]]*[0-9]' "$WORK/stripped"; then
        RUN_ERROR=""
        if [ "$INITIAL_FAILED" -eq 1 ]; then
          RUN_REASON=initial-tests-failed
          RUN_ERROR=$(sed -n '/Project tests must be in a passing state/,$p' "$WORK/stripped" | grep -m1 -E 'tests/.*Test\.php:[0-9]+' | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')
        fi
        [ -n "$RUN_ERROR" ] || RUN_ERROR=$(grep -m1 -E 'Exception|Error|error' "$WORK/stripped" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')
        [ -n "$RUN_ERROR" ] || RUN_ERROR=$(grep -m1 -v '^[[:space:]]*$' "$WORK/stripped" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')
        [ -n "$RUN_ERROR" ] || RUN_ERROR="runner exited $RUN_STATUS without output"
        RUN_FAILED=1
        break
      fi ;;
  esac
  if [ "$RUNNER" = infection ]; then
    # Mutants Infection skips because their estimated test time exceeds the configured timeout are not tested: a file where every
    # generated mutant was skipped (or none generated) has no result.
    gen=$(sed -n 's/^[[:space:]]*\([0-9][0-9]*\) mutations were generated.*/\1/p' "$WORK/stripped" | head -1)
    skipped=$(sed -n 's/^[[:space:]]*\([0-9][0-9]*\) mutants required more time than configured.*/\1/p' "$WORK/stripped" | head -1)
    skipped=${skipped:-0}
    [ "$skipped" -gt 0 ] && echo "MUTATE_NOTE=skipped-mutants:$f:$skipped" >> "$WORK/notes"
    if [ -n "$gen" ] && [ "$skipped" -ge "$gen" ]; then LAST_REASON=all-mutants-skipped; continue; fi
  fi
  EXECUTED=$((EXECUTED + 1))
  # the not-a-target note only counts for a file that produced a result
  grep -qxF -- "$f" "$WORK/nontarget" && echo "MUTATE_NOTE=not-a-target:$f" >> "$WORK/notes"
  case "$RUN_STATUS" in 124|137) TIMED_OUT=1 ;; esac

  grep '^SURVIVOR_RAW=' "$WORK/parsed" >> "$WORK/raw"
  grep '^MUTATE_SCORE=' "$WORK/parsed" >> "$WORK/scores"
  if [ -f "$f" ] && [ -z "$FILES" ]; then
    if git ls-files --error-unmatch -- "$f" >/dev/null 2>&1; then git diff -U0 "$BASE" -- "$f" > "$WORK/diff"
    else git diff -U0 --no-index -- /dev/null "$f" > "$WORK/diff"; fi
    changed_lines "$WORK/diff" >> "$WORK/changed-lines"
  fi
done < "$WORK/matched"

if [ "$RUN_FAILED" -eq 1 ]; then
  echo "MUTATE_RESULT=ERROR"; echo "MUTATE_REASON=$RUN_REASON"; echo "MUTATE_ERROR=$RUN_ERROR"
  exit 0
fi
if [ "$EXECUTED" -eq 0 ]; then echo "MUTATE_RESULT=SKIP"; echo "MUTATE_REASON=$LAST_REASON"; cat "$WORK/notes"; exit 0; fi
if [ "$TIMED_OUT" -eq 1 ]; then echo "MUTATE_RESULT=TIMEOUT"; else echo "MUTATE_RESULT=OK"; fi
cat "$WORK/scores" "$WORK/notes"
filter_survivors "$WORK/changed-lines" "$FILES" < "$WORK/raw"
exit 0
