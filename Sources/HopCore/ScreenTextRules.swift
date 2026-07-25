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
