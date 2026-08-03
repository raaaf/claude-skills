// Fixture: the salience gate that guaranteed "more than usual" was true
// got removed — cards now always show, the ranking only decides order —
// but the phrase generator never learned about it and keeps asserting
// the comparison unconditionally. The false claim flows straight into
// the generated recap text.
import Foundation

struct CalendarObservation {
    let eventCount: Int
    let medianCount: Int
}

enum CalendarPhrasing {
    // BUG: claims "mehr Termine als sonst" regardless of whether
    // eventCount actually exceeds medianCount. Before the gate removal
    // this function only ran once salience had already proven the
    // claim true; now every day reaches here, including ones at or
    // below the median.
    static func summary(for observation: CalendarObservation) -> String {
        "Heute hattest du mehr Termine als sonst (\(observation.eventCount))."
    }
}
