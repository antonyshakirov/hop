import Foundation

/// Matching text lines to the type sizes a PDF page actually painted with.
///
/// Reading a page as an attributed string hands the whole layout engine a job
/// it does not need to do: the converter wants one number per line (how big is
/// this type) and one flag (is it bold), and pays for fonts being resolved and
/// substituted for every run on the page. The sizes are in the page's own
/// content stream, which can be walked for a fraction of the cost, and the text
/// itself still comes from PDFKit, which knows how to decode it.
///
/// What is left is the join: the content stream gives painted segments with a
/// baseline, the text gives lines with a box around them, and these rules put
/// the two together. Everything here is arithmetic on numbers the caller
/// measured, so it is testable without a PDF in hand.
public enum PDFLineMetrics {
    /// A run of text the page painted: where its baseline sat, how it was set,
    /// and how many glyphs it carried — the glyph count is what decides which
    /// of several runs on one line describes that line.
    public struct Segment: Equatable {
        public let y: Double
        public let size: Double
        public let bold: Bool
        public let glyphs: Int

        public init(y: Double, size: Double, bold: Bool, glyphs: Int) {
            self.y = y
            self.size = size
            self.bold = bold
            self.glyphs = glyphs
        }
    }

    /// The vertical extent of a line of text, as the reader sees it.
    public struct LineBox: Equatable {
        public let minY: Double
        public let maxY: Double

        public init(minY: Double, maxY: Double) {
            self.minY = minY
            self.maxY = maxY
        }
    }

    /// How a line was set. `nil` for a line nothing was found for.
    public struct Metric: Equatable {
        public let size: Double
        public let bold: Bool

        public init(size: Double, bold: Bool) {
            self.size = size
            self.bold = bold
        }
    }

    /// A baseline sits inside the box of its own line, but the two are measured
    /// by different machinery and disagree by a fraction of a point. This is how
    /// much slack the box is given at each edge — small enough that the line
    /// above never lends its size to the line below.
    public static let slack: Double = 1.5

    /// The size and weight of each line. A segment belongs to a line when its
    /// baseline falls inside that line's box, and where several sizes share one
    /// line the one carrying the MOST TEXT wins: a heading followed by a small
    /// footnote mark is a heading, and a body line beside a large decorative
    /// character is still body text. Lines with nothing inside them come back
    /// nil, and the caller decides whether that is rare enough to live with.
    public static func match(
        lines: [LineBox], segments: [Segment], slack: Double = slack
    ) -> [Metric?] {
        guard !segments.isEmpty else { return Array(repeating: nil, count: lines.count) }
        let sorted = segments.sorted { $0.y < $1.y }
        let positions = sorted.map(\.y)
        return lines.map { line in
            var index = lowerBound(positions, line.minY - slack)
            // glyphs painted at each (size, weight) inside this line's box
            var weights: [Metric: Int] = [:]
            while index < sorted.count, sorted[index].y <= line.maxY + slack {
                let segment = sorted[index]
                let key = Metric(size: (segment.size * 10).rounded() / 10, bold: segment.bold)
                // a run with no glyphs still says how the line is set, so it
                // counts for something rather than nothing
                weights[key, default: 0] += max(segment.glyphs, 1)
                index += 1
            }
            // ties go to the larger size: a heading split into equal halves by a
            // line break reads better as a heading than as body text
            return weights.max { left, right in
                left.value != right.value ? left.value < right.value : left.key.size < right.key.size
            }?.key
        }
    }

    /// Share of lines that found a size, 0...1. A page whose text lives inside
    /// form objects, or one drawn in a way this walk does not follow, comes out
    /// low here and the caller falls back to the slow, complete path — a
    /// document read the fast way must not quietly lose its headings.
    public static func coverage(_ metrics: [Metric?]) -> Double {
        guard !metrics.isEmpty else { return 0 }
        return Double(metrics.filter { $0 != nil }.count) / Double(metrics.count)
    }

    /// Below this share of matched lines the page is re-read the slow way.
    /// Nine tenths: the fast reading is meant to answer for a page completely,
    /// and a page missing a tenth of its lines has likely lost a heading.
    public static let coverageFloor: Double = 0.9

    /// A font name says bold when the type is: PDF names carry the style in the
    /// name itself ("Helvetica-Bold", "ArialMT,Bold", "AAAAAB+Inter-SemiBold"),
    /// and the subset prefix in front of a plus sign is noise.
    public static func isBold(fontName: String) -> Bool {
        let name = fontName.split(separator: "+").last.map(String.init) ?? fontName
        let lower = name.lowercased()
        // "semibold" and "extrabold" read as bold; "boldface" as a family name
        // does not exist in practice, so a plain substring is enough here
        if lower.contains("bold") || lower.contains("black") || lower.contains("heavy") {
            return true
        }
        // the terse convention: a ",B" or "-B" suffix, as in "Times,B"
        return lower.hasSuffix(",b") || lower.hasSuffix("-b")
    }

    private static func lowerBound(_ values: [Double], _ target: Double) -> Int {
        var low = 0
        var high = values.count
        while low < high {
            let mid = (low + high) / 2
            if values[mid] < target { low = mid + 1 } else { high = mid }
        }
        return low
    }
}

extension PDFLineMetrics.Metric: Hashable {}
