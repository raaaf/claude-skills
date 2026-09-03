// Fixture: error reporting wired up during a sign-up revamp. Internal
// guard reasons and raw provider error text get forwarded to Sentry as
// extras, where anyone with dashboard access - including the third-party
// analytics contractor - can read them.
//
// Real-world origin: a Swift audit (2026-08) found this pattern added
// alongside a new sign-up provider integration.
import Sentry

enum GuardRejectionReason {
    case disposableEmail(domain: String)
    case rateLimited(retryAfter: TimeInterval)

    var detail: String {
        switch self {
        case .disposableEmail(let domain):
            return "blocked disposable domain \(domain)"
        case .rateLimited(let retryAfter):
            return "rate limited, retry after \(retryAfter)s"
        }
    }
}

func reportSignUpFailure(
    reason: GuardRejectionReason,
    providerError: Error?,
    rawError: NSError?
) {
    // BUG: these extras carry internal detail strings - the exact guard
    // reason, the provider's raw error text, and the underlying NSError
    // description - straight into Sentry, a third-party sink. None of this
    // was meant to leave the app; it can contain user-identifying
    // fragments (the disposable email domain) and internal reasoning that
    // should stay server-side.
    SentrySDK.capture(message: "sign_up_blocked") { scope in
        scope.setExtra(value: reason.detail, key: "guard_reason")
        scope.setExtra(value: providerError?.localizedDescription ?? "", key: "provider_error")
        scope.setExtra(value: rawError?.debugDescription ?? "", key: "raw_error")
    }
}
