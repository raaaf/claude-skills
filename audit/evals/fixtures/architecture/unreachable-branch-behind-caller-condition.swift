// Fixture: `completionShimmer()` is a fully implemented, independently
// correct branch — but its only call site lives nested inside
// `case .writing` of the switch below, checking for `.complete`. Since
// `step` is bound to `.writing` for the entire lifetime of that case, it
// cannot simultaneously equal `.complete` — the nested check can never be
// true. The compiler and type checker are satisfied; a documented
// end-of-entry feature never plays for a single real user.
import Foundation

enum ChatStep { case writing, generating, complete }

struct TodayFlow {
    var step: ChatStep

    func currentView() -> String {
        switch step {
        case .writing:
            // BUG: unreachable. `step` is `.writing` for this entire
            // branch; it cannot also be `.complete` here. This check
            // was left behind by a refactor and has had no other call
            // site since.
            if step == .complete {
                return completionShimmer()
            }
            return "composer"
        case .generating:
            return "typing indicator"
        case .complete:
            return "read-only transcript"
        }
    }

    // Correctly implemented, type-checks, has no bugs of its own — the
    // only call site above can never execute.
    func completionShimmer() -> String {
        "shimmer"
    }
}
