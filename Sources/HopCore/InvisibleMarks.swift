/// SPEC: docs/spec.md — "Localization".
/// Tests: Tests/HopCoreTests/InvisibleMarksTests.swift
public enum InvisibleMarks {
    static let directions: Set<Unicode.Scalar> = ["\u{200E}", "\u{200F}", "\u{061C}"]

    private static let joiner: Unicode.Scalar = "\u{200C}"
    private static let breaks: Set<Unicode.Scalar> = [" ", "\n", "\t"]
    private static let substitutions: Set<Unicode.Scalar> = ["%", "{"]
    private static let rightToLeftRanges: [ClosedRange<UInt32>] = [
        0x0590...0x08FF, 0xFB1D...0xFDFF, 0xFE70...0xFEFF,
    ]

    /// Where `text` carries an invisible character that does not belong there:
    /// any at all when the language runs left to right, and otherwise one the
    /// tables never use or one with nothing to do where it stands.
    public static func strayMark(_ text: String,
                                 rightToLeft: Bool) -> (offset: Int, scalar: Unicode.Scalar)? {
        let scalars = Array(text.unicodeScalars)
        for index in scalars.indices where hidden(scalars[index]) {
            let scalar = scalars[index]
            if rightToLeft {
                if scalar == joiner, separates(scalars, index) { continue }
                if directions.contains(scalar), steers(scalars, index) { continue }
            }
            return (index, scalar)
        }
        return nil
    }

    public static func stray(_ text: String, rightToLeft: Bool) -> Bool {
        strayMark(text, rightToLeft: rightToLeft) != nil
    }

    private static func hidden(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.properties.generalCategory {
        case .format, .lineSeparator, .paragraphSeparator: return true
        default: return scalar.properties.isDefaultIgnorableCodePoint
        }
    }

    private static func separates(_ scalars: [Unicode.Scalar], _ index: Int) -> Bool {
        guard index > 0, index + 1 < scalars.count else { return false }
        let before = scalars[index - 1], after = scalars[index + 1]
        guard !hidden(before), !hidden(after),
              !before.properties.isWhitespace, !after.properties.isWhitespace else { return false }
        return before.properties.isAlphabetic || after.properties.isAlphabetic
    }

    private static func steers(_ scalars: [Unicode.Scalar], _ index: Int) -> Bool {
        run(scalars, from: index + 1, step: 1) || run(scalars, from: index - 1, step: -1)
    }

    private static func run(_ scalars: [Unicode.Scalar], from start: Int, step: Int) -> Bool {
        var next = start
        while next >= 0, next < scalars.count {
            let scalar = scalars[next]
            if breaks.contains(scalar) { return false }
            if HangingWords.modifiers.contains(Character(scalar)) { return true }
            if substitutions.contains(scalar) { return true }
            if scalar.properties.isAlphabetic { return !runsRightToLeft(scalar) }
            if scalar.properties.numericType != nil { return true }
            next += step
        }
        return false
    }

    private static func runsRightToLeft(_ scalar: Unicode.Scalar) -> Bool {
        rightToLeftRanges.contains { $0.contains(scalar.value) }
    }
}
