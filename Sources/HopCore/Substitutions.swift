/// SPEC: docs/spec.md — "Localization".
/// Tests: Tests/HopCoreTests/SubstitutionsTests.swift
public enum Substitutions {
    /// `text` with `values` put in at `%1$@`, `%2$@` and so on, each fenced off
    /// by `isolate`; anything else opening with a per cent sign prints itself.
    public static func fill(_ text: String, _ values: [String]) -> String {
        var out = ""
        var index = text.startIndex
        while let mark = text[index...].firstIndex(of: "%") {
            out += text[index..<mark]
            index = text.index(after: mark)
            var place = 0
            while index < text.endIndex, let digit = figure(text[index]) {
                place = min(place * 10 + digit, values.count + 1)
                index = text.index(after: index)
            }
            var closing = index
            if index < text.endIndex, text[index] == "$" { closing = text.index(after: index) }
            guard place > 0, place <= values.count, closing > index,
                  closing < text.endIndex, text[closing] == "@" else { out += text[mark..<index]; continue }
            out += isolate(values[place - 1])
            index = text.index(after: closing)
        }
        out += text[index...]
        return out
    }

    /// `text` with `value` put in at every `%@`, fenced off by `isolate`.
    public static func fill(_ text: String, _ value: String) -> String {
        text.replacingOccurrences(of: "%@", with: isolate(value))
    }

    /// `value` fenced in Unicode isolates, so it can only ever reorder itself.
    public static func isolate(_ value: String) -> String {
        "\u{2068}" + plain(value) + "\u{2069}"
    }

    /// `value` fenced and trimmed, or `fallback` when nothing is left to read.
    public static func isolate(_ value: String, or fallback: String) -> String {
        var kept = Substring(plain(value))
        while let first = kept.first, first.isWhitespace { kept = kept.dropFirst() }
        while let last = kept.last, last.isWhitespace { kept = kept.dropLast() }
        return kept.isEmpty ? fallback : "\u{2068}" + kept + "\u{2069}"
    }

    /// What `isolate` fences: `value` with its direction controls out and every
    /// line break folded to a space. Why both: testTheFenceSurvivesALineTheValueBreaks.
    public static func plain(_ value: String) -> String {
        var out = ""
        for character in value {
            if character.isNewline { out.append(" "); continue }
            out.unicodeScalars.append(contentsOf: character.unicodeScalars.filter {
                !(0x2066...0x2069).contains($0.value) && !(0x202A...0x202E).contains($0.value)
            })
        }
        return out
    }

    /// The substitutions `text` is written with, sorted, repeats kept: exactly
    /// what `fill` puts a value into, and no more.
    public static func all(_ text: String) -> [String] {
        var out: [String] = []
        var index = text.startIndex
        while index < text.endIndex {
            let character = text[index]
            if character == "{", let close = brace(text, index) {
                out.append(String(text[index...close]))
                index = text.index(after: close)
                continue
            }
            if character == "%", let close = placeholder(text, index) {
                out.append(String(text[index...close]))
                index = text.index(after: close)
                continue
            }
            index = text.index(after: index)
        }
        return out.sorted()
    }

    private static func brace(_ text: String, _ index: String.Index) -> String.Index? {
        var scan = text.index(after: index)
        while scan < text.endIndex {
            if text[scan] == "}" { return scan }
            if text[scan] == "{" || text[scan].isNewline { return nil }
            scan = text.index(after: scan)
        }
        return nil
    }

    private static func placeholder(_ text: String, _ index: String.Index) -> String.Index? {
        var scan = text.index(after: index)
        var place = 0, digits = 0
        while scan < text.endIndex, let digit = figure(text[scan]) {
            place = min(place * 10 + digit, 1000)
            digits += 1
            scan = text.index(after: scan)
        }
        if digits > 0 {
            guard place > 0, scan < text.endIndex, text[scan] == "$" else { return nil }
            scan = text.index(after: scan)
        }
        return scan < text.endIndex && text[scan] == "@" ? scan : nil
    }

    private static func figure(_ character: Character) -> Int? {
        guard character.unicodeScalars.count == 1,
              let scalar = character.unicodeScalars.first,
              scalar.value >= 0x30, scalar.value <= 0x39 else { return nil }
        return Int(scalar.value - 0x30)
    }
}
