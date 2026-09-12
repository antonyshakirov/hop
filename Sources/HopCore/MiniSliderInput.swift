import Foundation

/// Turns what someone typed into `MiniSlider`'s value field into a value the
/// dial can actually hold.
///
/// The field sits right next to a drag-only slider, so it inherits the same
/// bounds — typing past either end clamps to it rather than rejecting the
/// edit outright, the same way dragging past the end of the track does.
/// Anything that isn't a whole number (empty, a decimal, stray letters) is a
/// typo in progress, not a new value: the dial keeps what it had rather than
/// snapping to something nobody asked for.
public enum MiniSliderInput {
    /// What the field lets through while someone is still typing: digits
    /// only, and never more of them than the range's own widest number needs
    /// (three for 1...100) — a stray extra digit or a pasted "1sdcv" is
    /// trimmed back on the spot rather than sitting there until Return.
    public static func filterDigits(_ text: String, range: ClosedRange<Int>) -> String {
        let maxDigits = String(range.upperBound).count
        return String(text.filter(\.isNumber).prefix(maxDigits))
    }

    public static func commit(_ text: String, range: ClosedRange<Int>, fallback: Int) -> Int {
        guard let parsed = Int(text.trimmingCharacters(in: .whitespaces)) else { return fallback }
        return min(range.upperBound, max(range.lowerBound, parsed))
    }
}
