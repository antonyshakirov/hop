import Foundation

/// Pure assembly of one screen-reading pass into a single clipboard entry.
/// Vision hands back text lines and barcode payloads separately; deciding what
/// the user actually meant to grab is a RULE, so it lives here with tests
/// instead of inside the capture controller.
public enum ScreenTextRules {
    /// The entry a pass becomes, or nil when there was nothing to read.
    ///
    /// A barcode WINS over text: framing a QR code is an unambiguous ask for its
    /// payload, and the caption printed next to it would only get in the way.
    /// Several codes in one selection are joined in the order found, duplicates
    /// dropped — a page repeating the same link is one entry.
    ///
    /// Text otherwise: lines in reading order, joined by newlines. Line breaks
    /// are KEPT deliberately — a table or a code snippet read off the screen is
    /// useless as one run-on line, and a paragraph pastes fine either way.
    /// Repeated text lines are NOT deduplicated: a table column really can have
    /// the same value twice, and silently dropping one would corrupt the reading.
    public static func assemble(lines: [String], barcodes: [String]) -> String? {
        let codes = trimmed(barcodes, dropDuplicates: true)
        if !codes.isEmpty { return codes.joined(separator: "\n") }
        let text = trimmed(lines, dropDuplicates: false)
        return text.isEmpty ? nil : text.joined(separator: "\n")
    }

    /// Indices of `boxes` in READING order — top to bottom, then left to right.
    /// Vision guarantees no order for its observations and its coordinate origin
    /// is bottom-left (y grows upward), so this is where the flip lives.
    ///
    /// Rows are quantized before comparing: two words sitting on the same visual
    /// line differ by a hair of vertical noise, and comparing raw midpoints would
    /// interleave them into nonsense. The bucket is 1/200 of the selection height
    /// — finer than any real line spacing, coarse enough to hold a line together.
    public static func readingOrder(_ boxes: [CGRect]) -> [Int] {
        let keys = boxes.map { box -> (row: Int, x: CGFloat) in
            (Int(((1 - box.midY) * 200).rounded()), box.minX)
        }
        // sort INDICES, and fall back to the original index so equal boxes keep a
        // stable, deterministic order (a valid strict ordering, no matter the input)
        return boxes.indices.sorted { left, right in
            let a = keys[left], b = keys[right]
            if a.row != b.row { return a.row < b.row }
            if a.x != b.x { return a.x < b.x }
            return left < right
        }
    }

    /// The first web address in a reading, ready to hand to a browser — or nil
    /// when there is nothing to open.
    ///
    /// A QR code on a bill or a poster carries a link, and the point of reading
    /// it on the Mac instead of pointing a phone at it is to FOLLOW it here
    /// (Anton, 2026-07-27). The same holds for an address printed in the text of
    /// a screenshot, so this looks at the whole reading rather than at barcodes
    /// alone.
    ///
    /// Only `http` and `https` are recognized. A scanned code is untrusted input
    /// and every other scheme hands it a lever: `file://` reaches the disk and a
    /// custom scheme reaches whatever app claimed it. A payload that is a phone
    /// number, an address book card or a Wi-Fi password stays plain text.
    public static func link(in text: String) -> String? {
        schemeLink(in: text) ?? bareHostLink(in: text)
    }

    /// An address that spells its scheme out: everything from `http://` to the
    /// first space or line break. Requiring the scheme is what keeps a reading
    /// of source code quiet — `readme.md` and `api.js` are host-shaped, and `.md`
    /// and `.js` are real top-level domains, so a looser match would offer to
    /// open a file name.
    private static func schemeLink(in text: String) -> String? {
        var best: String.Index?
        for scheme in ["http://", "https://"] {
            // searched on `text` itself, NOT on a lowercased copy: folding case
            // can change a string's length, and an index taken from the copy
            // would then point somewhere else in the original
            guard let found = text.range(of: scheme, options: [.caseInsensitive]) else { continue }
            // the earliest of the two — a line may hold one of each
            if best == nil || found.lowerBound < best! { best = found.lowerBound }
        }
        guard let start = best else { return nil }
        let rest = text[start...]
        let candidate = rest.prefix { !$0.isWhitespace && !$0.isNewline }
        let cleaned = strippingTrailingPunctuation(String(candidate))
        // "https://" and nothing after it is not an address
        guard let separator = cleaned.range(of: "://"),
              !cleaned[separator.upperBound...].isEmpty else { return nil }
        return cleaned
    }

    /// A whole reading that is nothing but a bare host — the shape of a QR code
    /// printed as `example.com/menu`. Deliberately narrow: it applies only when
    /// the ENTIRE reading is that one token, never to a word inside a sentence,
    /// so prose and file names are never promoted to links.
    private static func bareHostLink(in text: String) -> String? {
        let token = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty,
              !token.contains(where: { $0.isWhitespace || $0.isNewline }),
              // an e-mail address is host-shaped and must not open a browser
              !token.contains("@"),
              !token.contains(":") else { return nil }
        let cleaned = strippingTrailingPunctuation(token)
        let host = cleaned.prefix { $0 != "/" && $0 != "?" && $0 != "#" }
        let labels = host.split(separator: ".", omittingEmptySubsequences: false)
        guard labels.count >= 2,
              labels.allSatisfy({ !$0.isEmpty }),
              // a top-level domain is letters only, and at least two of them —
              // this is what rules out "1.5" and "v2.0"
              let tld = labels.last, tld.count >= 2,
              tld.allSatisfy({ $0.isLetter }),
              host.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "." || $0 == "-" })
        else { return nil }
        return "https://" + cleaned
    }

    /// Sentence punctuation that ends up glued to an address when it is read out
    /// of running text: "see https://example.com." must not open a dot.
    /// A closing bracket is kept when the address opened one itself, because a
    /// link really can carry balanced brackets in its path.
    private static func strippingTrailingPunctuation(_ value: String) -> String {
        var out = value
        let always: Set<Character> = [".", ",", ";", ":", "!", "?", "\"", "'", "»", ">"]
        while let last = out.last {
            if always.contains(last) {
                out.removeLast()
            } else if last == ")" && !out.contains("(") {
                out.removeLast()
            } else if last == "]" && !out.contains("[") {
                out.removeLast()
            } else {
                break
            }
        }
        return out
    }

    /// Trim every candidate and drop the empties; optionally remove later
    /// duplicates, keeping the first occurrence's position.
    private static func trimmed(_ values: [String], dropDuplicates: Bool) -> [String] {
        var seen = Set<String>()
        var out: [String] = []
        for value in values {
            let clean = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !clean.isEmpty else { continue }
            if dropDuplicates {
                guard !seen.contains(clean) else { continue }
                seen.insert(clean)
            }
            out.append(clean)
        }
        return out
    }
}
