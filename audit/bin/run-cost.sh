#!/usr/bin/env bash
# Claude transcript accounting, bash 3.2 and jq.
# Usage: run-cost.sh <projects-dir> <session-id> [--since <epoch>] [--json]
#        run-cost.sh --latest <projects-dir> [--since <epoch>] [--json]
#        run-cost.sh --window <projects-root> <since-epoch> [--json]
# Deduplicate message IDs across main and recursive agent transcripts, taking
# the highest-output usage snapshot. Unknown models retain tokens, USD is null.
# --since keeps only messages whose transcript timestamp is >= the epoch.
# --window sums every session transcript (main + agent) under <projects-root>/*/
# for messages >= since: `WINDOW sessions=<n> usd=<x.xx>`, json `{sessions, usd}`.
set -euo pipefail
JSON_MODE=0; SINCE=0; MODE=session; P1=""; P2=""; NPOS=0
while [ $# -gt 0 ]; do
  case "$1" in
    --json) JSON_MODE=1 ;;
    --since) SINCE="${2:-}"; [ $# -gt 1 ] && shift ;;
    --latest) MODE=latest ;;
    --window) MODE=window ;;
    *) NPOS=$((NPOS + 1)); if [ "$NPOS" -eq 1 ]; then P1="$1"; elif [ "$NPOS" -eq 2 ]; then P2="$1"; fi ;;
  esac
  shift
done
unavailable() {
  if [ "$JSON_MODE" -eq 1 ] && [ "$MODE" = window ]; then
    printf '{"status":"unavailable","sessions":null,"usd":null,"reason":"%s"}\n' "$1"
  elif [ "$JSON_MODE" -eq 1 ]; then
    printf '{"status":"unavailable","usd":null,"agents":null,"turns":null,"models":{},"unknown_models":[],"reason":"%s"}\n' "$1"
  elif [ "$MODE" = window ]; then
    printf 'WINDOW sessions=unknown usd=unknown status=unavailable reason=%s\n' "$1"
  else
    printf 'COST agents=unknown turns=unknown usd=unknown status=unavailable reason=%s\n' "$1"
  fi
  exit 1
}
command -v jq >/dev/null 2>&1 || unavailable jq_missing

# Prices per MTok. Checked 2026-10-03 against Claude Code /usage of one session:
# Opus 5.5 (456 in, 137.1k out, 62.8M cache read, 638.8k cache write) = 20.41 USD,
# Sonnet 5.5 (296.0k in, 2.1M out, 247.0M read, 18.2M write) = 143.78 USD.
# Claude Code uses the 1h cache TTL, so cache_write = 2 x input for every model.
PRICE_JSON='{
  "claude-fable-5-1": {"input": 10,   "cache_write": 20,   "cache_read": 0.25, "output": 50},
  "claude-opus-5-5":  {"input": 4,    "cache_write": 8,    "cache_read": 0.2,  "output": 20},
  "claude-opus-5":    {"input": 5,    "cache_write": 10,   "cache_read": 0.5,  "output": 25},
  "claude-sonnet-5":  {"input": 2,    "cache_write": 4,    "cache_read": 0.2,  "output": 10},
  "claude-haiku-4-5": {"input": 1,    "cache_write": 2,    "cache_read": 0.1,  "output": 5}
}'

JQ_DEFS='
def prefix($m):
  if   ($m | test("^claude-fable-5-1")) then "claude-fable-5-1"
  elif ($m | test("^claude-opus-5-5")) then "claude-opus-5-5"
  elif ($m | test("^claude-opus-5")) then "claude-opus-5"
  elif ($m | test("^claude-sonnet-5")) then "claude-sonnet-5"
  elif ($m | test("^claude-haiku-4-5")) then "claude-haiku-4-5"
  else "unknown:" + $m end;
def ts_epoch: try (.timestamp | sub("\\.[0-9]+"; "") | fromdateiso8601) catch 0;
def sum_models:
  reduce .[] as $m ({};
    (prefix($m.model)) as $key
    | .[$key].input += $m.usage.input_tokens
    | .[$key].cache_write += ($m.usage.cache_creation_input_tokens // 0)
    | .[$key].cache_read += ($m.usage.cache_read_input_tokens // 0)
    | .[$key].output += $m.usage.output_tokens);
def known_usd($prices):
  to_entries | map(.key as $k | .value as $v | $prices[$k] as $p
    | if $p == null then 0 else
      ($v.input * $p.input + $v.cache_write * $p.cache_write +
       $v.cache_read * $p.cache_read + $v.output * $p.output) / 1000000 end) | add // 0;
'

if [ "$MODE" = window ]; then
  ROOT="${P1:?usage: run-cost.sh --window <projects-root> <since-epoch> [--json]}"
  SINCE="${P2:?usage: run-cost.sh --window <projects-root> <since-epoch> [--json]}"
  case "$SINCE" in ''|*[!0-9]*) unavailable bad_since ;; esac
  [ -d "$ROOT" ] || unavailable projects_root_missing
  MMIN=$(( ($(date +%s) - SINCE) / 60 + 2 ))   # mtime prefilter: older files cannot hold newer messages
  LIST=$(mktemp "${TMPDIR:-/tmp}/run-cost-list.XXXXXX"); trap 'rm -f "$LIST"' EXIT
  find "$ROOT" -mindepth 2 -type f -name '*.jsonl' -mmin "-$MMIN" ! -path '*/journal/*' ! -path '*/meta/*' -print0 2>/dev/null > "$LIST" || true
  SESSIONS=$(tr '\0' '\n' < "$LIST" | grep -vc '/agent-[^/]*\.jsonl$' || true)   # main transcripts only
  WIN_FILTER="$JQ_DEFS"'
  [.[] | select(.id | type == "string") | select(.model != "<synthetic>")
   | select((.usage.input_tokens | type) == "number" and (.usage.output_tokens | type) == "number")]
  | group_by(.id) | map(sort_by(.usage.output_tokens) | last)
  | sum_models | known_usd($prices)'
  USD=$(xargs -0 jq -R -c --argjson since "$SINCE" "$JQ_DEFS"'
    fromjson? | select(type == "object" and .type == "assistant" and (.message.usage | type) == "object")
    | select(ts_epoch >= $since) | .message | {id, model, usage}' < "$LIST" 2>/dev/null \
    | jq -s --argjson prices "$PRICE_JSON" "$WIN_FILTER" 2>/dev/null) || unavailable invalid_transcript_usage
  [ -n "$USD" ] || USD=0
  USD_FMT=$(LC_NUMERIC=C printf '%.2f' "$USD")
  if [ "$JSON_MODE" -eq 1 ]; then
    printf '{"sessions":%s,"usd":%s}\n' "${SESSIONS:-0}" "$USD_FMT"
  else
    printf 'WINDOW sessions=%s usd=%s\n' "${SESSIONS:-0}" "$USD_FMT"
  fi
  exit 0
fi

case "$SINCE" in ''|*[!0-9]*) unavailable bad_since ;; esac
if [ "$MODE" = latest ]; then
  PROJECTS_DIR="${P1:?usage: run-cost.sh --latest <projects-dir> [--json]}"
  SESSION_FILE=""
  while IFS= read -r f; do
    if [ -z "$SESSION_FILE" ] || [ "$f" -nt "$SESSION_FILE" ]; then SESSION_FILE="$f"; fi
  done < <(find "$PROJECTS_DIR" -maxdepth 1 -type f -name '*.jsonl' 2>/dev/null)
  [ -n "$SESSION_FILE" ] || unavailable transcript_missing
  SESSION_ID="$(basename "$SESSION_FILE" .jsonl)"
else
  PROJECTS_DIR="${P1:?usage: run-cost.sh <projects-dir> <session-id> [--json]}"
  SESSION_ID="${P2:?usage: run-cost.sh <projects-dir> <session-id> [--json]}"
fi
MAIN="$PROJECTS_DIR/$SESSION_ID.jsonl"
[ -s "$MAIN" ] || unavailable transcript_missing_or_empty
FILES=("$MAIN")
AGENTS=0
if [ -d "$PROJECTS_DIR/$SESSION_ID" ]; then
  while IFS= read -r f; do
    FILES+=("$f")
    AGENTS=$((AGENTS + 1))
  done < <(find "$PROJECTS_DIR/$SESSION_ID" -type f -name 'agent-*.jsonl' ! -path '*/journal/*' ! -path '*/meta/*' | sort)
fi

JQ_FILTER="$JQ_DEFS"'
def valid_number: type == "number" and . >= 0;
def valid_usage:
  (.usage | type == "object") and
  (.usage.input_tokens | valid_number) and (.usage.output_tokens | valid_number) and
  (.usage.cache_creation_input_tokens // 0 | valid_number) and
  (.usage.cache_read_input_tokens // 0 | valid_number);
[.[] | select(.type == "assistant") | select($since == 0 or ts_epoch >= $since) | .message
 | select(.model != "<synthetic>" or
     ([.usage.input_tokens // 0, .usage.output_tokens // 0,
       .usage.cache_creation_input_tokens // 0, .usage.cache_read_input_tokens // 0] | add) != 0)]
| if length == 0 and $since == 0 then error("no API usage") else . end
| if any(.[]; (.id | type) != "string" or .id == "") then error("missing message id") else . end
| group_by(.id)
| map(sort_by([if valid_usage then 1 else 0 end,
               if (.usage.output_tokens | type) == "number" then .usage.output_tokens else -1 end]) | last)
| if any(.[]; (valid_usage | not) or (.model | type) != "string" or .model == "")
  then error("invalid usage or model") else . end
| . as $messages
| (sum_models) as $sums
| ($sums | keys | map(select(startswith("unknown:")) | sub("^unknown:"; ""))) as $unknown
| ($sums | known_usd($prices)) as $known
| {status: (if ($unknown | length) == 0 then "complete" else "unavailable" end),
   usd: (if ($unknown | length) == 0 then $known else null end),
   known_usd: $known, models: $sums, unknown_models: $unknown,
   turns: ($messages | length), agents: $agents}
'
RESULT=$(jq -s --argjson prices "$PRICE_JSON" --argjson agents "$AGENTS" --argjson since "$SINCE" "$JQ_FILTER" "${FILES[@]}" 2>/dev/null) || unavailable invalid_transcript_usage
if [ "$JSON_MODE" -eq 1 ]; then
  printf '%s\n' "$RESULT"
else
  USD=$(printf '%s' "$RESULT" | jq -r '.usd')
  if [ "$USD" = null ]; then USD_FMT=unknown; else USD_FMT=$(LC_NUMERIC=C printf '%.2f' "$USD"); fi
  TURNS=$(printf '%s' "$RESULT" | jq -r '.turns')
  STATUS=$(printf '%s' "$RESULT" | jq -r '.status')
  UNKNOWN=$(printf '%s' "$RESULT" | jq -r '.unknown_models | join(",")')
  printf 'COST agents=%s turns=%s usd=%s status=%s unknown_models=%s\n' "$AGENTS" "$TURNS" "$USD_FMT" "$STATUS" "$UNKNOWN"
fi
