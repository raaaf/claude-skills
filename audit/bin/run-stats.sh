#!/usr/bin/env bash
#
# run-stats.sh — read the personal run ledger
# ($HOME/.local/state/claude/skill-runs.jsonl,
# written by run-log.sh) and report ANOMALY conditions. This is a ledger plus
# a small set of checks, not a dashboard: the point is not "here are your
# stats", it is "here is a metric that looks off and might be lying to you",
# same motivation as check-docs-claims.sh but for run history instead of docs.
#
# Usage:
#   bash run-stats.sh [--days N] [--skill <name>] [--raw]
#
# --skill restricts the skill-scoped condition (gate-never-blocked) to one
#   skill. --raw additionally prints the exact ledger rows backing each
#   reported anomaly, prefixed "  RAW ", so every number in this report can be
#   checked by hand instead of trusted blind — the whole reason this script
#   exists is that three separate "green" numbers turned out to be false in
#   one session, and a number nobody can trace back to its rows is exactly how
#   that happens again.
#
# --days N is deliberately narrow in scope: it overrides ONLY the
# ledger-stale window (default LEDGER_STALE_DAYS below). gate-never-blocked
# needs full history for a trustworthy count, so day-filtering it would
# silently hide the very data the condition needs. Deliberate, not an
# oversight.
#
# ---- Calibration outcome (2026-08-26, 45 logged runs over two weeks) ----
# Two scheduled calibration checks ran (08-19, 08-26) under the rule that a
# condition which fires repeatedly without ever leading to an action is itself
# a defect and should be deleted. Three of the original five were deleted:
#   zero-findings-streak: 0 fires in 45 runs, and no run in the ledger has
#     ever reported zero findings, so it could not fire by construction.
#   never-triggered:      fired 9x per run, every time for skills that carry
#     no run-log.sh call at all and therefore can never have an entry. Its one
#     real signal (/ship silent for months) was closed when the German trigger
#     phrases added on 08-11 made /ship fire on 08-21 and 08-22. Restricted to
#     instrumented skills it would be permanently silent.
#   duration-outlier:     0 fires in 45 runs, on 24/45 rows that carry a
#     duration at all; `--start` fires per session rather than per run in
#     delegate/plan-it, so the median was structurally blind.
# The two survivors are below.
LEDGER_STALE_DAYS=7           # "no entry for this repo in the last N days" window
GATE_MIN_RUNS=10              # gated runs a skill needs before "never blocked" means anything
GATE_SKILLS="ship audit"      # the only skills expected to occasionally NOT pass their gate

set +e

LEDGER_FILE="$HOME/.local/state/claude/skill-runs.jsonl"

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

ANOM=0

print_raw() {
  # print_raw <json-array>: dump each row of a JSON array, one per line,
  # only when --raw was passed.
  [ "$RAW" -eq 1 ] || return 0
  printf '%s' "$1" | jq -c '.[]' 2>/dev/null | sed 's/^/  RAW /'
}

# Main checkout, same derivation as run-log.sh's project_path, so a run logged
# from a linked worktree still counts for this repo (learning 2026-09-02).
ROOT=$(git rev-parse --show-toplevel 2>/dev/null)
COMMON=$(git rev-parse --path-format=absolute --git-common-dir 2>/dev/null)
case "$COMMON" in */.git) ROOT="${COMMON%/.git}" ;; esac

# ---- Condition 1: gate-never-blocked ----
# 'ship' or 'audit' logged at least GATE_MIN_RUNS gated runs, but every
# non-empty .gate value was "passed". A gate that never fires may be dead.
# /ship logs `passed-after-rerun` when the marker was missing/stale and the
# audit had to run first: that IS the gate firing, and it counts as evidence
# here because it is not the literal "passed" (learning 2026-08-28: 17 gated
# runs, all "passed", while the gate had in fact blocked-and-rerun several
# times without leaving a trace in the ledger).
# Entries with no .gate logged at all (empty string) are not counted as
# evidence either way. The minimum exists because the 08-26 calibration saw
# this fire on 'ship' after exactly 2 gated runs, where "never blocked" is not
# an observation about the gate, only about the sample size.
for sk in $GATE_SKILLS; do
  if [ -n "$SKILL_FILTER" ] && [ "$SKILL_FILTER" != "$sk" ]; then
    continue
  fi
  GATED=$(printf '%s' "$ALL_JSON" | jq -c --arg sk "$sk" '[.[] | select(.skill == $sk) | select((.gate // "") != "")]')
  N_GATED=$(printf '%s' "$GATED" | jq 'length')
  [ "$N_GATED" -ge "$GATE_MIN_RUNS" ] || continue
  ALL_PASSED=$(printf '%s' "$GATED" | jq '[.[].gate] | all(. == "passed")')
  if [ "$ALL_PASSED" = "true" ]; then
    echo "RUNSTAT gate-never-blocked: skill '$sk' logged $N_GATED gated run(s), 'gate' was never anything but 'passed'"
    print_raw "$GATED"
    ANOM=$((ANOM + 1))
  fi
done

# ---- Condition 2: ledger-stale ----
# No ledger entry for THIS repo in the last $DAYS days, although this repo has
# commits in that window. Scoped to the current repo (project_path match) on
# purpose, since a green ledger from some other project proves nothing about
# this one. The message deliberately states the observation and NOT a cause: both
# calibration checks found the facts correct and the original wording ("logging
# is likely broken") wrong: the real explanation each time was that commits had
# landed here without anyone running an audit.
if [ -n "$ROOT" ]; then
  COMMITS=$(git log --since="${DAYS} days ago" --oneline 2>/dev/null | wc -l | tr -d ' ')
  if [ "${COMMITS:-0}" -gt 0 ]; then
    RECENT=$(printf '%s' "$ALL_JSON" | jq -c --arg root "$ROOT" --argjson days "$DAYS" \
      '(now - ($days * 86400)) as $cutoff | [.[] | select(.project_path == $root) | select((.ts | try fromdateiso8601 catch 0) >= $cutoff)]')
    N_RECENT=$(printf '%s' "$RECENT" | jq 'length')
    if [ "${N_RECENT:-0}" = "0" ]; then
      echo "RUNSTAT ledger-stale: $COMMITS commit(s) landed in $ROOT in the last $DAYS days, but no run was logged for this repo in that window (either no audit ran before those commits, or run-log.sh is not firing here)"
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
