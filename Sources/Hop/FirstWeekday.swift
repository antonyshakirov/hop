import Foundation

/// Which day a week starts on in the reminder's weekday row.
///
/// The region decides this and people disagree with their region: the US counts
/// from Sunday, most of Europe from Monday, and someone can sit in one place and
/// think in the other's week. So the default follows the system's regional
/// setting and the user can override it (Anton, 2026-07-28).
enum FirstWeekday: String, CaseIterable, Identifiable {
    case auto
    case sunday
    case monday

    var id: String { rawValue }

    /// Calendar's own numbering: 1 = Sunday … 7 = Saturday.
    var weekdayNumber: Int {
        switch self {
        case .auto: return Calendar.current.firstWeekday
        case .sunday: return 1
        case .monday: return 2
        }
    }

    /// The seven weekdays in display order, starting from this setting's day.
    var weekOrder: [Int] {
        let first = weekdayNumber
        return (0..<7).map { ((first - 1 + $0) % 7) + 1 }
    }

    /// The day's own name, from the system rather than a hand-written table, so
    /// it is right in every language the app speaks.
    var label: String {
        switch self {
        case .auto: return ""   // the settings row shows the localized "auto"
        case .sunday, .monday: return Self.name(for: weekdayNumber)
        }
    }

    static func name(for weekday: Int) -> String {
        let symbols = Calendar.current.standaloneWeekdaySymbols
        let name = symbols[(weekday - 1) % symbols.count]
        return name.prefix(1).uppercased() + name.dropFirst()
    }

    /// The single-letter cap used on the weekday squares.
    static func initial(for weekday: Int) -> String {
        let symbols = Calendar.current.veryShortWeekdaySymbols
        return symbols[(weekday - 1) % symbols.count]
    }
}
