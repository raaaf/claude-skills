#!/usr/bin/env bash
#
# Detect whether a repo implements a Stripe integration itself, classify HOW
# (cashier/sdk/client/hosted/http), and emit the payment-surface file list.
# Consumed by /audit and /full-audit to gate the payments audit dimension.
#
# Usage: bash detect-stripe.sh [PROJECT_ROOT]
# Default PROJECT_ROOT: git toplevel, falling back to pwd.
#
# ============================================================================
# CONSUMPTION CONTRACT
# ============================================================================
# Output:
#   STRIPE=yes|no
#   STRIPE_MODE=<comma-separated subset of: cashier,sdk,client,hosted,http>
#     (line omitted entirely when STRIPE=no)
#   STRIPE_RECURRING=yes|no|unknown
#     (line omitted entirely when STRIPE=no; "yes" when the integration
#     clearly does recurring billing, "no" when it is present but no
#     recurring signal appears anywhere, "unknown" when the evidence cannot
#     support either call, e.g. hosted/client modes where the recurring
#     decision lives in the Stripe Dashboard or a Payment Link)
#   STRIPE_FILES<<END
#   <one repo-relative path per line>
#   END
#
# STRIPE_FILES is a heredoc block, not a key=value line: it can legitimately
# contain many lines, one per surface file, so it must never be read with a
# single `sed -n 's/^STRIPE_FILES=//p'`-style single-line extraction. Same
# reasoning as detect-framework.sh's SOURCE_DIRS line (read that script's own
# header before writing a new consumer) -- a blanket `eval "$(...)"` over the
# whole output is wrong here too, since the heredoc body is arbitrary
# repo-relative text, not shell-safe. Correct consumption: capture stdout as
# text, extract STRIPE/STRIPE_MODE by key, then take everything between the
# `STRIPE_FILES<<END` and matching `END` lines as the file list, one path per
# line. Do not `eval` the file list.
# ============================================================================
set -euo pipefail

# Resolve SCRIPT_DIR before changing directory: it must anchor to this
# script's own location, not to $ROOT, or a relative invocation (`bash
# detect-stripe.sh ...` from this directory) resolves dirname("detect-
# stripe.sh") == "." against the POST-cd cwd and silently calls a
# non-existent detect-framework.sh next to $ROOT instead of next to this
# script, collapsing SOURCE_DIRS to the "./" fallback (verified: reproduces).
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)

ROOT="${1:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
cd "$ROOT"

# ----------------------------------------------------------------------------
# Source dirs: reuse detect-framework.sh's notion of "this repo's own code",
# per its CONSUMPTION CONTRACT (capture as text, extract by key, eval only the
# array reconstruction, never a blanket eval over the whole 3-line output).
# ----------------------------------------------------------------------------
FW_OUT="$(bash "$SCRIPT_DIR/detect-framework.sh" "$ROOT" 2>/dev/null || true)"
SOURCE_DIRS=$(printf '%s\n' "$FW_OUT" | sed -n 's/^SOURCE_DIRS=//p')
SOURCE_DIRS_ARR=()
if [ -n "$SOURCE_DIRS" ]; then
  eval "SOURCE_DIRS_ARR=($SOURCE_DIRS)"
fi
[ "${#SOURCE_DIRS_ARR[@]}" -eq 0 ] && SOURCE_DIRS_ARR=("./")

# Prune list shared by every find below: vendor/build output and third-party
# plugin/theme trees are never first-party evidence.
FIND_PRUNE=(
  -not -path '*/node_modules/*'
  -not -path '*/vendor/*'
  -not -path '*/.git/*'
  -not -path '*/dist/*'
  -not -path '*/build/*'
  -not -path '*/public/build/*'
  -not -path '*/wp-content/plugins/*'
  -not -path '*/wp-content/themes/*'
)

# Source-code file extensions worth grepping for Stripe content signals.
SRC_NAME_OPTS=(
  \( -name '*.php' -o -name '*.js' -o -name '*.jsx' -o -name '*.ts'
     -o -name '*.tsx' -o -name '*.mjs' -o -name '*.cjs' -o -name '*.vue'
     -o -name '*.py' -o -name '*.rb' -o -name '*.go' -o -name '*.cs' \)
)

TEST_DIR_RE='(^|/)(tests?|spec|__tests__|__mocks__|fixtures?|factories)/'

# ----------------------------------------------------------------------------
# Manifest detection: repo root, plus the top-level directory of each
# SOURCE_DIRS entry (non-recursive), so a monorepo package manifest counts
# but nothing inside vendor/node_modules ever does.
# ----------------------------------------------------------------------------
MANIFEST_DIRS_RAW="."
for d in "${SOURCE_DIRS_ARR[@]}"; do
  top="${d%%/*}"
  [ -z "$top" ] && continue
  [ -d "$top" ] || continue
  MANIFEST_DIRS_RAW="$MANIFEST_DIRS_RAW
$top"
done
MANIFEST_DIRS=$(printf '%s\n' "$MANIFEST_DIRS_RAW" | sort -u)

HAS_CASHIER=0
HAS_SDK=0
HAS_CLIENT_MANIFEST=0
MANIFEST_FILES=""

while IFS= read -r mdir; do
  [ -z "$mdir" ] && continue

  composer="$mdir/composer.json"
  if [ -f "$composer" ]; then
    if grep -q '"laravel/cashier"' "$composer" 2>/dev/null || \
       grep -q '"spatie/laravel-stripe-webhooks"' "$composer" 2>/dev/null; then
      HAS_CASHIER=1
      MANIFEST_FILES="$MANIFEST_FILES
$composer"
    fi
    if grep -q '"stripe/stripe-php"' "$composer" 2>/dev/null; then
      HAS_SDK=1
      MANIFEST_FILES="$MANIFEST_FILES
$composer"
    fi
  fi

  pkg="$mdir/package.json"
  if [ -f "$pkg" ]; then
    if grep -q '"stripe"[[:space:]]*:' "$pkg" 2>/dev/null; then
      HAS_SDK=1
      MANIFEST_FILES="$MANIFEST_FILES
$pkg"
    fi
    if grep -q '"@stripe/stripe-js"' "$pkg" 2>/dev/null || \
       grep -q '"@stripe/react-stripe-js"' "$pkg" 2>/dev/null; then
      HAS_CLIENT_MANIFEST=1
      MANIFEST_FILES="$MANIFEST_FILES
$pkg"
    fi
  fi

  req="$mdir/requirements.txt"
  if [ -f "$req" ] && grep -qi '^stripe\b' "$req" 2>/dev/null; then
    HAS_SDK=1
    MANIFEST_FILES="$MANIFEST_FILES
$req"
  fi

  pyproj="$mdir/pyproject.toml"
  if [ -f "$pyproj" ] && grep -qi 'stripe' "$pyproj" 2>/dev/null; then
    HAS_SDK=1
    MANIFEST_FILES="$MANIFEST_FILES
$pyproj"
  fi

  gemfile="$mdir/Gemfile"
  if [ -f "$gemfile" ] && grep -qE "gem ['\"]stripe['\"]" "$gemfile" 2>/dev/null; then
    HAS_SDK=1
    MANIFEST_FILES="$MANIFEST_FILES
$gemfile"
  fi

  gomod="$mdir/go.mod"
  if [ -f "$gomod" ] && grep -q 'github.com/stripe/stripe-go' "$gomod" 2>/dev/null; then
    HAS_SDK=1
    MANIFEST_FILES="$MANIFEST_FILES
$gomod"
  fi

  while IFS= read -r csproj; do
    [ -z "$csproj" ] && continue
    if grep -qi 'Stripe\.net' "$csproj" 2>/dev/null; then
      HAS_SDK=1
      MANIFEST_FILES="$MANIFEST_FILES
$csproj"
    fi
  done < <(find "$mdir" -maxdepth 1 -name '*.csproj' 2>/dev/null || true)
done <<< "$MANIFEST_DIRS"

# ----------------------------------------------------------------------------
# Source-content signals: js.stripe.com, api.stripe.com, buy/checkout.stripe.com
# and first-party Stripe SDK usage, scoped to SOURCE_DIRS, excluding vendor
# trees, minified assets and lock files. Split into all hits vs. non-test
# hits: non-test hits are evidence for the yes/no decision, test hits are
# not evidence but still belong in STRIPE_FILES once STRIPE=yes.
# ----------------------------------------------------------------------------
CANDIDATE_FILES=""
for d in "${SOURCE_DIRS_ARR[@]}"; do
  [ -d "$d" ] || continue
  hits=$(find "$d" -maxdepth 6 "${FIND_PRUNE[@]}" -type f "${SRC_NAME_OPTS[@]}" 2>/dev/null | \
    grep -v '\.min\.js$' || true)
  [ -n "$hits" ] && CANDIDATE_FILES="$CANDIDATE_FILES
$hits"
done

# SOURCE_DIRS (framework source dirs) deliberately excludes test directories,
# but "test files that touch Stripe belong in STRIPE_FILES once STRIPE=yes"
# needs them scanned too. Scan top-level test dirs separately so their hits
# feed ALL_CONTENT_HITS for the file list, while TEST_DIR_RE below still
# keeps them out of NON_TEST_CONTENT_HITS, i.e. out of the yes/no decision.
for d in tests test spec __tests__; do
  [ -d "$d" ] || continue
  hits=$(find "$d" -maxdepth 6 "${FIND_PRUNE[@]}" -type f "${SRC_NAME_OPTS[@]}" 2>/dev/null | \
    grep -v '\.min\.js$' || true)
  [ -n "$hits" ] && CANDIDATE_FILES="$CANDIDATE_FILES
$hits"
done
CANDIDATE_FILES=$(printf '%s\n' "$CANDIDATE_FILES" | sed '/^$/d' | sort -u)

CONTENT_PATTERN='js\.stripe\.com|api\.stripe\.com|buy\.stripe\.com|checkout\.stripe\.com|\\Stripe\\|Stripe::|use Stripe|from ['"'"'"]stripe|require\(['"'"'"]stripe|import Stripe'

ALL_CONTENT_HITS=""
if [ -n "$CANDIDATE_FILES" ]; then
  ALL_CONTENT_HITS=$(printf '%s\n' "$CANDIDATE_FILES" | xargs grep -lE "$CONTENT_PATTERN" 2>/dev/null || true)
fi
ALL_CONTENT_HITS=$(printf '%s\n' "$ALL_CONTENT_HITS" | sed '/^$/d' | sort -u)

NON_TEST_CONTENT_HITS=$(printf '%s\n' "$ALL_CONTENT_HITS" | grep -vE "$TEST_DIR_RE" || true)

HAS_HOSTED=0
HAS_HTTP=0
if [ -n "$NON_TEST_CONTENT_HITS" ]; then
  if printf '%s\n' "$NON_TEST_CONTENT_HITS" | xargs grep -lE 'buy\.stripe\.com|checkout\.stripe\.com' 2>/dev/null | grep -q .; then
    HAS_HOSTED=1
  fi
  if printf '%s\n' "$NON_TEST_CONTENT_HITS" | xargs grep -lE 'api\.stripe\.com' 2>/dev/null | grep -q .; then
    HAS_HTTP=1
  fi
  if printf '%s\n' "$NON_TEST_CONTENT_HITS" | xargs grep -lE 'js\.stripe\.com' 2>/dev/null | grep -q .; then
    HAS_CLIENT_MANIFEST=1
  fi
fi

# hosted only applies when no server SDK was found; http only applies when no
# SDK manifest entry exists at all.
[ "$HAS_SDK" -eq 1 ] && HAS_HOSTED=0
[ "$HAS_SDK" -eq 1 ] && HAS_HTTP=0

# ----------------------------------------------------------------------------
# Decide yes/no and build STRIPE_MODE.
# ----------------------------------------------------------------------------
STRIPE="no"
if [ "$HAS_CASHIER" -eq 1 ] || [ "$HAS_SDK" -eq 1 ] || [ "$HAS_CLIENT_MANIFEST" -eq 1 ] || \
   [ "$HAS_HOSTED" -eq 1 ] || [ "$HAS_HTTP" -eq 1 ]; then
  STRIPE="yes"
fi

MODE=""
[ "$HAS_CASHIER" -eq 1 ] && MODE="$MODE,cashier"
[ "$HAS_SDK" -eq 1 ] && MODE="$MODE,sdk"
[ "$HAS_CLIENT_MANIFEST" -eq 1 ] && MODE="$MODE,client"
[ "$HAS_HOSTED" -eq 1 ] && MODE="$MODE,hosted"
[ "$HAS_HTTP" -eq 1 ] && MODE="$MODE,http"
MODE="${MODE#,}"

echo "STRIPE=$STRIPE"

if [ "$STRIPE" = "no" ]; then
  exit 0
fi

echo "STRIPE_MODE=$MODE"

# ----------------------------------------------------------------------------
# STRIPE_RECURRING: does the integration do recurring billing at all, scoped
# to the same first-party, non-test content already used for the yes/no
# decision above (NON_TEST_CONTENT_HITS), plus a Laravel migration-name check
# for a subscriptions/subscription_items table. Cashier alone settles it
# (Cashier IS the subscription library). "unknown" only when the repo carries
# no such signal AND mode is limited to hosted/client, where the recurring
# decision lives in the Stripe Dashboard or a Payment Link, not in the repo.
# ----------------------------------------------------------------------------
RECURRING_CONTENT=0
if [ -n "$NON_TEST_CONTENT_HITS" ]; then
  if printf '%s\n' "$NON_TEST_CONTENT_HITS" | xargs grep -lE '\\Stripe\\Subscription|Subscription::' 2>/dev/null | grep -q .; then
    RECURRING_CONTENT=1
  fi
  if printf '%s\n' "$NON_TEST_CONTENT_HITS" | xargs grep -lE "mode['\"][[:space:]]*(=>|:)[[:space:]]*['\"]subscription['\"]" 2>/dev/null | grep -q .; then
    RECURRING_CONTENT=1
  fi
  if printf '%s\n' "$NON_TEST_CONTENT_HITS" | xargs grep -lE "recurring['\"]?[[:space:]]*(=>|:)" 2>/dev/null | grep -q .; then
    RECURRING_CONTENT=1
  fi
fi

HAS_MIGRATION_SUBSCRIPTION=0
if [ -d "database/migrations" ] && \
   find database/migrations -maxdepth 1 -type f -iname '*subscription*' 2>/dev/null | grep -q .; then
  HAS_MIGRATION_SUBSCRIPTION=1
fi

STRIPE_RECURRING="no"
if [ "$HAS_CASHIER" -eq 1 ] || [ "$RECURRING_CONTENT" -eq 1 ] || [ "$HAS_MIGRATION_SUBSCRIPTION" -eq 1 ]; then
  STRIPE_RECURRING="yes"
elif [ "$HAS_SDK" -eq 1 ] || [ "$HAS_HTTP" -eq 1 ]; then
  STRIPE_RECURRING="no"
else
  STRIPE_RECURRING="unknown"
fi
echo "STRIPE_RECURRING=$STRIPE_RECURRING"

# ----------------------------------------------------------------------------
# STRIPE_FILES: the payment surface.
# ----------------------------------------------------------------------------
FILES=""

# 1. Manifests + first-party source with a content signal (test hits included
#    now that STRIPE=yes is established).
[ -n "$MANIFEST_FILES" ] && FILES="$FILES
$MANIFEST_FILES"
[ -n "$ALL_CONTENT_HITS" ] && FILES="$FILES
$ALL_CONTENT_HITS"

# 2. Webhook routes + resolvable controllers (Laravel: routes/*.php).
#    "webhook" alone is not Stripe-specific (ResendWebhookController,
#    PrintfulWebhookController, ... live in the same routes file), so a
#    route only qualifies as evidence when either its URI/handler already
#    names Stripe/Cashier directly, or it says "webhook" AND the resolved
#    controller file itself carries a Stripe signal. A "webhook" route whose
#    handler can't be resolved to a file is skipped rather than guessed at.
if [ -d "routes" ]; then
  # All first-party PHP files, computed once so controller-class resolution
  # below doesn't re-run find per class name.
  ALL_PHP_FILES=$(find "${SOURCE_DIRS_ARR[@]}" -maxdepth 6 "${FIND_PRUNE[@]}" -type f -name '*.php' 2>/dev/null || true)

  WEBHOOK_CONTROLLER_EVIDENCE='[Ss]tripe|Webhook::constructEvent|api\.stripe\.com|STRIPE_|CASHIER_'

  while IFS= read -r routefile; do
    [ -z "$routefile" ] && continue

    while IFS= read -r line; do
      [ -z "$line" ] && continue
      class=$(printf '%s\n' "$line" | grep -oE '[A-Za-z_]+Controller' | head -1 || true)
      found=""
      [ -n "$class" ] && found=$(printf '%s\n' "$ALL_PHP_FILES" | grep -m1 "/${class}\.php\$" || true)

      if printf '%s\n' "$line" | grep -qiE 'stripe|cashier'; then
        FILES="$FILES
$routefile"
        [ -n "$found" ] && FILES="$FILES
$found"
      elif printf '%s\n' "$line" | grep -qi 'webhook'; then
        [ -n "$found" ] || continue
        if grep -qE "$WEBHOOK_CONTROLLER_EVIDENCE" "$found" 2>/dev/null; then
          FILES="$FILES
$routefile
$found"
        fi
      fi
    done < <(grep -iE 'stripe|webhook|cashier' "$routefile" 2>/dev/null)
  done < <(find routes -maxdepth 2 -name '*.php' 2>/dev/null || true)
fi

# 3. Middleware / CSRF / kernel config a webhook route depends on (Laravel).
for mf in bootstrap/app.php app/Http/Middleware/VerifyCsrfToken.php app/Http/Kernel.php; do
  [ -f "$mf" ] && FILES="$FILES
$mf"
done

# 4. Subscription / order / payment models + migrations. Multiple -iname
# clauses instead of -iregex alternation: BSD find (macOS) only supports
# alternation in -regex/-iregex with the non-portable -E flag, so an ordinary
# `(a|b)` pattern here would silently match nothing (verified: it does).
MODEL_NAME_OPTS=(
  \( -iname '*subscription*' -o -iname '*invoice*' -o -iname '*payment*'
     -o -iname '*order*' -o -iname '*charge*' -o -iname '*billing*' \)
)
for d in "${SOURCE_DIRS_ARR[@]}"; do
  [ -d "$d" ] || continue
  hits=$(find "$d" -maxdepth 6 "${FIND_PRUNE[@]}" -type f "${MODEL_NAME_OPTS[@]}" 2>/dev/null || true)
  [ -n "$hits" ] && FILES="$FILES
$hits"
done

# 5. .env.example when it declares a STRIPE_* key.
if [ -f ".env.example" ] && grep -q '^STRIPE_' ".env.example" 2>/dev/null; then
  FILES="$FILES
.env.example"
fi

# Deduplicate, sort, strip empty lines, make repo-relative (strip leading ./).
FILES=$(printf '%s\n' "$FILES" | sed '/^$/d' | sed 's#^\./##' | sort -u)

echo "STRIPE_FILES<<END"
[ -n "$FILES" ] && printf '%s\n' "$FILES"
echo "END"

exit 0
