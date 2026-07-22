// Fixture: a widget timeline provider that reads the app-lock state once, at
// build time, and then serves the same entry until midnight. The lock is
// deadline-based (it engages N minutes after the app was backgrounded), and the
// widget process never sees the foreground lock event, so protected content
// stays on the home screen long after the app has locked itself.
//
// Real-world origin: the same shape was found in three separate audits
// (2026-05-16, 2026-06-11, 2026-06-23) on the day's question, the answered
// flag, and a notification body.
import Foundation
import WidgetKit

struct DiaryEntry: TimelineEntry {
    let date: Date
    let questionText: String
    let isAnswered: Bool
    var isLocked: Bool = false
}

enum LockBridge {
    static var lockEnabled: Bool { true }
    static var backgroundedAt: Date? { nil }
    static let timeout: TimeInterval = 5 * 60

    /// Point-in-time answer. Correct only for "right now".
    static var isLocked: Bool {
        guard lockEnabled, let since = backgroundedAt else { return false }
        return Date().timeIntervalSince(since) > timeout
    }

    /// The moment the lock will engage, if one is pending.
    static var lockDeadline: Date? {
        guard lockEnabled, let since = backgroundedAt else { return nil }
        return since.addingTimeInterval(timeout)
    }
}

struct DiaryProvider: TimelineProvider {
    func placeholder(in context: Context) -> DiaryEntry {
        DiaryEntry(date: .now, questionText: "Was hat dich getragen?", isAnswered: false)
    }

    func getSnapshot(in context: Context, completion: @escaping (DiaryEntry) -> Void) {
        completion(loadToday())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<DiaryEntry>) -> Void) {
        // BUG: the lock is evaluated once, here, and baked into a single entry
        // that lives until midnight. lockDeadline exists and is ignored, so no
        // future entry hides the content when the lock actually engages.
        var entry = loadToday()
        entry.isLocked = LockBridge.isLocked

        let midnight = Calendar.current.startOfDay(
            for: Calendar.current.date(byAdding: .day, value: 1, to: .now) ?? .now
        )
        completion(Timeline(entries: [entry], policy: .after(midnight)))
    }

    private func loadToday() -> DiaryEntry {
        DiaryEntry(date: .now, questionText: "Was hat dich heute getragen?", isAnswered: false)
    }
}
