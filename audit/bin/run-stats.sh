#!/usr/bin/env bash
#
# run-stats.sh — read the personal run ledger ($HOME/.claude/skill-runs.jsonl,
# written by run-log.sh) and report ANOMALY conditions. This is a ledger plus
# a small set of checks, not a dashboard: the point is not "here are your
# stats", it is "here is a metric that looks off and might be lying to you",
# same motivation as check-docs-claims.sh but for run history instead of docs.
#
# Usage:
#   bash run-stats.sh [--days N] [--skill <name>] [--raw]
#
# --skill restricts the four skill-scoped conditions (1, 3, 4; and narrows 2
#   to just that skill) to one skill. --raw additionally prints the exact
#   ledger rows backing each reported anomaly, prefixed "  RAW ", so every
#   number in this report can be checked by hand instead of trusted blind —
#   the whole reason this script exists is that three separate "green"
#   numbers turned out to be false in one session, and a number nobody can
#   trace back to its rows is exactly how that happens again.
#
# --days N is deliberately narrow in scope: it overrides ONLY the
# ledger-stale window (condition 5, default LEDGER_STALE_DAYS below). It does
# NOT day-filter conditions 1/3/4 — condition 1 is defined as "last N runs",
# not "runs in the last N days", and 3/4 need full history for a trustworthy
# median/count. Day-filtering those would silently hide the very data the
# condition needs. This is a deliberate scope choice, not an oversight.
#
# ---- Thresholds (first guess, tune freely) ----
# A condition that has fired repeatedly without ever leading to an action is
# itself a defect and should be deleted from this script, same as any other
# noisy check in this repo.
ZERO_FINDINGS_STREAK_N=5      # how many of a skill's most recent runs must all show zero findings
DURATION_OUTLIER_MULT=3       # a run counts as an outlier above this multiple of its skill's median
DURATION_OUTLIER_MIN_RUNS=5   # minimum runs of a skill before its median is trusted at all
LEDGER_STALE_DAYS=7           # default "no entry in the last N days" window for condition 5
GATE_SKILLS="ship audit"      # the only skills expected to occasionally NOT pass their gate

set +e

LEDGER_FILE="$HOME/.claude/skill-runs.jsonl"

command -v jq >/dev/null 2>&1 || { echo "RUNSTATS_RESULT=SKIP (jq not available)"; exit 0; }

# ---- Argument parsing (same safe pattern as run-log.sh: never `shift 2`) ----
DAYS=""
SKILL_FILTER=""
RAW=0
while [ $# -gt 0 ]; do
  case "$1" in
    --days) DAYS="${2:-}"; shift ;;
    --skill) SKILL_FILTER="${2:-}"; shift ;;
    --raw) RAW=1 ;;
    *) : ;;
  esac
  shift
done
case "$DAYS" in
  ''|*[!0-9]*) DAYS="$LEDGER_STALE_DAYS" ;;
esac

if [ ! -f "$LEDGER_FILE" ]; then
  echo "RUNSTATS_RESULT=SKIP (no ledger at $LEDGER_FILE)"
  exit 0
fi

# Parse line by line, dropping anything that isn't valid JSON rather than
# failing the whole report on one corrupt line (e.g. a truncated write from a
# crashed process despite the atomic-append contract in run-log.sh).
ALL_JSON=$(jq -R -c 'try fromjson catch empty' "$LEDGER_FILE" 2>/dev/null | jq -s -c '[.[] | select(type == "object")]' 2>/dev/null)
[ -n "$ALL_JSON" ] || ALL_JSON="[]"

TOTAL=$(printf '%s' "$ALL_JSON" | jq 'length')
if [ "$TOTAL" -eq 0 ]; then
  echo "RUNSTATS_RESULT=SKIP (ledger empty or unparseable)"
  exit 0
fi

if [ -n "$SKILL_FILTER" ]; then
  SCOPED_JSON=$(printf '%s' "$ALL_JSON" | jq -c --arg sk "$SKILL_FILTER" '[.[] | select(.skill == $sk)]')
else
  SCOPED_JSON="$ALL_JSON"
fi

ANOM=0

print_raw() {
  # print_raw <json-array>: dump each row of a JSON array, one per line,
  # only when --raw was passed.
  [ "$RAW" -eq 1 ] || return 0
  printf '%s' "$1" | jq -c '.[]' 2>/dev/null | sed 's/^/  RAW /'
}

# ---- Condition 1: zero-findings-streak ----
# A skill's last N runs all reported zero findings (sum of all .counts
# values except "rounds", which is a loop counter, not a finding count).
# Runs with no .counts data at all are not eligible — "zero findings" must
# be something the run actually reported, not the absence of a report.
SKILLS=$(printf '%s' "$SCOPED_JSON" | jq -r '[.[].skill] | unique | .[]')
for sk in $SKILLS; do
  [ -n "$sk" ] || continue
  LAST_N=$(printf '%s' "$SCOPED_JSON" | jq -c --arg sk "$sk" --argjson n "$ZERO_FINDINGS_STREAK_N" \
    '[.[] | select(.skill == $sk)] | sort_by(.ts) | reverse | .[0:$n]')
  N_HAVE=$(printf '%s' "$LAST_N" | jq 'length')
  [ "$N_HAVE" -ge "$ZERO_FINDINGS_STREAK_N" ] || continue

  ALL_ZERO=$(printf '%s' "$LAST_N" | jq '
    [.[] | ((.counts // {}) | length > 0)] as $have
    | [.[] | ((.counts // {}) | to_entries | map(select(.key != "rounds")) | map(.value) | map(if type == "number" then . else 0 end) | add // 0)] as $sums
    | ($have | all) and ($sums | all(. == 0))')

  if [ "$ALL_ZERO" = "true" ]; then
    echo "RUNSTAT zero-findings-streak: skill '$sk' reported zero findings in its last $ZERO_FINDINGS_STREAK_N runs"
    print_raw "$LAST_N"
    ANOM=$((ANOM + 1))
  fi
done

# ---- Condition 2: never-triggered ----
# A skill directory exists on disk (has a SKILL.md) but has zero ledger
# entries ever, regardless of --days. Derived from the repo run-stats.sh is
# invoked in, same convention check-docs-claims.sh uses for its own scan.
ROOT=$(git rev-parse --show-toplevel 2>/dev/null)
if [ -n "$ROOT" ]; then
  DISK_SKILLS=$(find "$ROOT" -mindepth 2 -maxdepth 2 -name 'SKILL.md' \
    -not -path '*/node_modules/*' -not -path '*/vendor/*' -not -path '*/.git/*' 2>/dev/null \
    | sed "s|^${ROOT}/||" | sed 's|/SKILL\.md$||' | sort -u)
  if [ -n "$SKILL_FILTER" ]; then
    DISK_SKILLS=$(printf '%s\n' "$DISK_SKILLS" | grep -xF "$SKILL_FILTER" || true)
  fi
  while IFS= read -r sk; do
    [ -n "$sk" ] || continue
    HAVE=$(printf '%s' "$ALL_JSON" | jq --arg sk "$sk" '[.[] | select(.skill == $sk)] | length')
    if [ "$HAVE" = "0" ]; then
      echo "RUNSTAT never-triggered: skill '$sk' exists on disk ($ROOT/$sk/SKILL.md) but has no ledger entry at all"
      ANOM=$((ANOM + 1))
    fi
  done <<DISKEOF
$DISK_SKILLS
DISKEOF
fi

# ---- Condition 3: gate-never-blocked ----
# 'ship' or 'audit' logged runs, but every non-empty .gate value was
# "passed" — a gate that never fires may be dead. Entries with no .gate
# logged at all (empty string) are not counted as evidence either way.
for sk in $GATE_SKILLS; do
  if [ -n "$SKILL_FILTER" ] && [ "$SKILL_FILTER" != "$sk" ]; then
    continue
  fi
  GATED=$(printf '%s' "$ALL_JSON" | jq -c --arg sk "$sk" '[.[] | select(.skill == $sk) | select((.gate // "") != "")]')
  N_GATED=$(printf '%s' "$GATED" | jq 'length')
  [ "$N_GATED" -gt 0 ] || continue
  ALL_PASSED=$(printf '%s' "$GATED" | jq '[.[].gate] | all(. == "passed")')
  if [ "$ALL_PASSED" = "true" ]; then
    echo "RUNSTAT gate-never-blocked: skill '$sk' logged $N_GATED gated run(s), 'gate' was never anything but 'passed'"
    print_raw "$GATED"
    ANOM=$((ANOM + 1))
  fi
done

# ---- Condition 4: duration-outlier ----
# A single run whose duration_s is more than DURATION_OUTLIER_MULT times its
# skill's median, needing at least DURATION_OUTLIER_MIN_RUNS runs of that
# skill (with duration data) before the median is trusted.
for sk in $SKILLS; do
  [ -n "$sk" ] || continue
  DURS=$(printf '%s' "$SCOPED_JSON" | jq -c --arg sk "$sk" '[.[] | select(.skill == $sk) | select(.duration_s != null)]')
  N_DUR=$(printf '%s' "$DURS" | jq 'length')
  [ "$N_DUR" -ge "$DURATION_OUTLIER_MIN_RUNS" ] || continue

  MEDIAN=$(printf '%s' "$DURS" | jq '[.[].duration_s] | sort as $s | ($s | length) as $len
    | if ($len % 2) == 1 then $s[($len / 2 | floor)]
      else (($s[($len / 2) - 1] + $s[($len / 2)]) / 2)
      end')

  OUTLIERS=$(printf '%s' "$DURS" | jq -c --argjson med "$MEDIAN" --argjson mult "$DURATION_OUTLIER_MULT" \
    '[.[] | select(.duration_s > ($med * $mult))]')
  N_OUT=$(printf '%s' "$OUTLIERS" | jq 'length')
  if [ "$N_OUT" -gt 0 ]; then
    printf '%s' "$OUTLIERS" | jq -c '.[]' | while IFS= read -r row; do
      [ -n "$row" ] || continue
      D=$(printf '%s' "$row" | jq -r '.duration_s')
      T=$(printf '%s' "$row" | jq -r '.ts')
      echo "RUNSTAT duration-outlier: skill '$sk' run at $T took ${D}s, more than ${DURATION_OUTLIER_MULT}x the median (${MEDIAN}s over $N_DUR runs)"
      [ "$RAW" -eq 1 ] && printf '%s\n' "$row" | sed 's/^/  RAW /'
    done
    ANOM=$((ANOM + N_OUT))
  fi
done

# ---- Condition 5: ledger-stale ----
# No ledger entry for THIS repo in the last $DAYS days, although this repo
# has commits in that window. This is the self-check: it means the LOGGING
# is broken (run-log.sh not wired into a skill, or silently failing), not
# that the code is clean. Scoped to the current repo (project_path match)
# on purpose — a green ledger from some other project proves nothing about
# whether this repo's skills are logging.
if [ -n "$ROOT" ]; then
  COMMITS=$(git -C "$ROOT" log --since="${DAYS} days ago" --oneline 2>/dev/null | wc -l | tr -d ' ')
  if [ "${COMMITS:-0}" -gt 0 ]; then
    RECENT=$(printf '%s' "$ALL_JSON" | jq -c --arg root "$ROOT" --argjson days "$DAYS" \
      '(now - ($days * 86400)) as $cutoff | [.[] | select(.project_path == $root) | select((.ts | try fromdateiso8601 catch 0) >= $cutoff)]')
    N_RECENT=$(printf '%s' "$RECENT" | jq 'length')
    if [ "${N_RECENT:-0}" = "0" ]; then
      echo "RUNSTAT ledger-stale: no ledger entry for $ROOT in the last $DAYS days, but $COMMITS commit(s) landed in that window — logging is likely broken, not the code"
      ANOM=$((ANOM + 1))
    fi
  fi
fi

if [ "$ANOM" -gt 0 ]; then
  echo "RUNSTATS_RESULT=ANOMALIES ($ANOM)"
else
  echo "RUNSTATS_RESULT=OK"
fi

exit 0
