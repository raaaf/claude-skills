#!/usr/bin/env bash
#
# Pins orch_payments_touched: the payments trigger intersects the changed set with
# STRIPE_FILES, test paths excluded (2026-09-30: a test helper in STRIPE_FILES alone
# started a 41 USD payments run over unchanged code).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
. "$SCRIPT_DIR/lib-orchestrator.sh"

expect() {
  local changed="$1" stripe="$2" expected="$3" label="$4" output
  output=$(orch_payments_touched "$changed" "$stripe")
  [[ "$output" == "$expected" ]] || {
    printf 'FAIL %s\nExpected: %s\nGot: %s\n' "$label" "$expected" "$output" >&2
    exit 1
  }
  printf 'PASS %s\n' "$label"
}

STRIPE=$'app/Http/StripeWebhook.php\ntests/Pest.php\ntests/Feature/CheckoutTest.php\nsrc/pay.test.ts\nsrc/pay.spec.ts\nweb/__tests__/pay.ts\nspec/pay.rb\napp/Billing/InvoiceTest.php'

expect $'tests/Pest.php\n' "$STRIPE" '' 'test helper alone does not trigger'
expect $'tests/Feature/CheckoutTest.php\nsrc/pay.test.ts\nsrc/pay.spec.ts\nweb/__tests__/pay.ts\nspec/pay.rb\napp/Billing/InvoiceTest.php\n' "$STRIPE" '' 'every test path shape excluded'
expect $'tests/Pest.php\napp/Http/StripeWebhook.php\n' "$STRIPE" 'app/Http/StripeWebhook.php' 'source file still triggers next to a test file'
expect $'app/Other.php\n' "$STRIPE" '' 'file outside the surface does not trigger'

# 2026-10-02: generic wiring in STRIPE_FILES (routes/console.php) alone started payments over unchanged code.
WIRING=$'routes/console.php\nroutes/web.php\napp/Http/Controllers/StripeWebhookController.php\nconfig/cashier.php\nresources/views/checkout/pay.blade.php'
expect $'routes/console.php\n' "$WIRING" '' 'routes/console.php alone does not trigger'
expect $'routes/web.php\n' "$WIRING" '' 'routes/web.php alone does not trigger'
expect $'app/Http/Controllers/StripeWebhookController.php\n' "$WIRING" 'app/Http/Controllers/StripeWebhookController.php' 'webhook controller triggers'
expect $'config/cashier.php\n' "$WIRING" 'config/cashier.php' 'config/cashier.php triggers (cashier)'
expect $'resources/views/checkout/pay.blade.php\n' "$WIRING" 'resources/views/checkout/pay.blade.php' 'checkout view triggers'
