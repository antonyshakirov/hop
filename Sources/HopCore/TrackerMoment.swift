import Foundation

/// The date and time a history line carries, as three numbers plus a clock.
///
/// A menu of the last thirty days answered "when did I do this" only while the
/// answer was recent; a session logged for last spring had nowhere to go
/// (Anton, 2026-08-28). Typed day, month and year reach any date at all — and
/// typed fields need someone to keep them honest, which is what this does: the
/// 31st of a thirty-day month is not an error message, it is the 30th.
public enum TrackerMoment {
    public enum Part: String, Equatable, Sendable {
        case day
        case month
        case year
    }

    /// The order the three fields are shown in, taken from the locale's own
    /// date template — 5 March reads d/M/y in most of the world and M/d/y in
    /// the US, and a fixed order would be wrong in one of them.
    /// Anything the template does not mention is appended, so the row always
    /// has all three.
    public static func order(template: String) -> [Part] {
        var seen: [Part] = []
        for character in template {
            let part: Part?
            switch character {
            case "d", "D": part = .day
            case "M", "L": part = .month
            case "y", "Y": part = .year
            default: part = nil
            }
            if let part, !seen.contains(part) { seen.append(part) }
        }
        for part in [Part.day, .month, .year] where !seen.contains(part) { seen.append(part) }
        return seen
    }

    /// A day number that exists in that month: February never has a 31st, and
    /// 2026 has no 29th of February while 2028 does.
    public static func clampedDay(_ day: Int, month: Int, year: Int,
                                  calendar: Calendar = .current) -> Int {
        let month = min(max(month, 1), 12)
        var components = DateComponents()
        components.year = year
        components.month = month
        let last: Int
        if let firstOfMonth = calendar.date(from: components),
           let range = calendar.range(of: .day, in: .month, for: firstOfMonth) {
            last = range.count
        } else {
            last = 31
        }
        return min(max(day, 1), last)
    }

    /// The moment those numbers describe, with the day clamped into its month.
    /// nil only when the calendar refuses the combination outright.
    public static func date(year: Int, month: Int, day: Int, hour: Int, minute: Int,
                            calendar: Calendar = .current) -> Date? {
        var components = DateComponents()
        components.year = year
        components.month = min(max(month, 1), 12)
        components.day = clampedDay(day, month: month, year: year, calendar: calendar)
        components.hour = min(max(hour, 0), 23)
        components.minute = min(max(minute, 0), 59)
        components.second = 0
        return calendar.date(from: components)
    }

    /// The same numbers, read back off a date — how an editor is filled in.
    public static func parts(of date: Date, calendar: Calendar = .current)
        -> (year: Int, month: Int, day: Int, hour: Int, minute: Int) {
        let c = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        return (c.year ?? 2000, c.month ?? 1, c.day ?? 1, c.hour ?? 0, c.minute ?? 0)
    }
}
