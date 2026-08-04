#!/usr/bin/env bash
# Deterministic sanity-floor over the (haiku) triage routing for /audit.
#
# The triage agent proposes relevance.{dim}.run; the cheapest model decides what
# every expensive worker sees. This script does NOT trust that: it derives file-type
# signals straight from git and forces obviously-wrong skips back on (Bash decides,
# not the LLM), then emits a human Routing line so every skip is visible.
#
# Input:  triage JSON on stdin (the object the triage agent returned).
# Arg 1:  FRAMEWORK (optional, e.g. ios/android/react-native/flutter/laravel/...).
# Output (stdout), parseable + human:
#   ROUTING_RUN=architecture,security,...     effective dims to dispatch (triage-run UNION floor)
#   ROUTING_SKIPPED=performance:reason;ux:...  still off after the floor (with triage reason)
#   ROUTING_OVERRIDE=a11y:frontend;ux:frontend dims the floor forced back on (dim:signal)
#   Routing: lief [...]; uebersprungen [...]; Floor-Override [...]
#
# Input normalization: markdown code fences are stripped (LLMs wrap JSON), and
# EMPTY input means "triage did not run" (idle/FLOOR_ONLY) -- that is a normal
# mode, not an error: the floor decides alone against '{}'.
# Fails open (all dims run) ONLY for genuinely missing jq or JSON that is still
# unparseable after normalization, with distinct messages -- a combined message
# caused months of false "jq fehlt" reports while /usr/bin/jq existed all along
# (learning 2026-08-01: the real trigger was empty/fenced triage output).
# bash 3.2 safe (no set -u, no associative arrays).
set -o pipefail
FRAMEWORK="${1:-}"
DIMS="architecture security performance code_quality seo a11y typography ui_design ux animation docs_sync copy"

json=$(cat)
# Strip markdown code fences (```json ... ```) that LLM triage output may carry.
json=$(printf '%s\n' "$json" | sed '/^[[:space:]]*```/d')
# Empty input = triage skipped or idle (FLOOR_ONLY): floor-only routing, not fail-open.
floor_only=0
[ -z "$(printf '%s' "$json" | tr -d '[:space:]')" ] && { json='{}'; floor_only=1; }

if ! command -v jq >/dev/null 2>&1; then
  echo "ROUTING_RUN=$(echo "$DIMS" | tr ' ' ',')"
  echo "ROUTING_SKIPPED="
  echo "ROUTING_OVERRIDE="
  echo "Routing: jq nicht gefunden (PATH=$PATH) -- Floor faellt offen, alle Dimensionen laufen."
  exit 0
fi
if ! printf '%s' "$json" | jq -e . >/dev/null 2>&1; then
  echo "ROUTING_RUN=$(echo "$DIMS" | tr ' ' ',')"
  echo "ROUTING_SKIPPED="
  echo "ROUTING_OVERRIDE="
  echo "Routing: Triage-JSON unparseable (jq vorhanden) -- Floor faellt offen, alle Dimensionen laufen."
  exit 0
fi

# --- derive file-type signals from git (audit scope: working tree + staged + untracked + unpushed) ---
# Eval fixtures are intentionally-broken TEST DATA, not product code: they must not
# count as a frontend/code signal for the floor (learning 2026-07-07: a fixture
# blade.php force-dispatched a11y/ui/ux/security for nothing).
changed=$( {
  git diff --name-only HEAD 2>/dev/null
  git diff --name-only --cached 2>/dev/null
  git ls-files --others --exclude-standard 2>/dev/null
  up=$(git rev-parse --abbrev-ref --symbolic-full-name '@{u}' 2>/dev/null)
  [ -n "$up" ] && git diff --name-only "${up}...HEAD" 2>/dev/null
} | sort -u | grep -vE '(^|/)audit/evals/fixtures/' )

match(){ printf '%s\n' "$changed" | grep -qiE "$1"; }

has_frontend=0; match '\.(blade\.php|vue|jsx|tsx|svelte|astro|html?|css|scss|sass|less|swift|kt|kts|dart)$' && has_frontend=1
has_trans=0;    match '(/lang/.+\.(json|php)$|\.po$|\.pot$|\.arb$|\.strings$|/values[^/]*/strings\.xml$|/locales?/)' && has_trans=1
has_mig=0;      match '(/migrations?/|/migrate/|\.migration\.)' && has_mig=1
has_code=0;     printf '%s\n' "$changed" | grep -qvE '\.(md|txt|json|ya?ml|po|pot|arb|strings|xml|lock|toml|ini|cfg)$' && [ -n "$changed" ] && has_code=1
has_docs=0;     match '\.md$|(^|/)docs/|(^|/)\.env\.example$' && has_docs=1
has_seo=0;      match '\.(blade\.php|vue|svelte|astro|html?)$|(^|/)routes?/|sitemap(\.[a-zA-Z]+)?$|robots\.txt$' && has_seo=1

is_native=0; case "$FRAMEWORK" in ios|android|react-native|flutter|native) is_native=1;; esac

# floor signal: the condition under which a SKIP of this dim is obviously wrong
floor_signal(){
  case "$1" in
    a11y|ui_design|ux) [ "$has_frontend" = 1 ] && echo "frontend" ;;
    copy|typography)   [ "$has_trans" = 1 ] && echo "translation" ;;
    architecture)      [ "$has_mig" = 1 ] && echo "migration" ;;
    code_quality)      [ "$has_code" = 1 ] && echo "code-changed" ;;
    security)          [ "$has_code" = 1 ] && echo "code-changed" ;;
    docs_sync)         [ "$has_docs" = 1 ] && echo "docs" ;;
    seo)               [ "$has_seo" = 1 ] && echo "template" ;;
    performance)        { [ "$has_code" = 1 ] || [ "$has_mig" = 1 ]; } && echo "code-changed" ;;
    animation)          [ "$has_frontend" = 1 ] && echo "frontend" ;;
  esac
}

app(){ # app <csv> <item> [sep]
  local sep="${3:-,}"
  if [ -z "$1" ]; then printf '%s' "$2"; else printf '%s%s%s' "$1" "$sep" "$2"; fi
}

run_csv=""; skip_csv=""; over_csv=""
for d in $DIMS; do
  r=$(printf '%s' "$json" | jq -r --arg d "$d" '.relevance[$d].run // false')
  if [ "$r" = "true" ]; then
    run_csv=$(app "$run_csv" "$d")
  else
    sig=$(floor_signal "$d")
    [ "$d" = "seo" ] && [ "$is_native" = 1 ] && sig=""   # never force seo on native
    if [ -n "$sig" ]; then
      run_csv=$(app "$run_csv" "$d")
      over_csv=$(app "$over_csv" "$d:$sig" ";")
    else
      reason=$(printf '%s' "$json" | jq -r --arg d "$d" '.relevance[$d].reason // "no-reason"')
      skip_csv=$(app "$skip_csv" "$d:$reason" ";")
    fi
  fi
done

# No triage AND no git signal at all = zero information -> fail open rather
# than silently skipping every dimension.
if [ "$floor_only" = 1 ] && [ -z "$run_csv" ]; then
  echo "ROUTING_RUN=$(echo "$DIMS" | tr ' ' ',')"
  echo "ROUTING_SKIPPED="
  echo "ROUTING_OVERRIDE="
  echo "Routing: Triage leer und keine git-Signale -- Floor faellt offen, alle Dimensionen laufen."
  exit 0
fi

echo "ROUTING_RUN=$run_csv"
echo "ROUTING_SKIPPED=$skip_csv"
echo "ROUTING_OVERRIDE=$over_csv"

line="Routing: lief [$run_csv]"
[ -n "$skip_csv" ] && line="$line; uebersprungen [$skip_csv]"
[ -n "$over_csv" ] && line="$line; Floor-Override [$over_csv]"
echo "$line"
