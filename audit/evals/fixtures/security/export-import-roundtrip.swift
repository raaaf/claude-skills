// Fixture: the import path treats a field as mandatory that the CURRENT write
// path no longer fills. Every entry created since the redesign carries
// `questionId == nil`, and the importer skips exactly those — a restore looks
// like it worked ("Import abgeschlossen") and silently drops the entire modern
// history.
//
// Everything needed to see it is in this file: `Entry` has a second
// initializer without a question, `record(from:)` maps that to a nil
// `questionId`, and the import guard drops the record. The two halves of the
// same round trip disagree.
//
// Real-world origin: shipped 2026-07-24 with the redesign, found 2026-08-06.
// For six weeks the app's only backup path discarded almost everything it was
// asked to restore. The class is schema drift between writer and reader, not a
// typo: nobody re-read the importer when the model gained a second init.
import Foundation

final class Question {
    let id: UUID
    let text: String
    init(id: UUID = UUID(), text: String) {
        self.id = id
        self.text = text
    }
}

final class Entry {
    var id: UUID
    var question: Question?
    var questionTextSnapshot: String
    var answerText: String
    var entryDate: Date

    /// Legacy path: an entry that answers a question of the day.
    init(question: Question, answerText: String, entryDate: Date) {
        self.id = UUID()
        self.question = question
        self.questionTextSnapshot = question.text
        self.answerText = answerText
        self.entryDate = entryDate
    }

    /// Current path since the redesign: there is no question of the day any
    /// more, so a new entry is created WITHOUT one. Every entry written from
    /// here on has `question == nil`.
    init(answerText: String, entryDate: Date) {
        self.id = UUID()
        self.question = nil
        self.questionTextSnapshot = ""
        self.answerText = answerText
        self.entryDate = entryDate
    }
}

struct EntryRecord: Codable {
    var id: UUID
    var questionId: UUID?
    var questionTextSnapshot: String
    var answerText: String
    var entryDate: Date
}

struct ExportPayload: Codable {
    var version: Int
    var entries: [EntryRecord]
}

final class DataExportService {

    /// Export side: the optional is faithfully carried through. A questionless
    /// entry exports as `questionId: nil`, which is the normal case now.
    static func record(from entry: Entry) -> EntryRecord {
        EntryRecord(
            id: entry.id,
            questionId: entry.question?.id,
            questionTextSnapshot: entry.questionTextSnapshot,
            answerText: entry.answerText,
            entryDate: entry.entryDate
        )
    }

    func performImport(payload: ExportPayload, questionLookup: [UUID: Question]) -> Int {
        var imported = 0
        for record in payload.entries {
            // BUG: a missing questionId is treated as a broken record. It is the
            // normal shape of every entry written since the redesign, so this
            // guard drops the whole modern history without a single error.
            guard let questionId = record.questionId else { continue }
            guard let question = questionLookup[questionId] else { continue }

            let entry = Entry(
                question: question,
                answerText: record.answerText,
                entryDate: record.entryDate
            )
            entry.id = record.id
            entry.questionTextSnapshot = record.questionTextSnapshot
            imported += 1
        }
        return imported
    }

    /// The preview the user confirms before importing. It counts the same way,
    /// so the number shown and the number written agree — and both are wrong.
    func previewCount(payload: ExportPayload) -> Int {
        payload.entries.filter { $0.questionId != nil }.count
    }
}
