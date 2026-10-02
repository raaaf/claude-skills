#!/usr/bin/env bash
#
# Pins orch_sensitive_paths (2026-10-02): the changed non-test paths on an auth, payment or privacy surface
# decide whether /audit dispatches the extra /security-review next to the built-in /code-review.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
. "$SCRIPT_DIR/lib-orchestrator.sh"

expect() {
  local changed="$1" expected="$2" label="$3" output
  output=$(orch_sensitive_paths "$changed")
  [[ "$output" == "$expected" ]] || {
    printf 'FAIL %s\nExpected: %s\nGot: %s\n' "$label" "$expected" "$output" >&2
    exit 1
  }
  printf 'PASS %s\n' "$label"
}

# One hit per surface class
expect $'app/Http/Controllers/Auth/LoginController.php\n' 'app/Http/Controllers/Auth/LoginController.php' 'auth/login'
expect $'app/Providers/AuthServiceProvider.php\n' 'app/Providers/AuthServiceProvider.php' 'CamelCase Auth name'
expect $'app/Http/Middleware/EnsureTeam.php\n' 'app/Http/Middleware/EnsureTeam.php' 'middleware'
expect $'app/Policies/PostPolicy.php\n' 'app/Policies/PostPolicy.php' 'policies'
expect $'src/session-store.ts\n' 'src/session-store.ts' 'session'
expect $'src/api/token.ts\n' 'src/api/token.ts' 'token'
expect $'app/Actions/ResetPassword.php\n' 'app/Actions/ResetPassword.php' 'password'
expect $'app/Services/PaymentService.php\n' 'app/Services/PaymentService.php' 'payment'
expect $'app/Http/StripeWebhookController.php\n' 'app/Http/StripeWebhookController.php' 'stripe/webhook'
expect $'app/Billing/InvoiceBuilder.php\n' 'app/Billing/InvoiceBuilder.php' 'billing/invoice'
expect $'src/checkout/Cart.tsx\n' 'src/checkout/Cart.tsx' 'checkout'
expect $'app/Gdpr/Export.php\n' 'app/Gdpr/Export.php' 'gdpr'
expect $'src/ConsentBanner.tsx\n' 'src/ConsentBanner.tsx' 'consent'
expect $'app/Models/PersonalData.php\n' 'app/Models/PersonalData.php' 'personal data'
expect $'resources/views/privacy.blade.php\n' 'resources/views/privacy.blade.php' 'privacy view'
expect $'app/Policies/Perm.php\nconfig/permissions.php\n' $'app/Policies/Perm.php\nconfig/permissions.php' 'permission, sorted, several hits'

# Not matched
expect $'resources/views/about.blade.php\n' '' 'plain view file'
expect $'app/Models/Author.php\nresources/views/authors/index.blade.php\n' '' 'author is not auth'
expect $'resources/css/tokens.css\ndocs/privacy.md\n' '' 'style and prose files'
expect $'tests/Feature/LoginTest.php\nsrc/login.test.ts\nsrc/auth.spec.ts\nweb/__tests__/session.ts\nspec/payment.rb\n' '' 'test files ignored'
expect $'tests/Feature/LoginTest.php\napp/Http/LoginController.php\n' 'app/Http/LoginController.php' 'source hit survives next to a test file'
expect '' '' 'empty input'
