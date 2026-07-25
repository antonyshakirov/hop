import Foundation

/// Recovering STRUCTURE from documents that do not carry it. A .docx knows its
/// paragraph styles only loosely and a .pdf stores layout rather than meaning,
/// so headings and lists have to be inferred from what is measurable: type
/// size, weight, and the characters a line starts with.
///
/// These are honest heuristics, not a parser. They live here so their behaviour
/// is pinned by tests instead of drifting inside a conversion routine.
public enum DocumentHeuristics {
    /// The document's body size: the most common line size, ties going to the
    /// SMALLER one (body text is the floor of a document, headings the exception).
    /// nil for an empty document.
    public static func bodySize(_ sizes: [Double]) -> Double? {
        guard !sizes.isEmpty else { return nil }
        var counts: [Double: Int] = [:]
        for size in sizes {
            // a tenth of a point is below anything a reader can see, and it
            // keeps near-identical sizes from splitting the vote
            counts[(size * 10).rounded() / 10, default: 0] += 1
        }
        let best = counts.max { left, right in
            left.value != right.value ? left.value < right.value : left.key > right.key
        }
        return best?.key
    }

    /// Heading level for a line, or nil when it is body text. The thresholds are
    /// ratios rather than absolute sizes, so a 10pt document and a 14pt one both
    /// work. A line that is merely BOLD at body size counts as the deepest
    /// heading — that is how most people write a subheading in Word.
    public static func headingLevel(size: Double, body: Double, bold: Bool = false) -> Int? {
        guard body > 0 else { return nil }
        let ratio = size / body
        if ratio >= 1.6 { return 1 }
        if ratio >= 1.3 { return 2 }
        if ratio >= 1.12 { return 3 }
        return bold && ratio >= 0.98 ? 3 : nil
    }

    /// A list line split into its marker and its content, or nil when the line
    /// is not a list item. Covers what word processors and pdf exporters emit:
    /// bullets (•, ‣, –, -, *) and numbers ("1." / "1)").
    public struct ListItem: Equatable {
        public let ordered: Bool
        public let number: Int?
        public let text: String
    }

    public static func listItem(_ line: String) -> ListItem? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        for marker in ["• ", "‣ ", "◦ ", "– ", "- ", "* "] where trimmed.hasPrefix(marker) {
            let text = String(trimmed.dropFirst(marker.count)).trimmingCharacters(in: .whitespaces)
            return text.isEmpty ? nil : ListItem(ordered: false, number: nil, text: text)
        }
        // At most two digits: a document's numbered list does not reach 100, but
        // prose does start with a year ("2026. was a year"), and reading that as
        // item number 2026 would mangle it.
        let digits = trimmed.prefix { $0.isNumber }
        if !digits.isEmpty, digits.count <= 2, let number = Int(digits) {
            let rest = trimmed.dropFirst(digits.count)
            if rest.hasPrefix(". ") || rest.hasPrefix(") ") {
                let text = String(rest.dropFirst(2)).trimmingCharacters(in: .whitespaces)
                if !text.isEmpty { return ListItem(ordered: true, number: number, text: text) }
            }
        }
        return nil
    }

    /// Whether `next` is the CONTINUATION of a line that was wrapped, rather
    /// than a new paragraph. A pdf stores one text run per visual line, so
    /// without this every wrapped sentence would come out as its own paragraph.
    ///
    /// The rule is deliberately cautious: a line that ended a sentence starts a
    /// new paragraph, and a line that starts with a capital, a bullet or a digit
    /// is treated as a fresh one. Everything else continues.
    public static func continuesParagraph(previous: String, next: String) -> Bool {
        let left = previous.trimmingCharacters(in: .whitespaces)
        let right = next.trimmingCharacters(in: .whitespaces)
        guard !left.isEmpty, !right.isEmpty else { return false }
        // sentence-final punctuation (and the closing quotes that follow it)
        if let last = left.last, ".?!:;»”\"".contains(last) { return false }
        guard let first = right.first else { return false }
        if first.isUppercase || first.isNumber { return false }
        if listItem(right) != nil { return false }
        return first.isLetter || first == "(" || first == "«" || first == "\u{201C}"
    }

    /// A line that is nothing but rule characters — em dashes, hyphens,
    /// underscores — which a converted document uses as a separator.
    public static func isRuleLine(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.count >= 3 else { return false }
        return trimmed.allSatisfy { "-—–_⸻⸺=*".contains($0) }
    }

    /// Whether a line looks like a heading by SHAPE, used when no size
    /// information is available at all: short, no sentence-ending punctuation.
    /// Kept conservative — a wrong heading is more annoying than a missed one.
    public static func looksLikeHeading(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, trimmed.count <= 60 else { return false }
        guard !trimmed.hasSuffix(".") , !trimmed.hasSuffix(","), !trimmed.hasSuffix(";") else {
            return false
        }
        // a line of a few words, not a sentence
        return trimmed.split(separator: " ").count <= 8
    }
}
