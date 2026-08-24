#!/usr/bin/env bash
# Deterministic sanity-floor over the triage routing for /audit.
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
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# Guarded source: a missing lib-git-base.sh must not silently kill the floor.
# Without this guard, an unguarded `source` of a missing file leaves
# collect_changed_files undefined, `changed` ends up empty, and every
# dimension looks skippable -- the exact opposite of "fails open".
# shellcheck disable=SC1091
[ -r "$SCRIPT_DIR/lib-git-base.sh" ] && source "$SCRIPT_DIR/lib-git-base.sh"
FRAMEWORK="${1:-}"
# Fall back to literal defaults when lib-git-base.sh was missing above, so the
# floor still routes rather than collapsing to "no dimensions".
DIMS="${AUDIT_DIMS:-architecture security performance code_quality seo a11y typography ui_design ux animation docs_sync copy}"
FE_RE="${FRONTEND_EXT_RE:-\.(blade\.php|html?|vue|tsx?|jsx?|css|scss|sass|less|svelte|astro|swift|kt|kts|dart|xml|storyboard|xib)$}"

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

# Same fail-open contract as the jq checks above, for the same reason: the floor
# has zero information without a working collect_changed_files, and silently
# skipping every dimension is the one outcome this script must never produce.
if ! command -v collect_changed_files >/dev/null 2>&1; then
  echo "ROUTING_RUN=$(echo "$DIMS" | tr ' ' ',')"
  echo "ROUTING_SKIPPED="
  echo "ROUTING_OVERRIDE="
  echo "Routing: lib-git-base.sh fehlt oder collect_changed_files nicht definiert -- Floor faellt offen, alle Dimensionen laufen."
  echo "check-skips.sh: lib-git-base.sh missing or collect_changed_files undefined -- floor cannot derive file signals, falling open (all dimensions run)" >&2
  exit 0
fi

# --- derive file-type signals from git (audit scope: same file set as collect-scope.sh) ---
# Eval fixtures are intentionally-broken TEST DATA, not product code: they must not
# count as a frontend/code signal for the floor (learning 2026-07-07: a fixture
# blade.php force-dispatched a11y/ui/ux/security for nothing).
changed=$(collect_changed_files | grep -vE '(^|/)audit/evals/fixtures/')

match(){ printf '%s\n' "$changed" | grep -qiE "$1"; }

has_frontend=0; match "$FE_RE" && has_frontend=1
# Path-based on purpose: value-only edits to EXISTING lang keys must route
# copy/typography exactly like new keys (learning 2026-08: value-only diffs in
# lang/*.php went unrouted under an earlier key-based check). Any change to a
# matched file sets the signal — do not narrow this to added keys.
has_trans=0;    match '(/lang/.+\.(json|php)$|\.po$|\.pot$|\.arb$|\.strings$|/values[^/]*/strings\.xml$|/locales?/)' && has_trans=1
has_mig=0;      match '(/migrations?/|/migrate/|\.migration\.)' && has_mig=1
has_code=0;     printf '%s\n' "$changed" | grep -qvE '\.(md|txt|json|ya?ml|po|pot|arb|strings|xml|lock|toml|ini|cfg)$' && [ -n "$changed" ] && has_code=1
has_docs=0;     match '\.md$|(^|/)docs/|(^|/)\.env\.example$' && has_docs=1
# Runtime-consumed YAML (Home Assistant automations/scripts, Ansible playbooks,
# k8s manifests, CI workflows) is executing logic, not prose: it has triggers,
# conditions, templates and service calls. has_code excludes *.yaml wholesale, so
# a repo whose entire codebase is YAML used to produce an empty ROUTING_RUN and
# needed a manual override every run (learning 2026-08-19).
has_config_logic=0
match '(^|/)(automations?|scripts?|packages|playbooks|roles|manifests)/.*\.ya?ml$|(^|/)\.github/workflows/.*\.ya?ml$|(^|/)(configuration|scripts|automations|scenes|sensors|binary_sensors|lights|climates|groups|timers|notifies)\.ya?ml$' && has_config_logic=1
has_seo=0;      match '\.(blade\.php|vue|svelte|astro|html?)$|(^|/)routes?/|sitemap(\.[a-zA-Z]+)?$|robots\.txt$' && has_seo=1

is_native=0; case "$FRAMEWORK" in ios|android|react-native|flutter|native) is_native=1;; esac

# floor signal: the condition under which a SKIP of this dim is obviously wrong
floor_signal(){
  case "$1" in
    a11y|ui_design|ux) [ "$has_frontend" = 1 ] && echo "frontend" ;;
    copy|typography)   [ "$has_trans" = 1 ] && echo "translation" ;;
    architecture)      { [ "$has_mig" = 1 ] || [ "$has_config_logic" = 1 ]; } && echo "migration" ;;
    code_quality)      { [ "$has_code" = 1 ] || [ "$has_config_logic" = 1 ]; } && echo "code-changed" ;;
    security)          { [ "$has_code" = 1 ] || [ "$has_config_logic" = 1 ]; } && echo "code-changed" ;;
    docs_sync)         [ "$has_docs" = 1 ] && echo "docs" ;;
    seo)               [ "$has_seo" = 1 ] && echo "template" ;;
    performance)        { [ "$has_code" = 1 ] || [ "$has_mig" = 1 ] || [ "$has_config_logic" = 1 ]; } && echo "code-changed" ;;
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

# Every skip must carry a logged reason; a "no-reason" skip is itself an
# anomaly (learning backlog 2026-08): surface it instead of letting the
# dimension vanish silently.
case "$skip_csv" in
  *":no-reason"*) echo "WARN: Dimension-Skip ohne protokollierten Grund (no-reason) -- als Anomalie behandeln, Skip-Quelle pruefen." ;;
esac
