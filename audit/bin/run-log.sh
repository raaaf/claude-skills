#!/usr/bin/env bash
#
# run-log.sh — append one JSON line per skill run to the personal run ledger.
#
# The ledger lives at $HOME/.claude/skill-runs.jsonl, deliberately NOT inside
# any repo: project paths are personal (absolute filesystem paths) and this
# repo (claude-skills) is public on GitHub. Never write the ledger under a
# repo directory.
#
# Usage:
#   bash run-log.sh --start --skill <name>
#   bash run-log.sh --skill <name> --outcome <str> [--duration <sec>] \
#       [--counts k=v,k=v,...] [--gate <str>] [--note <str>]
#
# Derived fields (not passed in): ts, project, project_path, head, branch.
# Outside a git repo these are empty strings, never a failure.
#
# --counts parses comma-separated k=v pairs into a nested JSON object.
# A value matching an integer/decimal pattern becomes a JSON number, anything
# else stays a JSON string (e.g. --counts critical=0,important=3,rounds=2).
#
# Duration across separate shell invocations: each SKILL.md Bash block runs
# in a fresh shell, so a `START=$(date +%s)` set in an early phase does not
# survive to the terminal call. `--start --skill <name>` instead touches a
# marker file keyed by skill name AND cwd (same hash pattern as the existing
# `/tmp/claude-audit-in-progress-*` family: `pwd | md5`, WITH trailing
# newline — that family means "a run of this skill is happening in this
# directory", which is exactly this marker's semantics too; the OTHER family,
# `/tmp/claude-audit-passed-*`, hashes cwd WITHOUT a trailing newline and
# means something different ("push is currently allowed"). Do not blend the
# two conventions). The terminal call (this script without --start) then
# reads that marker's mtime, derives elapsed seconds, and deletes the marker
# — but only when the caller did not pass an explicit `--duration`, which
# always wins (keeps the existing hand-written form working). A marker older
# than 3 hours (10800s) is treated as abandoned and discarded without
# producing a duration — same staleness ceiling `pre-compact.sh` already uses
# for the sibling `-in-progress-` marker, chosen for the same reason: any
# single real run legitimately finishes well inside a workday, so a marker
# older than that is a crashed/abandoned session, not a slow run, and letting
# it through would poison the ledger with a fictional multi-hour (or
# multi-day) duration that then corrupts the median `duration-outlier`
# compares against. No marker, or a stale one: `duration_s` is omitted
# exactly as before `--start` existed, never invented.
#
# THIS SCRIPT MUST NEVER BREAK THE CALLING SKILL. Every failure path — jq
# missing, not a git repo, $HOME/.claude not writable, malformed arguments —
# exits 0 silently and simply skips the write. A logging helper that can fail
# a skill run is worse than no logging at all; this is the one script in the
# repo where "fail silently" is the deliberately correct behaviour, not a
# shortcut. Callers must never check this script's exit code as a signal.
#
# Concurrency: several skills can log at once. The whole JSON line is built
# in memory first and appended with a single `>>`, never written
# incrementally — a single `write()` under the pipe buffer size is atomic
# enough on macOS/Linux, but only if it happens in one call. Start markers
# are keyed by skill name AND cwd hash, so two projects (or two different
# skills in the same project) running in parallel never share a marker.
set +e

LEDGER_DIR="$HOME/.claude"
LEDGER_FILE="$LEDGER_DIR/skill-runs.jsonl"

command -v jq >/dev/null 2>&1 || exit 0

# ---- Argument parsing (safe against a flag missing its value: never uses
# `shift 2`, which errors and can stall the loop when the value is absent) ----
SKILL=""
OUTCOME=""
DURATION_RAW=""
COUNTS_RAW=""
GATE=""
NOTE=""
START_MODE=0
while [ $# -gt 0 ]; do
  case "$1" in
    --start) START_MODE=1 ;;
    --skill) SKILL="${2:-}"; shift ;;
    --outcome) OUTCOME="${2:-}"; shift ;;
    --duration) DURATION_RAW="${2:-}"; shift ;;
    --counts) COUNTS_RAW="${2:-}"; shift ;;
    --gate) GATE="${2:-}"; shift ;;
    --note) NOTE="${2:-}"; shift ;;
    *) : ;;
  esac
  shift
done

# --skill is required in every mode; nothing meaningful to do without it.
[ -n "$SKILL" ] || exit 0

# Marker path for the --start / duration-derivation pair: skill name +
# cwd hash, under $TMPDIR (falls back to /tmp). Skill name is sanitized
# defensively even though every real caller passes a plain lowercase-hyphen
# identifier (audit, full-audit, plan-it, design-audit, delegate, ship).
_runlog_marker() {
  _hash=$(pwd | md5 2>/dev/null || pwd | md5sum 2>/dev/null | cut -d' ' -f1)
  [ -n "$_hash" ] || return 1
  _skill_safe=$(printf '%s' "$SKILL" | tr -c 'A-Za-z0-9_-' '_')
  printf '%s/claude-runlog-start-%s-%s' "${TMPDIR:-/tmp}" "$_skill_safe" "$_hash"
}

if [ "$START_MODE" = "1" ]; then
  MARKER=$(_runlog_marker) || exit 0
  mkdir -p "${TMPDIR:-/tmp}" 2>/dev/null
  touch "$MARKER" 2>/dev/null
  exit 0
fi

# --outcome is required for the terminal (logging) call.
[ -n "$OUTCOME" ] || exit 0

# Derive duration from the start marker only when the caller did not pass
# an explicit --duration — explicit always wins. Cleans the marker up
# either way once a terminal call reaches this point, so an abandoned
# marker never survives past the next real run of this skill in this dir.
if [ -z "$DURATION_RAW" ]; then
  MARKER=$(_runlog_marker)
  if [ -n "$MARKER" ] && [ -f "$MARKER" ]; then
    MTIME=$(stat -f%m "$MARKER" 2>/dev/null || stat -c%Y "$MARKER" 2>/dev/null || echo 0)
    NOW=$(date +%s 2>/dev/null || echo 0)
    case "$MTIME" in ''|*[!0-9]*) MTIME=0 ;; esac
    case "$NOW" in ''|*[!0-9]*) NOW=0 ;; esac
    if [ "$MTIME" -gt 0 ] && [ "$NOW" -gt 0 ]; then
      AGE=$(( NOW - MTIME ))
      if [ "$AGE" -ge 0 ] && [ "$AGE" -lt 10800 ]; then
        DURATION_RAW="$AGE"
      fi
    fi
    rm -f "$MARKER" 2>/dev/null
  fi
fi

TS=$(date -u +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null) || exit 0

TOPLEVEL=$(git rev-parse --show-toplevel 2>/dev/null)
if [ -n "$TOPLEVEL" ]; then
  PROJECT=$(basename "$TOPLEVEL")
  HEAD=$(git -C "$TOPLEVEL" rev-parse --short HEAD 2>/dev/null)
  BRANCH=$(git -C "$TOPLEVEL" rev-parse --abbrev-ref HEAD 2>/dev/null)
else
  PROJECT=""
  TOPLEVEL=""
  HEAD=""
  BRANCH=""
fi

LINE=$(jq -n -c \
  --arg ts "$TS" \
  --arg skill "$SKILL" \
  --arg project "$PROJECT" \
  --arg project_path "$TOPLEVEL" \
  --arg head "$HEAD" \
  --arg branch "$BRANCH" \
  --arg outcome "$OUTCOME" \
  --arg gate "$GATE" \
  --arg note "$NOTE" \
  --arg counts_raw "$COUNTS_RAW" \
  --arg duration_raw "$DURATION_RAW" \
  '
  ($duration_raw | if test("^[0-9]+(\\.[0-9]+)?$") then tonumber else null end) as $duration
  |
  ($counts_raw
    | if . == "" then {}
      else
        split(",")
        | map(select(length > 0))
        | map(capture("^(?<k>[^=]+)=(?<v>.*)$"))
        | map({(.k): (.v | if test("^-?[0-9]+(\\.[0-9]+)?$") then tonumber else . end)})
        | add // {}
      end
  ) as $counts
  |
  {
    ts: $ts,
    skill: $skill,
    project: $project,
    project_path: $project_path,
    head: $head,
    branch: $branch,
    duration_s: $duration,
    outcome: $outcome,
    counts: $counts,
    gate: $gate,
    note: $note
  }
  | if .duration_s == null then del(.duration_s) else . end
  ' 2>/dev/null)

[ -n "$LINE" ] || exit 0

mkdir -p "$LEDGER_DIR" 2>/dev/null || exit 0
[ -w "$LEDGER_DIR" ] || exit 0

printf '%s\n' "$LINE" >> "$LEDGER_FILE" 2>/dev/null

exit 0
