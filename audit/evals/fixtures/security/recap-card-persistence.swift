// Fixture: a field that must never leave the device carries a filter on exactly
// ONE of its sinks. The write path is clean, so the rule looks implemented; two
// other paths hand the same values out untouched.
//
// The class is "one field, several sinks, one filter". It is not visible from
// the write path alone — a reviewer who checks `encodedCards` and stops sees a
// correct filter. All three sinks are in this file on purpose: the finding
// requires holding them side by side, which is exactly what the real case
// failed to do.
//
// Real-world origin: 2026-08-06. The write-path filter landed in round 1. The
// widget path and the legacy-entry rewrite path were found in rounds 2 and 3 —
// same field, same rule, three rounds. Between round 1 and round 3 the fix
// looked complete.
import Foundation

struct StoredCard: Codable {
    let kind: String
    let chipText: String
}

enum CardKind {
    static let health = "health"

    /// The rule, in one place, correctly written.
    static func isProtected(_ kind: String) -> Bool { kind == health }
}

enum CardStore {

    /// SINK 1 — write. Correct: the protected kind never reaches the synced
    /// column.
    static func encodedCards(_ cards: [StoredCard]) -> String? {
        let allowed = cards.filter { !CardKind.isProtected($0.kind) }
        guard !allowed.isEmpty else { return nil }
        return try? String(data: JSONEncoder().encode(allowed), encoding: .utf8) ?? ""
    }

    /// SINK 2 — the widget's short form. BUG: reads the same cached set and
    /// takes the top two by rank with no filter, so the protected kind renders
    /// on a surface that is visible while the app is locked.
    static func widgetSummary(cached: [StoredCard]) -> String {
        cached.prefix(2).map(\.chipText).joined(separator: " · ")
    }

    /// SINK 3 — the one-off rewrite of already-stored entries. BUG: re-encodes
    /// whatever is on the entry without applying the rule, so every row written
    /// before the filter existed keeps its protected card forever. A migration
    /// that does not enforce the invariant it exists for.
    static func rewriteLegacy(entries: [(id: UUID, cards: [StoredCard])]) -> [UUID: String] {
        var out: [UUID: String] = [:]
        for entry in entries {
            guard let json = try? String(data: JSONEncoder().encode(entry.cards), encoding: .utf8) else { continue }
            out[entry.id] = json
        }
        return out
    }

    /// SINK 4 — the derived one-line summary that ships in the same synced row.
    /// Correct: filters before joining. Included so the fixture is not "every
    /// path but one is broken".
    static func summaryLine(_ cards: [StoredCard]) -> String {
        cards.filter { !CardKind.isProtected($0.kind) }.map(\.chipText).joined(separator: " · ")
    }
}
