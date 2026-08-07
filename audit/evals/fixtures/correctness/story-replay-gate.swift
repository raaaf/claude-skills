// Fixture: a once-per-evening gate stored as a Bool. At 00:01 it still holds
// yesterday's answer, so the new day's sequence never plays — and the flag that
// would reset it is only written when the sequence plays. The state is stuck
// until something else clears it.
//
// The second half is in the same file: a phase enum held by a view that is not
// rebuilt when the calendar moves, and a layout rule reading it. Open at 23:59,
// untouched, the rule keeps answering with yesterday's phase.
//
// Real-world origin: the most frequent correctness class in this codebase's
// history — five separate findings (a reminder hour of 0 read as "unset", a
// widget deadline compared against build time, a pending marker with no
// midnight exit, day bucketing before interval merge, a step enum surviving the
// day change) before it was ever written down as a class.
import Foundation

enum Phase {
    case loading
    case playing
    case board
}

final class DayGate {

    // BUG: a day-scoped fact stored as a Bool. Nothing in the type says which
    // day it is about, so it cannot expire on its own.
    private var sequencePlayed = false

    // Held by a view that is created once and never rebuilt on a date change.
    private var phase: Phase = .loading

    private let gateHour = 18

    func markPlayed() {
        sequencePlayed = true
    }

    /// The gate. Correct on the day it was written, wrong every day after.
    func shouldPlaySequence(now: Date, calendar: Calendar = .current) -> Bool {
        let hour = calendar.component(.hour, from: now)
        guard hour >= gateHour else { return false }
        return !sequencePlayed
    }

    /// BUG: a layout rule reading state that outlives its screen. `phase` was
    /// set yesterday evening; the process stayed alive through midnight, the
    /// view was never rebuilt, and nothing recomputes this at the date change.
    var usesCompactLayout: Bool {
        phase == .board
    }

    /// For comparison: the same question answered correctly elsewhere in the
    /// file. The last-played DAY is stored and compared, so midnight resolves
    /// it without anyone having to remember to reset.
    private var lastRefreshDay: Date?

    func shouldRefresh(now: Date, calendar: Calendar = .current) -> Bool {
        guard let last = lastRefreshDay else { return true }
        return !calendar.isDate(last, inSameDayAs: now)
    }
}
