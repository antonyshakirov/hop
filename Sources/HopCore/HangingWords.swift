/// A line never ends on a short word and never starts on one that leans back.
/// SPEC: docs/spec.md — "Localization".
/// Tests: Tests/HopCoreTests/HangingWordsTests.swift
public enum HangingWords {
    /// A joined run stops here: past this length an unbreakable piece is worse
    /// than the hanging word it was meant to cure.
    public static let runLimit = 16

    private static let modifiers: Set<Character> = ["⌘", "⌥", "⌃", "⇧", "⇪", "⎋", "⏎", "⌫"]

    private static let breaks: Set<Character> = [" ", "\u{00A0}"]
    private static let marks: Set<Unicode.Scalar> = ["\u{200E}", "\u{200F}", "\u{061C}"]
    private static let opening = "«„“\"'‘(["
    private static let punctuation: Set<Unicode.GeneralCategory> = [
        .connectorPunctuation, .dashPunctuation, .openPunctuation, .closePunctuation,
        .initialPunctuation, .finalPunctuation, .otherPunctuation]
    private static let closing = "»”“\"'’)]…,.;:!?"
    private static let conversions: Set<Character> = ["@", "d", "i", "u", "f", "g", "x", "X"]
    private static let lengths: Set<Character> = ["l", "h", "z", "q", "j", "t", "L"]

    /// `text` with every join the rule asks for, and with the joins it does not
    /// ask for taken back out. `trailing` holds the words that lean on the word
    /// before them rather than the one after.
    public static func glued(_ text: String,
                             shortWords: Set<String>,
                             trailing: Set<String> = []) -> String {
        lines(text)
            .map { glueLine(normalizeLine($0, shortWords, trailing), shortWords, trailing) }
            .joined(separator: "\n")
    }

    /// `text` with the joins this rule owns turned back into ordinary spaces, so
    /// what the rule would write can be measured against what a table holds.
    public static func normalized(_ text: String,
                                  shortWords: Set<String>,
                                  trailing: Set<String> = []) -> String {
        lines(text)
            .map { normalizeLine($0, shortWords, trailing) }
            .joined(separator: "\n")
    }

    private static func normalizeLine(_ line: String,
                                      _ short: Set<String>,
                                      _ trailing: Set<String>) -> String {
        let (tokens, separators) = split(line)
        guard !separators.isEmpty else { return line }
        var out = tokens[0]
        var chorded = false
        var carried = false
        for index in separators.indices {
            let owned = separators[index] == "\u{00A0}"
                && (!chordTail(tokens[index]).isEmpty
                    || chorded
                    || carried
                    || short.contains(bare(tokens[index]))
                    || trailing.contains(stem(tokens[index]))
                    || trailing.contains(stem(tokens[index + 1])))
            chorded = !chordTail(tokens[index]).isEmpty
            carried = owned && !holdsLetter(tokens[index + 1])
            out.append(owned ? " " : separators[index])
            out += tokens[index + 1]
        }
        return out
    }

    private static func glueLine(_ line: String,
                                 _ short: Set<String>,
                                 _ trailing: Set<String>) -> String {
        let parts = line.split(separator: " ", omittingEmptySubsequences: false).map(String.init)
        var out = parts.first ?? line
        var previous = out
        var run = out.count
        var carried = false
        for token in parts.dropFirst() {
            let tail = chordTail(previous)
            let chord = !tail.isEmpty
            let base = chord && tail.count < previous.count ? tail.count : run
            let leans = trailing.contains(stem(token))
            let wanted = chord || carried || leans || short.contains(bare(previous))
            let key = chord ? chordKey(token) : ""
            let reach = key.isEmpty || key.count >= token.count ? token.count : key.count
            let cost = leans ? token.count : base + 1 + reach
            let joins = wanted
                && !previous.isEmpty && !token.isEmpty
                && !isPunctuation(token) && !substituted(token)
                && (leans || (!isPunctuation(previous) && !substituted(previous)))
                && cost <= runLimit
            out += (joins ? "\u{00A0}" : " ") + token
            run = joins ? base + 1 + reach : token.count
            carried = joins && !holdsLetter(token) && !endsPhrase(token)
            previous = token
        }
        return out
    }

    private static func lines(_ text: String) -> [String] {
        text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
    }

    private static func split(_ line: String) -> ([String], [Character]) {
        var tokens: [String] = []
        var separators: [Character] = []
        var current = ""
        for character in line {
            if breaks.contains(character) {
                tokens.append(current)
                separators.append(character)
                current = ""
            } else {
                current.append(character)
            }
        }
        tokens.append(current)
        return (tokens, separators)
    }

    private static func substituted(_ token: String) -> Bool {
        if token.contains("{n}") || token.contains("{sym:") { return true }
        var rest = Substring(token)
        while let percent = rest.firstIndex(of: "%") {
            var index = rest.index(after: percent)
            while index < rest.endIndex, rest[index].isNumber { index = rest.index(after: index) }
            if index < rest.endIndex, rest[index] == "$" { index = rest.index(after: index) }
            while index < rest.endIndex, lengths.contains(rest[index]) {
                index = rest.index(after: index)
            }
            if index < rest.endIndex, conversions.contains(rest[index]) { return true }
            rest = rest[rest.index(after: percent)...]
        }
        return false
    }

    private static func chordTail(_ token: String) -> String {
        var tail = ""
        for scalar in token.unicodeScalars.reversed() {
            if marks.contains(scalar) { continue }
            guard modifiers.contains(Character(scalar)) else { break }
            tail.append(Character(scalar))
        }
        return tail
    }

    private static func chordKey(_ token: String) -> String {
        var key = ""
        for scalar in token.unicodeScalars {
            if marks.contains(scalar) { continue }
            let character = Character(scalar)
            guard scalar.isASCII, character.isLetter || character.isNumber else { break }
            key.append(character)
        }
        return key
    }

    /// True when a modifier stands in front of an ordinary space, so the chord
    /// can break across two lines.
    public static func chordBreaks(_ text: String) -> Bool {
        var previous: Character?
        for character in text {
            if character.unicodeScalars.count == 1,
               let scalar = character.unicodeScalars.first, marks.contains(scalar) { continue }
            if character == " ", let last = previous, modifiers.contains(last) { return true }
            previous = character
        }
        return false
    }

    private static func endsPhrase(_ token: String) -> Bool {
        guard let last = token.last else { return false }
        return closing.contains(last)
    }

    private static func holdsLetter(_ token: String) -> Bool {
        token.unicodeScalars.contains { $0.properties.isAlphabetic }
    }

    private static func isPunctuation(_ token: String) -> Bool {
        let body = token.unicodeScalars.filter { !marks.contains($0) }
        return body.isEmpty || body.allSatisfy {
            punctuation.contains($0.properties.generalCategory)
        }
    }

    private static func bare(_ token: String) -> String {
        var word = Substring(String(String.UnicodeScalarView(
            token.unicodeScalars.filter { !marks.contains($0) })))
        while let first = word.first, opening.contains(first) { word = word.dropFirst() }
        if let mark = word.lastIndex(where: { $0 == "'" || $0 == "\u{2019}" }) {
            word = word[word.index(after: mark)...]
        }
        return word.lowercased()
    }

    private static func stem(_ token: String) -> String {
        var word = Substring(bare(token))
        while let last = word.last, closing.contains(last) { word = word.dropLast() }
        return String(word)
    }
}
