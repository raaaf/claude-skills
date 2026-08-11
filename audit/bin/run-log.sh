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
# enough on macOS/Linux, but only if it happens in one call.
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
while [ $# -gt 0 ]; do
  case "$1" in
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

# --skill and --outcome are the only required fields. Missing either means
# there is nothing meaningful to log; skip the write, never error.
[ -n "$SKILL" ] || exit 0
[ -n "$OUTCOME" ] || exit 0

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
