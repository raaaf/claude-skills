#!/usr/bin/env bash
#
# Deterministic diff profile for the audit start question (Phase 1.5, decided 2026-10-03): which kinds of
# files changed, which optional dimensions look worthwhile, and the three tiers built from that
# (Guenstig / Gruendlich / Alles) with a rough cost. No LLM, no network. bash 3.2 compatible.
#
# Usage: printf '%s\n' "$ALLE_DATEIEN" | bash diff-profile.sh [repo-root]
#   stdin  the scope file list (repo-root-relative, one per line)
#   env    DIFF_SIZE_RESULT (SMALL|OK|LARGE|HUGE; else diff-size-gate.sh runs in the root),
#          STRIPE_FILES (newline list; with the changed set it decides the payments trigger), PLATFORM
# Output: key=value lines, no spaces around "=":
#   DIFF_SIZE, FILES_<TOTAL|BACKEND|FRONTEND|VIEW|LANG|MIGRATION|DOCS|TEST|CONFIG|API|OTHER>, QUERY_FILES, LOOP_FILES,
#   SENSITIVE_COUNT, SENSITIVE_PATHS (comma list), PAYMENTS, SEO_RELEVANT,
#   SUGGEST_<dim>=yes|no with REASON_<dim>=<short reason> for the ten non-gate dimensions, SUGGEST_COUNT,
#   TIER_GUENSTIG / TIER_GRUENDLICH / TIER_ALLES (comma lists, payments NOT included: the Phase 1.5 block adds it),
#   COST_GUENSTIG / COST_GRUENDLICH / COST_ALLES (rough weighted M tokens, payments included),
#   COST_<tier>_PCT (share of the weekly budget, one decimal), RECOMMENDED.
#   env USAGE_LIMITS_CONF overrides ~/.claude/usage-limits.conf (WEEK_BUDGET_USD, default 2600).
#
# Cost model (measured 2026-10-02: 8.5-14.4 M per gate run incl. /code-review): the Guenstig base is
# SMALL 8, OK 12, LARGE/HUGE 18 M; every dimension beyond the three gate dimensions adds 1.5 M on a SMALL
# diff, 3 M on a larger one. LARGE/HUGE scale with the file count N instead: base max(18, 0.15 N) M, per
# added dimension max(3, 0.04 N) M (2026-10-03: zeit Gruendlich on a 140-file HUGE diff cost ~78 M, ~3.5% of
# the week, against a flat 48 M estimate). PCT = M x 1.2 USD / WEEK_BUDGET_USD (1 weighted M ~ 1.2 USD).
# A rough estimate, not a measurement. LARGE/HUGE always recommends GUENSTIG.
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
export AUDIT_BIN="$SCRIPT_DIR"
# shellcheck source=lib-orchestrator.sh
. "$SCRIPT_DIR/lib-orchestrator.sh"
. "$SCRIPT_DIR/lib-git-base.sh"

ROOT="${1:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
CHANGED=$(sed '/^[[:space:]]*$/d' | sort -u)

TEST_RE='(^|/)(tests?|spec|__tests__)/|Test\.php$|\.(test|spec)\.'
MIGRATION_RE='(^|/)migrations?/'
DOCS_RE='\.(md|mdx|rst|txt|adoc)$|^docs?/'
LANG_RE='(^|/)(lang|locales?|i18n|translations?)/|\.(po|xliff|strings|stringsdict)$'
CONFIG_RE='(^|/)config/|\.(ya?ml|toml|ini)$|(^|/)(package|composer|tsconfig)[^/]*\.json$|(^|/)composer\.lock$|(^|/)Dockerfile|(^|/)\.github/'
API_RE='(^|/)routes?/|(^|/)(openapi|swagger)[^/]*\.(ya?ml|json)$|\.graphql$'
BACKEND_PREFIX_RE='^(backend|server|api|cmd|internal|worker|workers|functions|lambda|app/(Http|Models|Services|Jobs|Actions))/'
BACKEND_EXT_RE='\.(php|py|rb|go|rs|java|cs|ex|exs|scala|sql)$'
VIEW_RE='\.(blade\.php|html?|vue|tsx|jsx|svelte|astro|css|scss|sass|less|styl|storyboard|xib)$|(View|Screen)\.(swift|kt)$'
QUERY_RE='->(where|whereHas|whereIn|orWhere|join|leftJoin|groupBy|orderBy|pluck|paginate|with|withCount|selectRaw|whereRaw)\(|::(where|query|with|all|find|findOrFail|create|firstOrCreate|updateOrCreate)\(|DB::|\b(SELECT|INSERT INTO|UPDATE|DELETE FROM)\b[^;]*\b(FROM|SET|VALUES)\b|\.(objects\.(filter|all|get)|findMany|findAll|createQueryBuilder)\('
LOOP_RE='->(each|chunk|chunkById|reduce|flatMap)\(|\.(forEach|reduce|flatMap)\('

n_backend=0; n_frontend=0; n_view=0; n_lang=0; n_migration=0; n_docs=0; n_test=0; n_config=0; n_api=0; n_other=0
n_total=0; n_query=0; n_loop=0
FE_RE=$(orch_frontend_ext_re)
while IFS= read -r p; do
  [ -n "$p" ] || continue
  n_total=$((n_total + 1))
  printf '%s\n' "$p" | grep -Eq "$API_RE" && n_api=$((n_api + 1))
  if printf '%s\n' "$p" | grep -Eq "$TEST_RE"; then n_test=$((n_test + 1)); continue; fi
  if printf '%s\n' "$p" | grep -Eq "$MIGRATION_RE"; then n_migration=$((n_migration + 1)); continue; fi
  if printf '%s\n' "$p" | grep -Eq "$DOCS_RE"; then n_docs=$((n_docs + 1)); continue; fi
  if printf '%s\n' "$p" | grep -Eq "$LANG_RE"; then n_lang=$((n_lang + 1)); continue; fi
  if printf '%s\n' "$p" | grep -Eq "$CONFIG_RE"; then n_config=$((n_config + 1)); continue; fi
  if printf '%s\n' "$p" | grep -Eq "$VIEW_RE"; then n_view=$((n_view + 1)); n_frontend=$((n_frontend + 1))
  elif printf '%s\n' "$p" | grep -Eq "$BACKEND_PREFIX_RE|$BACKEND_EXT_RE"; then n_backend=$((n_backend + 1))
  elif printf '%s\n' "$p" | grep -Eq "$FE_RE"; then n_frontend=$((n_frontend + 1))
  else n_other=$((n_other + 1)); continue; fi
  if [ -f "$ROOT/$p" ]; then
    grep -Eq "$QUERY_RE" "$ROOT/$p" 2>/dev/null && n_query=$((n_query + 1))
    grep -Eq "$LOOP_RE" "$ROOT/$p" 2>/dev/null && n_loop=$((n_loop + 1))
  fi
done <<EOF
$CHANGED
EOF

size="${DIFF_SIZE_RESULT:-}"
[ -n "$size" ] || size=$(cd "$ROOT" && bash "$SCRIPT_DIR/diff-size-gate.sh" 2>/dev/null | sed -n 's/^DIFF_SIZE_RESULT=//p')
[ -n "$size" ] || size=OK

sensitive=$(orch_sensitive_paths "$CHANGED")
n_sensitive=$(printf '%s\n' "$sensitive" | grep -c . || true)
payments=no
[ -n "${STRIPE_FILES:-}" ] && [ -n "$(orch_payments_touched "$CHANGED" "$STRIPE_FILES")" ] && payments=yes
seo_rel=$(orch_seo_relevant "$CHANGED" "$ROOT" 2>/dev/null)

# suggest <dim> <yes|no> <reason>
SUGGESTED=""
suggest() {
  printf 'SUGGEST_%s=%s\nREASON_%s=%s\n' "$1" "$2" "$1" "$3"
  [ "$2" = yes ] && SUGGESTED="${SUGGESTED:+$SUGGESTED,}$1"
  return 0
}
yn() { [ "$1" -gt 0 ] && echo yes || echo no; }

echo "DIFF_SIZE=$size"
echo "FILES_TOTAL=$n_total"; echo "FILES_BACKEND=$n_backend"; echo "FILES_FRONTEND=$n_frontend"; echo "FILES_VIEW=$n_view"
echo "FILES_LANG=$n_lang"; echo "FILES_MIGRATION=$n_migration"; echo "FILES_DOCS=$n_docs"; echo "FILES_TEST=$n_test"
echo "FILES_CONFIG=$n_config"; echo "FILES_API=$n_api"; echo "FILES_OTHER=$n_other"
echo "QUERY_FILES=$n_query"; echo "LOOP_FILES=$n_loop"
echo "SENSITIVE_COUNT=$n_sensitive"
echo "SENSITIVE_PATHS=$(printf '%s\n' "$sensitive" | sed '/^$/d' | paste -sd, -)"
echo "PAYMENTS=$payments"
echo "SEO_RELEVANT=$seo_rel"

fe_or_lang=$((n_frontend + n_lang))
suggest a11y "$(yn $fe_or_lang)" "$n_frontend frontend and $n_lang language file(s) changed"
suggest copy "$(yn $fe_or_lang)" "$n_frontend frontend and $n_lang language file(s) changed"
perf=$((n_migration + n_query + n_loop))
suggest performance "$(yn $perf)" "$n_migration migration(s), $n_query file(s) with queries, $n_loop with collection loops"
docs=$((n_docs + n_config + n_api))
suggest docs_sync "$(yn $docs)" "$n_docs doc file(s), $n_config config file(s), $n_api route/API file(s) changed"
suggest seo "$seo_rel" "$([ "$seo_rel" = yes ] && echo 'SEO surface present and a frontend or routes file changed' || echo 'no SEO surface or no frontend/routes change')"
suggest typography "$(yn $n_view)" "$n_view view/CSS file(s) changed"
suggest ui_design "$(yn $n_view)" "$n_view view/CSS file(s) changed"
suggest ux "$(yn $n_view)" "$n_view view file(s) changed"
suggest animation "$(yn $n_view)" "$n_view view/CSS file(s) changed"
cq=no; [ "$n_backend" -gt 0 ] && [ "$size" != SMALL ] && cq=yes
suggest code_quality "$cq" "$n_backend backend file(s), diff size $size"
n_suggest=$(printf '%s\n' "$SUGGESTED" | tr ',' '\n' | grep -c . || true)
echo "SUGGEST_COUNT=$n_suggest"

# Tiers. Order inside the lists is stable; payments is added later by the Phase 1.5 block (own trigger).
BASE="security,privacy,architecture"
guenstig="$BASE"
for d in a11y copy; do case ",$SUGGESTED," in *,$d,*) guenstig="$guenstig,$d" ;; esac; done
gruendlich="$guenstig"
for d in performance code_quality docs_sync seo typography ui_design ux animation; do
  case ",$SUGGESTED," in *,$d,*) gruendlich="$gruendlich,$d" ;; esac
done
alles=$(orch_expand_dimensions all+full)
echo "TIER_GUENSTIG=$guenstig"; echo "TIER_GRUENDLICH=$gruendlich"; echo "TIER_ALLES=$alles"

# cost_of <dim-list>: rough weighted M, see header. Tenths in integer math, printed with at most one decimal.
cost_of() {
  local list="$1" total added base per
  total=$(printf '%s\n' "$list" | tr ',' '\n' | grep -c .)
  added=$((total - 3))
  [ "$payments" = yes ] && added=$((added + 1))
  case "$size" in
    SMALL) base=80; per=15 ;;
    OK) base=120; per=30 ;;
    *) base=$((n_total * 3 / 2)); [ "$base" -ge 180 ] || base=180
       per=$(((n_total * 4 + 5) / 10)); [ "$per" -ge 30 ] || per=30 ;;
  esac
  echo $((base + added * per))
}
# fmt_tenths <tenths>: 210 -> 21, 266 -> 26.6
fmt_tenths() { awk -v t="$1" 'BEGIN { printf "%s\n", (t % 10 == 0) ? t / 10 : sprintf("%.1f", t / 10) }'; }
# pct_of <tenths>: share of the weekly budget in percent, one decimal
pct_of() { awk -v t="$1" -v b="$budget" 'BEGIN { printf "%.1f\n", t / 10 * 1.2 / b * 100 }'; }
budget=$(sed -n 's/^WEEK_BUDGET_USD=//p' "${USAGE_LIMITS_CONF:-$HOME/.claude/usage-limits.conf}" 2>/dev/null | head -1)
case "$budget" in ''|*[!0-9]*|0) budget=2600 ;; esac
c_g=$(cost_of "$guenstig"); c_r=$(cost_of "$gruendlich"); c_a=$(cost_of "$alles")
echo "COST_GUENSTIG=$(fmt_tenths "$c_g")"; echo "COST_GRUENDLICH=$(fmt_tenths "$c_r")"; echo "COST_ALLES=$(fmt_tenths "$c_a")"
echo "COST_GUENSTIG_PCT=$(pct_of "$c_g")"; echo "COST_GRUENDLICH_PCT=$(pct_of "$c_r")"; echo "COST_ALLES_PCT=$(pct_of "$c_a")"

if [ "$size" = LARGE ] || [ "$size" = HUGE ]; then echo "RECOMMENDED=GUENSTIG"   # big diffs: the flat per-dimension cost hid a 78 M run
elif [ "$n_sensitive" -gt 0 ] || [ "$n_suggest" -ge 3 ]; then echo "RECOMMENDED=GRUENDLICH"; else echo "RECOMMENDED=GUENSTIG"; fi
