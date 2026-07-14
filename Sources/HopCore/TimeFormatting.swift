import Foundation

public enum TimeFormatting {
    /// Full display format: always HH:MM:SS; insignificant digits are dimmed separately.
    public static func display(_ remaining: TimeInterval) -> String {
        let total = max(0, Int(remaining.rounded(.up)))
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        return String(format: "%02d:%02d:%02d", h, m, s)
    }

    /// How many leading characters to draw dimmed (zeros and colons before the first significant digit).
    public static func dimCount(for text: String) -> Int {
        var count = 0
        for ch in text {
            if ch == "0" || ch == ":" { count += 1 } else { break }
        }
        return count
    }

    /// Short format for the menu bar: MM:SS, or H:MM:SS when hours are present.
    public static func short(_ remaining: TimeInterval) -> String {
        let total = max(0, Int(remaining.rounded(.up)))
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        if h > 0 { return String(format: "%d:%02d:%02d", h, m, s) }
        return String(format: "%02d:%02d", m, s)
    }
}
