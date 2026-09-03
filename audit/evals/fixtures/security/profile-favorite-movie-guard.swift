// Fixture: onboarding profile validation. ContentGuard.block was written
// for the free-text "about me" field and later reused, unchanged, for the
// "favorite movie" preference field during a quick onboarding revamp.
//
// Real-world origin: a Swift audit (2026-07) found a content guard reused
// across a new field without checking whether the original block/degrade
// distinction still applied.
import Foundation

enum ContentGuard {
    // Words considered inappropriate for a public free-text bio. A hard
    // block is the right response there: better to reject than publish
    // something ugly.
    static let blockedKeywords = ["hass", "krieg", "gewalt"]

    static func block(_ text: String) -> Bool {
        let lower = text.lowercased()
        return blockedKeywords.contains { lower.contains($0) }
    }
}

struct ProfileDraft {
    var bio: String
    var favoriteMovie: String
}

enum ProfileValidator {
    static func validate(_ profile: ProfileDraft) -> Bool {
        if ContentGuard.block(profile.bio) {
            return false
        }

        // BUG: favoriteMovie is a curated preference field, not free text.
        // Reusing the free-text block list here hard-rejects benign real
        // titles like "Krieg der Sterne" (Star Wars) because "krieg" is on
        // the list. The bio use case wanted a hard block; this field needed
        // at most a soft degrade, never a rejection of real content.
        if ContentGuard.block(profile.favoriteMovie) {
            return false
        }

        return true
    }
}
