/// SPEC: docs/spec.md — "Localization".
/// Tests: Tests/HopCoreTests/InvisibleMarksTests.swift
public enum InvisibleMarks {
    static let directions: Set<Unicode.Scalar> = ["\u{200E}", "\u{200F}", "\u{061C}"]

    private enum Side { case leftToRight, rightToLeft }

    private static let joiner: Unicode.Scalar = "\u{200C}"
    private static let lineEnds: Set<Unicode.Scalar> = [
        "\n", "\r", "\u{000B}", "\u{000C}", "\u{0085}", "\u{2028}", "\u{2029}",
    ]
    private static let breaks: Set<Unicode.Scalar> = [" ", "\t", "\n", "\r",
                                                     "\u{000B}", "\u{000C}", "\u{0085}",
                                                     "\u{2028}", "\u{2029}"]
    private static let isolates: Set<Unicode.Scalar> = ["\u{2066}", "\u{2067}", "\u{2068}"]
    private static let popIsolate: Unicode.Scalar = "\u{2069}"
    private static let conversions: Set<Unicode.Scalar> = [
        "@", "d", "i", "u", "f", "F", "g", "G", "e", "E", "x", "X", "o", "s", "S", "c", "C", "p", "a", "A",
    ]
    private static let lengths: Set<Unicode.Scalar> = ["l", "h", "z", "q", "j", "t", "L"]
    /// The space flag is left out: see testWhatOpensNoSubstitutionIsReadAsItStands.
    private static let flags: Set<Unicode.Scalar> = ["-", "+", "#"]
    private static let rightToLeftRanges: [ClosedRange<UInt32>] = [
        0x0590...0x08FF, 0xFB1D...0xFDFF, 0xFE70...0xFEFF,
    ]

    /// Where `text` carries an invisible character with no work to do there.
    public static func strayMark(_ text: String,
                                 rightToLeft: Bool) -> (offset: Int, scalar: Unicode.Scalar)? {
        let scalars = Array(text.unicodeScalars)
        for index in scalars.indices where hidden(scalars[index]) {
            let scalar = scalars[index]
            if rightToLeft {
                if scalar == joiner, separates(scalars, index) { continue }
                if directions.contains(scalar),
                   chord(scalars, index)
                    || (carries(scalars, index)
                        && (steers(scalars, index) || turns(scalars, index))) { continue }
            }
            return (index, scalar)
        }
        return nil
    }

    public static func stray(_ text: String, rightToLeft: Bool) -> Bool {
        strayMark(text, rightToLeft: rightToLeft) != nil
    }

    /// The first line of `text` that holds right-to-left words yet opens left
    /// to right, or nil when none does.
    public static func openingLeftToRight(_ text: String) -> String? {
        let scalars = Array(text.unicodeScalars)
        var head = 0
        while head <= scalars.count {
            var end = head
            while end < scalars.count, !lineEnds.contains(scalars[end]) { end += 1 }
            let line = reading(scalars, from: head, upTo: end)
            if line.first == .leftToRight, line.holdsRightToLeft {
                return String(String.UnicodeScalarView(scalars[head..<end]))
            }
            head = end + 1
        }
        return nil
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

    private static func inSubstitution(_ scalars: [Unicode.Scalar], _ index: Int) -> Bool {
        var scan = lineStart(scalars, index)
        while scan <= index, scan < scalars.count, !lineEnds.contains(scalars[scan]) {
            guard let past = substitution(scalars, scan) else { scan += 1; continue }
            if index < past { return true }
            scan = past
        }
        return false
    }

    private static func chord(_ scalars: [Unicode.Scalar], _ index: Int) -> Bool {
        modifier(scalars, from: index + 1, step: 1) || modifier(scalars, from: index - 1, step: -1)
    }

    private static func modifier(_ scalars: [Unicode.Scalar], from start: Int, step: Int) -> Bool {
        var next = start
        while next >= 0, next < scalars.count {
            let scalar = scalars[next]
            if breaks.contains(scalar) { return false }
            if HangingWords.modifiers.contains(Character(scalar)) { return true }
            if scalar.properties.isAlphabetic || scalar.properties.numericType != nil { return false }
            next += step
        }
        return false
    }

    private static func carries(_ scalars: [Unicode.Scalar], _ index: Int) -> Bool {
        reading(scalars, from: lineStart(scalars, index)).holdsRightToLeft
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
            if inSubstitution(scalars, next) { return true }
            if scalar.properties.isAlphabetic { return !runsRightToLeft(scalar) }
            if scalar.properties.numericType != nil { return true }
            next += step
        }
        return false
    }

    private static func turns(_ scalars: [Unicode.Scalar], _ index: Int) -> Bool {
        guard strength(scalars[index]) == .rightToLeft else { return false }
        let head = lineStart(scalars, index)
        guard reading(scalars, from: head, upTo: index).first == nil else { return false }
        let ahead = reading(scalars, from: index + 1)
        return ahead.first == .leftToRight && ahead.holdsRightToLeft
    }

    private static func lineStart(_ scalars: [Unicode.Scalar], _ index: Int) -> Int {
        var head = index
        while head > 0, !lineEnds.contains(scalars[head - 1]) { head -= 1 }
        return head
    }

    private static func reading(_ scalars: [Unicode.Scalar],
                                from start: Int,
                                upTo limit: Int? = nil) -> (first: Side?,
                                                            holdsRightToLeft: Bool) {
        var index = start
        let end = min(limit ?? scalars.count, scalars.count)
        var depth = 0
        var first: Side?
        while index < end {
            let scalar = scalars[index]
            if lineEnds.contains(scalar) { break }
            if isolates.contains(scalar) { depth += 1; index += 1; continue }
            if scalar == popIsolate { depth = max(0, depth - 1); index += 1; continue }
            if depth > 0 { index += 1; continue }
            if let past = substitution(scalars, index) { index = past; continue }
            if let side = strength(scalar) {
                if first == nil { first = side }
                if side == .rightToLeft, !directions.contains(scalar) {
                    return (first, true)
                }
            }
            index += 1
        }
        return (first, false)
    }

    /// Reads wider than `Substitutions.all` on purpose: SPEC: docs/spec.md.
    private static func substitution(_ scalars: [Unicode.Scalar], _ index: Int) -> Int? {
        if scalars[index] == "{" {
            var next = index + 1
            while next < scalars.count, scalars[next] != "}", scalars[next] != "{",
                  !lineEnds.contains(scalars[next]) { next += 1 }
            return next < scalars.count && scalars[next] == "}" ? next + 1 : nil
        }
        guard scalars[index] == "%" else { return nil }
        var next = index + 1
        if next < scalars.count, scalars[next] == "%" { return next + 1 }
        var argument = next
        while argument < scalars.count, digit(scalars[argument]) { argument += 1 }
        if argument > next, argument < scalars.count, scalars[argument] == "$" { next = argument + 1 }
        while next < scalars.count, flags.contains(scalars[next]) { next += 1 }
        while next < scalars.count, digit(scalars[next]) { next += 1 }
        if next < scalars.count, scalars[next] == "." {
            next += 1
            while next < scalars.count, digit(scalars[next]) { next += 1 }
        }
        while next < scalars.count, lengths.contains(scalars[next]) { next += 1 }
        guard next < scalars.count, conversions.contains(scalars[next]) else { return nil }
        return next + 1
    }

    private static func digit(_ scalar: Unicode.Scalar) -> Bool {
        ("0"..."9").contains(scalar)
    }

    private static func strength(_ scalar: Unicode.Scalar) -> Side? {
        if scalar == "\u{200E}" { return .leftToRight }
        if scalar == "\u{200F}" || scalar == "\u{061C}" { return .rightToLeft }
        guard scalar.properties.isAlphabetic else { return nil }
        return runsRightToLeft(scalar) ? .rightToLeft : .leftToRight
    }

    private static func runsRightToLeft(_ scalar: Unicode.Scalar) -> Bool {
        rightToLeftRanges.contains { $0.contains(scalar.value) }
    }
}
