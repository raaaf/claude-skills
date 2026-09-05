#!/usr/bin/env bash
#
# Sums agents, turns and token usage across a session's main transcript plus
# its subagents/*.jsonl files, and prices the result against a fixed table.
#
# Usage: bash run-cost.sh <projects-dir> <session-id> [--json]
#        bash run-cost.sh --latest <projects-dir> [--json]
#
# `--latest <projects-dir>` picks the most recently modified `<session-id>.jsonl`
# directly under <projects-dir> instead of taking a session id — Claude Code
# sessions have no $CLAUDE_TRANSCRIPT_DIR env var to read the current session id
# from, so this is how audit/SKILL.md Phase 4 finds "the session that just ran".
#
# Input: <projects-dir>/<session-id>.jsonl (main transcript) plus
# <projects-dir>/<session-id>/subagents/*.jsonl (one file per dispatched
# agent). Only `type: assistant` lines with a `message.usage` block count.
#
# Output (default): one line, `COST agents=<n> turns=<n> usd=<x.xx>`.
# Output (--json):  a JSON object with the same fields plus a per-model
# breakdown and `unknown_models` (model ids that matched no price-table
# prefix; they count as 0 USD, never abort the run).
#
# bash 3.2 compatible (no declare -A, no readarray). jq required.
set -euo pipefail

if [ "${1:-}" = "--latest" ]; then
  PROJECTS_DIR="${2:?usage: run-cost.sh --latest <projects-dir> [--json]}"
  SESSION_FILE=$(find "$PROJECTS_DIR" -maxdepth 1 -type f -name '*.jsonl' -exec stat -f '%m %N' {} \; 2>/dev/null \
    | sort -rn | head -1 | cut -d' ' -f2-)
  if [ -z "$SESSION_FILE" ]; then
    echo "COST agents=0 turns=0 usd=0.00 (no session found in: $PROJECTS_DIR)"
    exit 0
  fi
  SESSION_ID="$(basename "$SESSION_FILE" .jsonl)"
  JSON_MODE=0
  [ "${3:-}" = "--json" ] && JSON_MODE=1
else
  PROJECTS_DIR="${1:?usage: run-cost.sh <projects-dir> <session-id> [--json]}"
  SESSION_ID="${2:?usage: run-cost.sh <projects-dir> <session-id> [--json]}"
  JSON_MODE=0
  [ "${3:-}" = "--json" ] && JSON_MODE=1
fi

if ! command -v jq >/dev/null 2>&1; then
  echo "COST agents=0 turns=0 usd=0.00 (jq missing)"
  exit 0
fi

MAIN="$PROJECTS_DIR/$SESSION_ID.jsonl"
SUBDIR="$PROJECTS_DIR/$SESSION_ID/subagents"

if [ ! -f "$MAIN" ]; then
  echo "COST agents=0 turns=0 usd=0.00 (main transcript not found: $MAIN)"
  exit 0
fi

# Collect subagent transcript files (each *.jsonl in subagents/ is one
# dispatched agent; the sibling *.meta.json files are not transcripts).
# Indexed array (bash 3.2 has these; only associative arrays are unavailable).
SUB_FILES=()
AGENTS=0
if [ -d "$SUBDIR" ]; then
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    SUB_FILES+=("$f")
    AGENTS=$((AGENTS + 1))
  done < <(find "$SUBDIR" -maxdepth 1 -type f -name "*.jsonl" 2>/dev/null | sort)
fi

# A single API turn can be logged as several JSONL lines (one per content
# block: thinking, tool_use, text), each carrying the SAME message.id and the
# SAME usage totals for the whole turn. Count/sum per unique message.id, or
# a multi-block turn gets its tokens counted 2-3x.
TURNS=$(jq -s '[.[] | select(.type == "assistant") | .message.id] | unique | length' "$MAIN" 2>/dev/null || echo 0)

# USD per million tokens: input / cache-write / cache-read / output.
PRICE_JSON='{
  "claude-fable-5-1": {"input": 10,   "cache_write": 12.5, "cache_read": 0.25, "output": 50},
  "claude-opus-5":    {"input": 5,    "cache_write": 6.25, "cache_read": 0.5,  "output": 25},
  "claude-sonnet-5":  {"input": 2,    "cache_write": 2.5,  "cache_read": 0.2,  "output": 10},
  "claude-haiku-4-5": {"input": 1,    "cache_write": 1.25, "cache_read": 0.1,  "output": 5}
}'

JQ_FILTER='
def prefix($m):
  if   ($m | test("^claude-fable-5-1"))  then "claude-fable-5-1"
  elif ($m | test("^claude-opus-5"))     then "claude-opus-5"
  elif ($m | test("^claude-sonnet-5"))   then "claude-sonnet-5"
  elif ($m | test("^claude-haiku-4-5"))  then "claude-haiku-4-5"
  else "unknown:" + $m
  end;
[ .[] | select(.type == "assistant") | .message // empty | select(.usage != null) ]
| unique_by(.id)
| reduce .[] as $m (
    {};
    (prefix($m.model // "unknown")) as $key
    | .[$key].input        += ($m.usage.input_tokens // 0)
    | .[$key].cache_write  += ($m.usage.cache_creation_input_tokens // 0)
    | .[$key].cache_read   += ($m.usage.cache_read_input_tokens // 0)
    | .[$key].output       += ($m.usage.output_tokens // 0)
  )
| . as $sums
| ($sums | to_entries | map(
    .key as $k | .value as $v
    | ($prices[$k]) as $p
    | if $p == null then 0
      else (($v.input // 0) / 1000000 * $p.input)
           + (($v.cache_write // 0) / 1000000 * $p.cache_write)
           + (($v.cache_read // 0) / 1000000 * $p.cache_read)
           + (($v.output // 0) / 1000000 * $p.output)
      end
  ) | add // 0) as $usd
| ($sums | keys | map(select(startswith("unknown:")) | sub("^unknown:"; ""))) as $unknown_models
| { usd: $usd, models: $sums, unknown_models: $unknown_models }
'

# Feed every file through one jq -s call (all lines, all files, one array).
# bash 3.2 treats an empty array as unbound under `set -u`: guard the
# zero-subagent case instead of expanding "${SUB_FILES[@]}" directly.
if [ "${#SUB_FILES[@]}" -gt 0 ]; then
  RESULT=$(jq -s --argjson prices "$PRICE_JSON" "$JQ_FILTER" "$MAIN" "${SUB_FILES[@]}" 2>/dev/null || echo '{"usd":0,"models":{},"unknown_models":[]}')
else
  RESULT=$(jq -s --argjson prices "$PRICE_JSON" "$JQ_FILTER" "$MAIN" 2>/dev/null || echo '{"usd":0,"models":{},"unknown_models":[]}')
fi

USD=$(printf '%s' "$RESULT" | jq -r '.usd')
# LC_NUMERIC=C: some locales use a comma decimal separator, which makes
# printf reject the dot-separated number jq just emitted.
USD_FMT=$(LC_NUMERIC=C printf '%.2f' "$USD")
UNKNOWN=$(printf '%s' "$RESULT" | jq -r '.unknown_models | join(",")')

if [ "$JSON_MODE" -eq 1 ]; then
  printf '%s' "$RESULT" | jq --argjson agents "$AGENTS" --argjson turns "$TURNS" \
    '. + {agents: $agents, turns: $turns}'
else
  if [ -n "$UNKNOWN" ]; then
    echo "COST agents=$AGENTS turns=$TURNS usd=$USD_FMT unknown_models=$UNKNOWN"
  else
    echo "COST agents=$AGENTS turns=$TURNS usd=$USD_FMT"
  fi
fi
