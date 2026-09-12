import Foundation

/// Parsing for `MiniSlider`'s value field. Tests: `MiniSliderInputTests`.
public enum MiniSliderInput {
    /// Digits only, at most as many as the range's widest number holds.
    public static func filterDigits(_ text: String, range: ClosedRange<Int>) -> String {
        let maxDigits = String(range.upperBound).count
        return String(text.filter(\.isNumber).prefix(maxDigits))
    }

    /// The typed value clamped into `range`; `fallback` when it is not a whole number.
    public static func commit(_ text: String, range: ClosedRange<Int>, fallback: Int) -> Int {
        guard let parsed = Int(text.trimmingCharacters(in: .whitespaces)) else { return fallback }
        return min(range.upperBound, max(range.lowerBound, parsed))
    }
}
