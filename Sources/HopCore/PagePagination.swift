import Foundation

/// Cutting one very tall page into sheets of paper.
/// SPEC: docs/spec.md — "Converter: web pages", the pdf is cut into sheets.
public enum PagePagination {
    /// The most sheets one page may become; past it a page is refused.
    public static let pageLimit = 2000

    public struct Plan {
        /// How much the source is shrunk to fit the sheet's width.
        public let scale: Double
        public let pageCount: Int
        private let sourceStride: Double

        fileprivate init(scale: Double, pageCount: Int, sourceStride: Double) {
            self.scale = scale
            self.pageCount = pageCount
            self.sourceStride = sourceStride
        }

        /// The top of sheet `index`, measured down the source page.
        public func sourceOffset(ofPage index: Int) -> Double {
            Double(index) * sourceStride
        }
    }

    public static func plan(
        contentWidth: Double, contentHeight: Double,
        printableWidth: Double, printableHeight: Double
    ) -> Plan? {
        guard contentWidth > 0, contentHeight > 0,
              printableWidth > 0, printableHeight > 0 else { return nil }
        let scale = min(1, printableWidth / contentWidth)
        let scaledHeight = contentHeight * scale
        let pages = Int((scaledHeight / printableHeight).rounded(.up))
        let pageCount = max(1, pages)
        guard pageCount <= pageLimit else { return nil }
        return Plan(scale: scale, pageCount: pageCount,
                    sourceStride: printableHeight / scale)
    }
}
