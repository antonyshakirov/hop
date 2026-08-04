import CoreGraphics
import Foundation
import HopCore
import PDFKit

/// Reading how a PDF page is SET, without asking the layout engine.
///
/// The converter needs one number and one flag per line: the type size, and
/// whether it is bold. `PDFPage.attributedString` answers both, and pays for
/// the whole page to be laid out with every font resolved — measured at 4 ms
/// per page on ordinary documents and 15 ms on documents whose fonts macOS has
/// to substitute. The same two facts sit in the page's content stream as plain
/// numbers: walking it costs a quarter of a millisecond per page.
///
/// The walk is deliberately narrow. It follows the operators that place text
/// and nothing else: no glyph decoding (PDFKit's own `string` stays the source
/// of the text, so encodings and ligatures keep working), no colour, no paths.
/// Text drawn inside form objects is not followed, which is exactly why the
/// caller checks coverage and falls back to the slow path when a page comes out
/// half-read.

/// The scanner's callbacks are C function pointers, so the two helpers they use
/// live outside the type: a call through `Self` would count as captured context
/// and the closure would no longer convert.
private func scanState(_ info: UnsafeMutableRawPointer?) -> PDFContentScan.ScanState {
    Unmanaged<PDFContentScan.ScanState>.fromOpaque(info!).takeUnretainedValue()
}

private func popNumber(_ scanner: CGPDFScannerRef) -> Double {
    var value: CGPDFReal = 0
    return CGPDFScannerPopNumber(scanner, &value) ? Double(value) : 0
}

/// How much text a shown string carried. The bytes are not decoded — the count
/// is only ever compared against other runs on the same line, and a two-byte
/// encoding shortens every run on that line equally.
private func popStringLength(_ scanner: CGPDFScannerRef) -> Int {
    var string: CGPDFStringRef?
    guard CGPDFScannerPopString(scanner, &string), let string else { return 0 }
    return CGPDFStringGetLength(string)
}

/// The same for the array form, where the numbers between the strings are
/// kerning and carry no text.
private func popArrayLength(_ scanner: CGPDFScannerRef) -> Int {
    var array: CGPDFArrayRef?
    guard CGPDFScannerPopArray(scanner, &array), let array else { return 0 }
    var glyphs = 0
    for index in 0..<CGPDFArrayGetCount(array) {
        var string: CGPDFStringRef?
        if CGPDFArrayGetString(array, index, &string), let string {
            glyphs += CGPDFStringGetLength(string)
        }
    }
    return glyphs
}

enum PDFContentScan {
    /// Text segments of a page in PAGE coordinates, or nil when the page cannot
    /// be walked (no underlying CoreGraphics page, or a rotated one — a rotated
    /// page reports its text through PDFKit in a different frame, and matching
    /// the two would be guesswork).
    static func segments(of page: PDFPage) -> [PDFLineMetrics.Segment]? {
        guard page.rotation == 0, let cgPage = page.pageRef else { return nil }
        let state = ScanState(fonts: fontNames(of: cgPage))
        // PDFKit measures from the crop box's corner; the content stream is in
        // media box coordinates. On the vast majority of documents these are the
        // same rectangle, and where they are not this is the whole difference.
        let origin = page.bounds(for: .cropBox).origin
        state.originY = Double(origin.y)

        let table = CGPDFOperatorTableCreate()!
        install(into: table)
        let stream = CGPDFContentStreamCreateWithPage(cgPage)
        let scanner = CGPDFScannerCreate(stream, table, Unmanaged.passUnretained(state).toOpaque())
        CGPDFScannerScan(scanner)
        CGPDFScannerRelease(scanner)
        CGPDFContentStreamRelease(stream)
        CGPDFOperatorTableRelease(table)
        return state.segments
    }

    // MARK: - State carried through the walk

    /// The scanner's callbacks are C functions, so everything they touch lives
    /// here and travels as the info pointer.
    final class ScanState {
        let fonts: [String: String]        // resource name → base font name
        var originY: Double = 0

        var ctm = CGAffineTransform.identity
        var stack: [CGAffineTransform] = []
        var text = CGAffineTransform.identity      // Tm
        var line = CGAffineTransform.identity      // the line's own matrix
        var leading: Double = 0                    // TL
        var size: Double = 0                       // Tf
        var bold = false
        var segments: [PDFLineMetrics.Segment] = []

        init(fonts: [String: String]) { self.fonts = fonts }

        /// Where the current baseline sits on the page, and how big the type is
        /// once both matrices have had their say. `glyphs` is how much text the
        /// run carried, which is what settles a line painted in several sizes.
        func show(glyphs: Int) {
            let full = text.concatenating(ctm)
            let scale = (full.b * full.b + full.d * full.d).squareRoot()
            let painted = size * Double(scale)
            // a zero-size run is a rendering-mode trick (invisible OCR text over
            // a scan, for one) and tells us nothing about how the page is set
            guard painted > 0 else { return }
            segments.append(PDFLineMetrics.Segment(
                y: Double(full.ty) - originY, size: painted, bold: bold, glyphs: glyphs))
        }

        func newline(_ tx: Double, _ ty: Double) {
            line = line.translatedBy(x: CGFloat(tx), y: CGFloat(ty))
            text = line
        }
    }

    // MARK: - The operators that place text

    private static func install(into table: CGPDFOperatorTableRef) {
        CGPDFOperatorTableSetCallback(table, "q") { _, info in
            let state = scanState(info)
            state.stack.append(state.ctm)
        }
        CGPDFOperatorTableSetCallback(table, "Q") { _, info in
            let state = scanState(info)
            if let previous = state.stack.popLast() { state.ctm = previous }
        }
        CGPDFOperatorTableSetCallback(table, "cm") { scanner, info in
            let state = scanState(info)
            // the scanner hands operands back in reverse
            var v = [Double](repeating: 0, count: 6)
            for i in (0..<6).reversed() { v[i] = popNumber(scanner) }
            let matrix = CGAffineTransform(a: CGFloat(v[0]), b: CGFloat(v[1]), c: CGFloat(v[2]),
                                           d: CGFloat(v[3]), tx: CGFloat(v[4]), ty: CGFloat(v[5]))
            state.ctm = matrix.concatenating(state.ctm)
        }
        CGPDFOperatorTableSetCallback(table, "BT") { _, info in
            let state = scanState(info)
            state.text = .identity
            state.line = .identity
        }
        CGPDFOperatorTableSetCallback(table, "Tf") { scanner, info in
            let state = scanState(info)
            state.size = popNumber(scanner)
            var name: UnsafePointer<Int8>?
            if CGPDFScannerPopName(scanner, &name), let name {
                let resource = String(cString: name)
                state.bold = PDFLineMetrics.isBold(fontName: state.fonts[resource] ?? resource)
            }
        }
        CGPDFOperatorTableSetCallback(table, "TL") { scanner, info in
            scanState(info).leading = popNumber(scanner)
        }
        CGPDFOperatorTableSetCallback(table, "Tm") { scanner, info in
            let state = scanState(info)
            var v = [Double](repeating: 0, count: 6)
            for i in (0..<6).reversed() { v[i] = popNumber(scanner) }
            state.text = CGAffineTransform(a: CGFloat(v[0]), b: CGFloat(v[1]), c: CGFloat(v[2]),
                                           d: CGFloat(v[3]), tx: CGFloat(v[4]), ty: CGFloat(v[5]))
            state.line = state.text
        }
        CGPDFOperatorTableSetCallback(table, "Td") { scanner, info in
            let ty = popNumber(scanner)
            let tx = popNumber(scanner)
            scanState(info).newline(tx, ty)
        }
        CGPDFOperatorTableSetCallback(table, "TD") { scanner, info in
            let state = scanState(info)
            let ty = popNumber(scanner)
            let tx = popNumber(scanner)
            state.leading = -ty
            state.newline(tx, ty)
        }
        CGPDFOperatorTableSetCallback(table, "T*") { _, info in
            let state = scanState(info)
            state.newline(0, -state.leading)
        }
        CGPDFOperatorTableSetCallback(table, "Tj") { scanner, info in
            scanState(info).show(glyphs: popStringLength(scanner))
        }
        CGPDFOperatorTableSetCallback(table, "TJ") { scanner, info in
            scanState(info).show(glyphs: popArrayLength(scanner))
        }
        // the two shorthands that step to the next line and show in one go
        CGPDFOperatorTableSetCallback(table, "'") { scanner, info in
            let state = scanState(info)
            state.newline(0, -state.leading)
            state.show(glyphs: popStringLength(scanner))
        }
        CGPDFOperatorTableSetCallback(table, "\"") { scanner, info in
            let state = scanState(info)
            state.newline(0, -state.leading)
            state.show(glyphs: popStringLength(scanner))
        }
    }

    // MARK: - Font names

    /// Resource name → base font name for the page, so "F1" in the stream can
    /// be read as "Helvetica-Bold". A page with no font resources gives an empty
    /// map, and every line then reads as regular weight.
    private static func fontNames(of page: CGPDFPage) -> [String: String] {
        guard let dictionary = page.dictionary else { return [:] }
        var resources: CGPDFDictionaryRef?
        guard CGPDFDictionaryGetDictionary(dictionary, "Resources", &resources),
              let resources else { return [:] }
        var fonts: CGPDFDictionaryRef?
        guard CGPDFDictionaryGetDictionary(resources, "Font", &fonts), let fonts else { return [:] }

        final class Collector { var names: [String: String] = [:] }
        let collector = Collector()
        CGPDFDictionaryApplyFunction(fonts, { key, value, info in
            let collector = Unmanaged<Collector>.fromOpaque(info!).takeUnretainedValue()
            var font: CGPDFDictionaryRef?
            guard CGPDFObjectGetValue(value, .dictionary, &font), let font else { return }
            var base: UnsafePointer<Int8>?
            guard CGPDFDictionaryGetName(font, "BaseFont", &base), let base else { return }
            collector.names[String(cString: key)] = String(cString: base)
        }, Unmanaged.passUnretained(collector).toOpaque())
        return collector.names
    }
}
