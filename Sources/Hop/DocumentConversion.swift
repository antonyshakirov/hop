import AppKit
import HopCore
import PDFKit
import Vision

/// Documents in the converter: markdown, Word files and PDFs turned into one
/// another. Everything here is native — the markdown engine is ours
/// (`HopCore.MarkdownParser`), Word files ride AppKit's own reader/writer, and
/// PDFs go through PDFKit — so the module adds no dependency and no download.
///
/// Honest limits, stated in the UI and the docs rather than hidden: a Word file
/// with columns, footnotes or headers loses that layout (AppKit's reader keeps
/// text, headings, emphasis, lists, simple tables and images), and a PDF holds
/// layout rather than structure, so PDF → markdown is text EXTRACTION with
/// heading guesses, not a faithful conversion.
enum DocumentConversion {
    /// What a document group can be turned into.
    enum Target: String, CaseIterable, Identifiable {
        case pdf, markdown, docx

        var id: String { rawValue }
        var fileExtension: String {
            switch self {
            case .pdf: return "pdf"
            case .markdown: return "md"
            case .docx: return "docx"
            }
        }
        /// Chip label — file extensions, no translation needed.
        var label: String { fileExtension }
    }

    /// Extensions the document group accepts. PDFs are NOT here: they stay in
    /// their own group (compression) and gain a "→ md" mode instead.
    static let readableExtensions: Set<String> = ["md", "markdown", "txt", "rtf", "doc", "docx"]

    // MARK: - Reading

    /// A source document as an attributed string: markdown through our own
    /// parser (so its typography is ours), everything else through AppKit's
    /// readers, which is what TextEdit uses.
    nonisolated static func read(_ url: URL) -> NSAttributedString? {
        let ext = url.pathExtension.lowercased()
        if ext == "md" || ext == "markdown" || ext == "txt" {
            guard let text = try? String(contentsOf: url, encoding: .utf8) else { return nil }
            if ext == "txt" {
                return NSAttributedString(string: text, attributes: [
                    .font: bodyFont(bodySize),
                    .paragraphStyle: paragraphStyle(spacing: 8),
                ])
            }
            return attributed(markdown: text)
        }
        let type: NSAttributedString.DocumentType
        switch ext {
        case "docx": type = .officeOpenXML
        case "doc": type = .docFormat
        case "rtf": type = .rtf
        default: return nil
        }
        return try? NSAttributedString(
            url: url, options: [.documentType: type], documentAttributes: nil)
    }

    // MARK: - Markdown → attributed

    private static let bodySize: CGFloat = 11.5

    /// The face documents are written in.
    ///
    /// NOT the system font. Printing an NSTextView set in San Francisco asks
    /// CoreText for `.SFNS-Regular…` by NAME, gets Times New Roman substituted
    /// ("it will get TimesNewRomanPSMT rather than the intended font") and
    /// embeds a mapping under which Cyrillic comes back wrong: a heading written
    /// in Cyrillic extracted with its "ka" turned into U+0138 (KRA), and copying
    /// that line out of the pdf in any reader gave the same (found 2026-07-29
    /// while adding pdf to docx). Helvetica Neue is a real, embeddable family
    /// with a proper Cyrillic cut, so the text in the file IS the text that went
    /// in. Latin was fine throughout, which is why this survived so long.
    nonisolated static func bodyFont(_ size: CGFloat, bold: Bool = false) -> NSFont {
        let name = bold ? "HelveticaNeue-Bold" : "HelveticaNeue"
        return NSFont(name: name, size: size)
            ?? (bold ? .boldSystemFont(ofSize: size) : .systemFont(ofSize: size))
    }

    /// Fixed-pitch for code blocks, chosen the same way and for the same reason.
    nonisolated static func codeFont(_ size: CGFloat) -> NSFont {
        NSFont(name: "Menlo", size: size) ?? .monospacedSystemFont(ofSize: size, weight: .regular)
    }

    /// Markdown rendered with Hop's own typography: the whole point of owning
    /// the parser is that the PDF comes out looking deliberate rather than like
    /// a browser's default stylesheet.
    nonisolated static func attributed(markdown: String) -> NSAttributedString {
        let out = NSMutableAttributedString()
        for block in MarkdownParser.blocks(markdown) {
            switch block {
            case .heading(let level, let text):
                let size: CGFloat = level == 1 ? 22 : (level == 2 ? 17 : 14)
                out.append(styled(text, font: bodyFont(size, bold: true),
                                  style: paragraphStyle(spacing: 6, before: level == 1 ? 4 : 12)))
            case .paragraph(let text):
                out.append(styled(text, font: bodyFont(bodySize),
                                  style: paragraphStyle(spacing: 8)))
            case .bullet(let text):
                out.append(styled("•  " + text, font: bodyFont(bodySize),
                                  style: paragraphStyle(spacing: 4, indent: 14)))
            case .numbered(let number, let text):
                out.append(styled("\(number).  " + text, font: bodyFont(bodySize),
                                  style: paragraphStyle(spacing: 4, indent: 14)))
            case .quote(let text):
                let attributed = styled(text, font: bodyFont(bodySize),
                                        style: paragraphStyle(spacing: 8, indent: 18))
                attributed.addAttribute(.foregroundColor, value: NSColor.darkGray,
                                        range: NSRange(location: 0, length: attributed.length))
                out.append(attributed)
            case .code(let lines, _):
                let style = paragraphStyle(spacing: 8, indent: 12)
                let text = NSMutableAttributedString(
                    string: lines.joined(separator: "\n") + "\n",
                    attributes: [
                        .font: codeFont(bodySize - 1),
                        .paragraphStyle: style,
                        .foregroundColor: NSColor.black,
                        .backgroundColor: NSColor(white: 0.95, alpha: 1),
                    ])
                out.append(text)
            case .rule:
                // AppKit paragraphs have no border, so the rule is drawn as a
                // light run of dashes — plain, and it survives every exporter
                out.append(NSAttributedString(string: String(repeating: "—", count: 32) + "\n",
                                              attributes: [
                                                  .font: bodyFont(bodySize),
                                                  .foregroundColor: NSColor.lightGray,
                                                  .paragraphStyle: paragraphStyle(spacing: 10),
                                              ]))
            }
        }
        return out
    }

    /// One block of text with its inline markers applied.
    private nonisolated static func styled(
        _ text: String, font: NSFont, style: NSParagraphStyle
    ) -> NSMutableAttributedString {
        let out = NSMutableAttributedString()
        for span in MarkdownInline.spans(text) {
            var attributes: [NSAttributedString.Key: Any] = [
                .paragraphStyle: style,
                .foregroundColor: NSColor.black,
            ]
            if span.code {
                attributes[.font] = codeFont(font.pointSize - 1)
                attributes[.backgroundColor] = NSColor(white: 0.95, alpha: 1)
            } else {
                attributes[.font] = traited(font, bold: span.bold, italic: span.italic)
            }
            if let link = span.link, let url = URL(string: link) {
                attributes[.link] = url
                attributes[.foregroundColor] = NSColor.systemBlue
                attributes[.underlineStyle] = NSUnderlineStyle.single.rawValue
            }
            out.append(NSAttributedString(string: span.text, attributes: attributes))
        }
        out.append(NSAttributedString(string: "\n", attributes: [
            .font: font, .paragraphStyle: style,
        ]))
        return out
    }

    private nonisolated static func traited(_ font: NSFont, bold: Bool, italic: Bool) -> NSFont {
        var traits: NSFontTraitMask = []
        if bold { traits.insert(.boldFontMask) }
        if italic { traits.insert(.italicFontMask) }
        guard !traits.isEmpty else { return font }
        return NSFontManager.shared.convert(font, toHaveTrait: traits)
    }

    private nonisolated static func paragraphStyle(
        spacing: CGFloat, before: CGFloat = 0, indent: CGFloat = 0
    ) -> NSParagraphStyle {
        let style = NSMutableParagraphStyle()
        style.paragraphSpacing = spacing
        style.paragraphSpacingBefore = before
        style.headIndent = indent
        style.firstLineHeadIndent = indent > 0 ? indent - 14 : 0
        style.lineHeightMultiple = 1.15
        return style
    }

    // MARK: - Attributed → PDF

    /// A4 with 2cm margins — the shape a document is expected to have.
    private static let pageSize = NSSize(width: 595, height: 842)
    private static let pageMargin: CGFloat = 56

    /// Paginated PDF via AppKit's own print machinery: an off-screen text view
    /// laid out to the printable width, printed to a file. This is what gives
    /// real page breaks (and keeps images that came out of a Word file); a
    /// single-page image render would not.
    @MainActor
    static func writePDF(_ attributed: NSAttributedString, to url: URL) -> Bool {
        let info = NSPrintInfo()
        info.paperSize = pageSize
        info.topMargin = pageMargin
        info.bottomMargin = pageMargin
        info.leftMargin = pageMargin
        info.rightMargin = pageMargin
        info.horizontalPagination = .fit
        info.verticalPagination = .automatic
        // AppKit centres the content of a PARTIAL page by default, so the last
        // page of a document floated in the middle of the sheet with a huge gap
        // above it. Text pages start at the top margin, like anything printed.
        info.isVerticallyCentered = false
        info.isHorizontallyCentered = false
        info.jobDisposition = .save
        info.dictionary()[NSPrintInfo.AttributeKey.jobSavingURL] = url

        let width = pageSize.width - pageMargin * 2
        let height = pageSize.height - pageMargin * 2
        let view = NSTextView(frame: NSRect(x: 0, y: 0, width: width, height: height))
        view.textContainer?.containerSize = NSSize(width: width, height: .greatestFiniteMagnitude)
        view.textContainer?.widthTracksTextView = true
        view.isVerticallyResizable = true
        view.isHorizontallyResizable = false
        view.textStorage?.setAttributedString(attributed)
        if let container = view.textContainer {
            view.layoutManager?.ensureLayout(for: container)
        }
        view.sizeToFit()

        let operation = NSPrintOperation(view: view, printInfo: info)
        operation.showsPrintPanel = false
        operation.showsProgressPanel = false
        guard operation.run() else { return false }
        return FileManager.default.fileExists(atPath: url.path)
    }

    // MARK: - Attributed → docx

    nonisolated static func writeDocx(_ attributed: NSAttributedString, to url: URL) -> Bool {
        let range = NSRange(location: 0, length: attributed.length)
        guard let data = try? attributed.data(
            from: range,
            documentAttributes: [.documentType: NSAttributedString.DocumentType.officeOpenXML])
        else { return false }
        return (try? data.write(to: url)) != nil
    }

    // MARK: - Attributed → markdown

    /// Word (or rtf) content described as markdown blocks. Structure is
    /// RECOVERED, not read: styles are inconsistent in real documents, so the
    /// decision comes from measurable things — type size against the document's
    /// own body size, weight, and list markers (`HopCore.DocumentHeuristics`).
    nonisolated static func markdown(from attributed: NSAttributedString) -> String {
        let paragraphs = self.paragraphs(of: attributed)
        let body = DocumentHeuristics.bodySize(paragraphs.map { Double($0.size) }) ?? Double(bodySize)
        var blocks: [MarkdownBlock] = []
        var codeLines: [String] = []

        func flushCode() {
            guard !codeLines.isEmpty else { return }
            blocks.append(.code(lines: codeLines, language: nil))
            codeLines = []
        }

        for paragraph in paragraphs {
            let text = paragraph.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { continue }
            // consecutive fixed-pitch paragraphs are ONE code block, the way
            // they were written before the trip through Word
            if paragraph.monospaced {
                codeLines.append(text)
                continue
            }
            flushCode()
            if DocumentHeuristics.isRuleLine(text) {
                blocks.append(.rule)
                continue
            }
            if let item = DocumentHeuristics.listItem(text) {
                blocks.append(item.ordered
                    ? .numbered(item.number ?? 1, item.text)
                    : .bullet(item.text))
                continue
            }
            if let level = DocumentHeuristics.headingLevel(
                size: Double(paragraph.size), body: body, bold: paragraph.bold) {
                blocks.append(.heading(level: level, text: text))
                continue
            }
            blocks.append(.paragraph(paragraph.inline))
        }
        flushCode()
        return MarkdownWriter.text(from: blocks)
    }

    private struct Paragraph {
        let text: String
        /// Same text with inline markers restored from the runs' font traits.
        let inline: String
        let size: CGFloat
        let bold: Bool
        /// A whole paragraph set in a fixed-pitch face — a code block in the
        /// original, and worth keeping as one.
        let monospaced: Bool
    }

    /// Split into paragraphs, each with the size and weight of its first run —
    /// that is what a reader perceives as "this line is a heading".
    private nonisolated static func paragraphs(of attributed: NSAttributedString) -> [Paragraph] {
        let string = attributed.string as NSString
        var out: [Paragraph] = []
        string.enumerateSubstrings(
            in: NSRange(location: 0, length: string.length), options: [.byParagraphs]
        ) { substring, range, _, _ in
            guard let substring, !substring.isEmpty else { return }
            let font = attributed.attribute(.font, at: range.location, effectiveRange: nil) as? NSFont
            let size = font?.pointSize ?? bodySize
            let bold = font.map {
                NSFontManager.shared.traits(of: $0).contains(.boldFontMask)
            } ?? false
            out.append(Paragraph(text: substring,
                                 inline: inlineMarkdown(attributed, range: range),
                                 size: size, bold: bold,
                                 monospaced: isAllFixedPitch(attributed, range: range)))
        }
        return out
    }

    /// Whether the WHOLE paragraph is fixed-pitch, which is what makes it a code
    /// block. Reading the first run alone turned any paragraph that merely began
    /// with an inline `snippet` into a fenced block on the way back out of Word
    /// (found 2026-07-29).
    private nonisolated static func isAllFixedPitch(
        _ attributed: NSAttributedString, range: NSRange
    ) -> Bool {
        var sawFont = false
        var allFixed = true
        attributed.enumerateAttribute(.font, in: range, options: []) { value, runRange, stop in
            // whitespace-only runs carry no evidence either way
            let text = (attributed.string as NSString).substring(with: runRange)
            guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
            guard let font = value as? NSFont else { allFixed = false; stop.pointee = true; return }
            sawFont = true
            if !font.isFixedPitch { allFixed = false; stop.pointee = true }
        }
        return sawFont && allFixed
    }

    /// Bold and italic runs inside a paragraph written back as markdown markers,
    /// so emphasis survives the trip out of Word.
    private nonisolated static func inlineMarkdown(
        _ attributed: NSAttributedString, range: NSRange
    ) -> String {
        var out = ""
        attributed.enumerateAttributes(in: range, options: []) { attributes, runRange, _ in
            let text = (attributed.string as NSString).substring(with: runRange)
            guard !text.isEmpty else { return }
            // a link is written back as a markdown link, so it survives the trip
            if let url = attributes[.link] as? URL ?? (attributes[.link] as? String)
                .flatMap(URL.init(string:)) {
                let label = text.trimmingCharacters(in: .whitespaces)
                if !label.isEmpty {
                    out += "[\(label)](\(url.absoluteString))"
                    return
                }
            }
            guard let font = attributes[.font] as? NSFont else { out += text; return }
            let traits = NSFontManager.shared.traits(of: font)
            let bold = traits.contains(.boldFontMask)
            let italic = traits.contains(.italicFontMask)
            // markers wrap the run's own text; surrounding spaces stay outside,
            // otherwise "**bold **next" would not render as emphasis anywhere
            let trimmed = text.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty, bold || italic || font.isFixedPitch else {
                out += text
                return
            }
            let leading = String(text.prefix(while: { $0 == " " }))
            let trailing = String(text.reversed().prefix(while: { $0 == " " }))
            let marker = font.isFixedPitch ? "`" : (bold ? "**" : "*")
            out += leading + marker + trimmed + marker + trailing
        }
        return out
    }

    // MARK: - PDF → markdown

    /// Text out of a PDF, with headings guessed from type size. A page with no
    /// text layer at all (a scan) is read with Vision instead — the same
    /// recognition the screen-text module uses.
    nonisolated static func markdown(fromPDF url: URL) -> String? {
        guard let document = PDFDocument(url: url) else { return nil }
        var lines: [(text: String, size: Double, bold: Bool)] = []
        for index in 0..<document.pageCount {
            guard let page = document.page(at: index) else { continue }
            let text = page.string ?? ""
            if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                lines.append(contentsOf: scannedPageLines(page))
            } else if let attributed = page.attributedString {
                lines.append(contentsOf: self.lines(of: attributed))
            }
        }
        guard !lines.isEmpty else { return nil }
        let body = DocumentHeuristics.bodySize(lines.map(\.size)) ?? 12
        var blocks: [MarkdownBlock] = []
        for line in lines {
            let text = line.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { continue }
            if DocumentHeuristics.isRuleLine(text) {
                blocks.append(.rule)
            } else if let item = DocumentHeuristics.listItem(text) {
                blocks.append(item.ordered ? .numbered(item.number ?? 1, item.text) : .bullet(item.text))
            } else if let level = DocumentHeuristics.headingLevel(
                size: line.size, body: body, bold: line.bold) {
                blocks.append(.heading(level: level, text: text))
            } else if case .paragraph(let previous)? = blocks.last,
                      DocumentHeuristics.continuesParagraph(previous: previous, next: text) {
                // a pdf stores one run per VISUAL line; without this every
                // wrapped sentence would come out as its own paragraph
                blocks[blocks.count - 1] = .paragraph(previous + " " + text)
            } else {
                blocks.append(.paragraph(text))
            }
        }
        return MarkdownWriter.text(from: blocks)
    }

    private nonisolated static func lines(
        of attributed: NSAttributedString
    ) -> [(text: String, size: Double, bold: Bool)] {
        let string = attributed.string as NSString
        var out: [(String, Double, Bool)] = []
        string.enumerateSubstrings(
            in: NSRange(location: 0, length: string.length), options: [.byParagraphs]
        ) { substring, range, _, _ in
            guard let substring else { return }
            let font = attributed.attribute(.font, at: range.location, effectiveRange: nil) as? NSFont
            let bold = font.map { NSFontManager.shared.traits(of: $0).contains(.boldFontMask) } ?? false
            out.append((substring, Double(font?.pointSize ?? 12), bold))
        }
        return out
    }

    /// A scanned page: render it and let Vision read it. Line HEIGHT stands in
    /// for type size, so the heading heuristics still work on a scan.
    private nonisolated static func scannedPageLines(
        _ page: PDFPage
    ) -> [(text: String, size: Double, bold: Bool)] {
        let bounds = page.bounds(for: .mediaBox)
        guard bounds.width > 1, bounds.height > 1 else { return [] }
        let scale: CGFloat = 2
        let width = Int(bounds.width * scale)
        let height = Int(bounds.height * scale)
        guard let context = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return [] }
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.scaleBy(x: scale, y: scale)
        page.draw(with: .mediaBox, to: context)
        guard let image = context.makeImage() else { return [] }

        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        guard (try? handler.perform([request])) != nil else { return [] }
        let observations = request.results ?? []
        return ScreenTextRules.readingOrder(observations.map(\.boundingBox)).compactMap { index in
            let observation = observations[index]
            guard let text = observation.topCandidates(1).first?.string else { return nil }
            // the box height is a fraction of the page; scale it into something
            // comparable to a point size so the heading ratios still apply
            return (text, Double(observation.boundingBox.height) * Double(bounds.height), false)
        }
    }
}
