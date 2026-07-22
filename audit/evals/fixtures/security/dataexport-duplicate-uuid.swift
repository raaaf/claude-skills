// Fixture: import path builds a lookup dictionary with
// `Dictionary(uniqueKeysWithValues:)` over IDs that are NOT guaranteed unique.
// A payload with two records carrying the same UUID crashes the app instead of
// failing the import.
//
// The duplicate is not hypothetical: this codebase has a documented dedup pass
// for exactly this situation (two rows for the same day arriving through
// CloudKit mid-sync), and an export taken during that window carries both.
//
// Real-world origin: missed on 2026-06-11 by an audit that touched this very
// method for a different security fix. The sibling call a few lines above
// already uses the safe `uniquingKeysWith:` form, which makes this a
// sibling-guard-gap on top of a crash.
import Foundation

struct QuestionRecord {
    let id: UUID
    let text: String
}

struct EntryRecord {
    let id: UUID
    let questionId: UUID?
    let answerText: String
}

struct ExportPayload {
    let entries: [EntryRecord]
    let questions: [QuestionRecord]
}

final class ImportService {

    func performImport(payload: ExportPayload, existingQuestions: [QuestionRecord]) throws -> Int {
        // SAFE: this one already tolerates duplicates and says so.
        // A store mid-CloudKit-sync can legitimately hold two rows per day.
        let existingById = Dictionary(
            existingQuestions.map { ($0.id, $0) },
            uniquingKeysWith: { first, _ in first }
        )

        // BUG: same shape, untrusted source, no uniquing. Two records with the
        // same UUID in the imported JSON trap here. The input is a user-supplied
        // file, so this is reachable by anyone who can hand over an export.
        let incomingById = Dictionary(
            uniqueKeysWithValues: payload.questions.map { ($0.id, $0) }
        )

        var imported = 0
        for entry in payload.entries {
            guard let questionId = entry.questionId else { continue }
            guard incomingById[questionId] != nil || existingById[questionId] != nil else { continue }
            imported += 1
        }
        return imported
    }
}
