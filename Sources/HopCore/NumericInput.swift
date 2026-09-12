import Foundation

/// Parsing for the app's numeric fields. Tests: `NumericInputTests`.
public enum NumericInput {
    /// ASCII digits only, at most as many as the range's widest number holds.
    public static func filterDigits(_ text: String, range: ClosedRange<Int>) -> String {
        filterDigits(text, maxDigits: String(range.upperBound).count)
    }

    /// ASCII digits only, at most `maxDigits` of them.
    public static func filterDigits(_ text: String, maxDigits: Int) -> String {
        String(text.filter { $0.isASCII && $0.isNumber }.prefix(max(1, maxDigits)))
    }

    /// The typed value clamped into `range`; `fallback` when it is not a whole number.
    public static func commit(_ text: String, range: ClosedRange<Int>, fallback: Int) -> Int {
        guard let parsed = Int(text.trimmingCharacters(in: .whitespaces)) else { return fallback }
        return clamp(parsed, into: range)
    }

    /// The value brought inside `range`.
    public static func clamp(_ value: Int, into range: ClosedRange<Int>) -> Int {
        min(range.upperBound, max(range.lowerBound, value))
    }
}
