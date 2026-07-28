import Foundation

/// Writing systems, as far as recognition needs to tell them apart.
public enum TextScript: String, Sendable, CaseIterable {
    case latin, cyrillic, cjk, hangul, arabic, thai

    /// Digits, punctuation and symbols belong to nobody and are ignored.
    static func of(_ scalar: Unicode.Scalar) -> TextScript? {
        switch scalar.value {
        case 0x0041...0x024F: return .latin
        case 0x0400...0x04FF: return .cyrillic
        case 0x3000...0x30FF, 0x3400...0x9FFF, 0xF900...0xFAFF: return .cjk
        case 0xAC00...0xD7AF: return .hangul
        case 0x0600...0x06FF, 0x0750...0x077F: return .arabic
        case 0x0E00...0x0E7F: return .thai
        default: return nil
        }
    }

    /// The Vision tag to ask for when this script has to be read explicitly.
    public var recognitionTag: String {
        switch self {
        case .latin: return "en-US"
        case .cyrillic: return "ru-RU"
        case .cjk: return "ja-JP"
        case .hangul: return "ko-KR"
        case .arabic: return "ar-SA"
        case .thai: return "th-TH"
        }
    }
}

/// One recognised word with enough position to line it up against the same word
/// read by a different pass.
public struct TextFragment: Equatable, Sendable {
    public let text: String
    /// Left edge in Vision's normalised image coordinates.
    public let x: Double
    /// Index of the line this word belongs to, in reading order.
    public let line: Int

    public init(text: String, x: Double, line: Int) {
        self.text = text
        self.x = x
        self.line = line
    }
}

/// Repairs the one thing automatic recognition cannot do: a line carrying two
/// distant scripts at once.
///
/// Vision picks ONE language model per text region, and a line IS a region. So a
/// line reading "Hello 世界" followed by two Cyrillic words comes back with the
/// ideographs right and the Cyrillic as noise — `门puBeT MMp`. Asking for Russian
/// instead flips the damage: the Cyrillic lands and the ideographs vanish.
///
/// The fix is not a better guess but a rule: **a pass may only be trusted on the
/// scripts it was actually reading**. So a second pass is run for the scripts the
/// first one was NOT specialised in, and each word is taken from whichever pass
/// had the competence to read it. Everything else — a clean line, a page in one
/// script — is left exactly as the first pass produced it, and the second pass is
/// not even run.
public enum ScriptMerge {

    /// The scripts a word contains. Empty for digits and punctuation.
    public static func scripts(in word: String) -> Set<TextScript> {
        var out: Set<TextScript> = []
        for scalar in word.unicodeScalars {
            if let script = TextScript.of(scalar) { out.insert(script) }
        }
        return out
    }

    /// What a pass turned out to be reading, weighted by how many characters each
    /// script accounts for. Capped at three: past that it is noise, not a page.
    public static func competence(of fragments: [TextFragment], limit: Int = 3) -> Set<TextScript> {
        var weight: [TextScript: Int] = [:]
        for fragment in fragments {
            for script in scripts(in: fragment.text) {
                weight[script, default: 0] += fragment.text.count
            }
        }
        return Set(weight.sorted { $0.value > $1.value }.prefix(limit).map(\.key))
    }

    /// A word mixing two scripts inside itself is the signature of a wrong-language
    /// reading — no real word does it.
    public static func isGarbled(_ word: String) -> Bool {
        scripts(in: word).count > 1
    }

    /// Lines that need a second opinion: exactly the ones carrying such a word.
    public static func garbledLines(_ fragments: [TextFragment]) -> Set<Int> {
        Set(fragments.filter { isGarbled($0.text) }.map(\.line))
    }

    /// What to ask the second pass for.
    ///
    /// Two tags, no more — naming many languages makes Vision worse, not better.
    /// The pick is not "everything the first pass missed": it is the ALPHABETIC
    /// scripts on the picture, because the damage always runs the same way. A CJK
    /// model swallows the alphabet next to it — a Cyrillic word comes back as a
    /// jumble of ideographs and Latin letters — while an alphabetic model merely
    /// drops the ideographs it cannot read. So the helper
    /// reads alphabets, the first pass keeps the ideographs, and each word ends up
    /// with the pass that could read it.
    ///
    /// The reader's own script leads: a screen usually mixes a foreign page with
    /// the viewer's own tongue.
    public static func helperLanguages(seen: Set<TextScript>, dominant: TextScript?,
                                       interface: TextScript, supported: [String],
                                       limit: Int = 2) -> [String] {
        let alphabetic: [TextScript] = [.cyrillic, .arabic, .thai, .hangul, .latin]
        var wanted: [TextScript] = []
        // First: alphabets that ARE on the picture but were not what the first
        // pass specialised in — those are the ones it mangled.
        for script in alphabetic where seen.contains(script) && script != dominant {
            wanted.append(script)
        }
        // Then Latin, which almost every page carries some of.
        if !wanted.contains(.latin) { wanted.append(.latin) }
        // Then the reader's own script: a page whose alphabet was mangled beyond
        // recognition leaves no trace of itself in `seen`, and this is the only
        // hint left about what it might have been.
        if !wanted.contains(interface) { wanted.append(interface) }
        for script in seen where !wanted.contains(script) { wanted.append(script) }

        var tags: [String] = []
        for script in wanted {
            let tag = script.recognitionTag
            if supported.contains(tag), !tags.contains(tag) { tags.append(tag) }
            if tags.count == limit { break }
        }
        return tags
    }

    /// The script a pass mostly read — the one it can be trusted on.
    public static func dominant(of fragments: [TextFragment]) -> TextScript? {
        var weight: [TextScript: Int] = [:]
        for fragment in fragments {
            for script in scripts(in: fragment.text) {
                weight[script, default: 0] += fragment.text.count
            }
        }
        return weight.max { $0.value < $1.value }?.key
    }

    /// A fragment can be believed when every script in it is one the pass was
    /// reading, and it does not mix scripts inside itself.
    public static func trusted(_ word: String, competence: Set<TextScript>) -> Bool {
        let found = scripts(in: word)
        if found.isEmpty { return true }        // digits and punctuation: anyone reads those
        if found.count > 1 { return false }
        return found.isSubset(of: competence)
    }

    /// Rebuilds the lines, taking each word from whichever pass could read it.
    ///
    /// Word ORDER always comes from the first pass, never from the x coordinate:
    /// sorting by x reverses a right-to-left line, which turned a correct Arabic
    /// line into a backwards one.
    public static func merge(primary: [TextFragment], helper: [TextFragment],
                             helperCompetence: Set<TextScript>) -> [String] {
        let suspect = garbledLines(primary)
        let lines = Set(primary.map(\.line)).sorted()
        return lines.map { line in
            let words = primary.filter { $0.line == line }
            guard suspect.contains(line) else { return words.map(\.text).joined(separator: " ") }
            let twins = helper.filter { $0.line == line }
            return words.map { word -> String in
                guard let twin = twins.min(by: { abs($0.x - word.x) < abs($1.x - word.x) }),
                      abs(twin.x - word.x) < 0.02 else { return word.text }
                let found = scripts(in: word.text)
                // In a line already known to be garbled, the specialist wins for
                // every word whose script it reads — and for anything mangled.
                let helperOwnsIt = !found.isEmpty && found.isSubset(of: helperCompetence)
                let shouldReplace = helperOwnsIt || found.count > 1
                return shouldReplace && trusted(twin.text, competence: helperCompetence)
                    ? twin.text : word.text
            }.joined(separator: " ")
        }
    }
}
