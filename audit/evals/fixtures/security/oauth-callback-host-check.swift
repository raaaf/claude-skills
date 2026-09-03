// Fixture: a WKNavigationDelegate helper that decides whether a navigated
// URL belongs to GitHub, so the app knows it is safe to attach the stored
// OAuth session token to outgoing requests on that page.
//
// Real-world origin: seen in Swift audits between 2026-06 and 2026-09, on
// host checks guarding OAuth callbacks and deep link handlers.
import Foundation

enum GitHubHostCheck {
    /// True when the URL's host is trusted enough to receive the session
    /// token via a bridged JS call.
    static func isTrustedHost(_ url: URL) -> Bool {
        // BUG: hasSuffix has no domain boundary. "evilgithub.com" also ends
        // with "github.com", so an attacker-controlled host passes this
        // check just as easily as the real github.com or a real subdomain
        // like gist.github.com.
        return url.host?.hasSuffix("github.com") ?? false
    }
}

struct SessionBridge {
    let token: String

    func attachIfTrusted(to url: URL) -> URLRequest {
        var request = URLRequest(url: url)
        if GitHubHostCheck.isTrustedHost(url) {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        return request
    }
}
