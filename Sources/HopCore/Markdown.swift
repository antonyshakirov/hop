import Foundation

/// One block of a document, the shape both directions of the document
/// converter agree on: markdown is parsed INTO these, and .docx/.pdf content is
/// described BY these before being written back out as markdown.
public enum MarkdownBlock: Equatable {
    case heading(level: Int, text: String)
    case paragraph(String)
    case bullet(String)
    case numbered(Int, String)
    /// Fenced code — the lines verbatim, plus the language written after the fence.
    case code(lines: [String], language: String?)
    case quote(String)
    case rule
}

/// A run of inline text with the styling markdown gives it. Rendering to a
/// PDF needs the styling; writing markdown back out needs the markers. Both
/// sides work from this, so the two directions cannot drift apart.
public struct InlineSpan: Equatable {
    public var text: String
    public var bold: Bool
    public var italic: Bool
    public var code: Bool
    /// Destination of a [text](url) link, if this run is one.
    public var link: String?

    public init(text: String, bold: Bool = false, italic: Bool = false,
                code: Bool = false, link: String? = nil) {
        self.text = text
        self.bold = bold
        self.italic = italic
        self.code = code
        self.link = link
    }
}

/// A deliberately small CommonMark subset — the part real documents use:
/// headings, paragraphs, lists, quotes, fenced code, rules, and inline
/// bold/italic/code/links. Hop ships no external packages, and a parser we own
/// is one we can test exactly and keep rendering deterministic.
public enum MarkdownParser {
    public static func blocks(_ markdown: String) -> [MarkdownBlock] {
        var out: [MarkdownBlock] = []
        var paragraph: [String] = []
        var lines = markdown.replacingOccurrences(of: "\r\n", with: "\n")
            .components(separatedBy: "\n")[...]

        func flushParagraph() {
            guard !paragraph.isEmpty else { return }
            // wrapped lines are one paragraph — that is what markdown means
            out.append(.paragraph(paragraph.joined(separator: " ")))
            paragraph = []
        }

        while let line = lines.first {
            lines = lines.dropFirst()
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed.isEmpty {
                flushParagraph()
                continue
            }
            if let fence = fenceLanguage(trimmed) {
                flushParagraph()
                var body: [String] = []
                while let next = lines.first {
                    lines = lines.dropFirst()
                    if next.trimmingCharacters(in: .whitespaces).hasPrefix("```") { break }
                    body.append(next)
                }
                out.append(.code(lines: body, language: fence.isEmpty ? nil : fence))
                continue
            }
            if isRule(trimmed) {
                flushParagraph()
                out.append(.rule)
                continue
            }
            if let heading = heading(trimmed) {
                flushParagraph()
                out.append(heading)
                continue
            }
            if trimmed.hasPrefix(">") {
                flushParagraph()
                let text = String(trimmed.dropFirst()).trimmingCharacters(in: .whitespaces)
                out.append(.quote(text))
                continue
            }
            if let bullet = bulletContent(trimmed) {
                flushParagraph()
                out.append(.bullet(bullet))
                continue
            }
            if let ordered = numberedContent(trimmed) {
                flushParagraph()
                out.append(.numbered(ordered.number, ordered.text))
                continue
            }
            paragraph.append(trimmed)
        }
        flushParagraph()
        return out
    }

    /// "```swift" → "swift", "```" → "", not a fence → nil.
    private static func fenceLanguage(_ line: String) -> String? {
        guard line.hasPrefix("```") else { return nil }
        return String(line.dropFirst(3)).trimmingCharacters(in: .whitespaces)
    }

    /// Three or more of the same rule character, spaces allowed between them.
    private static func isRule(_ line: String) -> Bool {
        let stripped = line.replacingOccurrences(of: " ", with: "")
        guard stripped.count >= 3 else { return false }
        return ["-", "*", "_"].contains { char in
            stripped.allSatisfy { String($0) == char }
        }
    }

    private static func heading(_ line: String) -> MarkdownBlock? {
        guard line.hasPrefix("#") else { return nil }
        let hashes = line.prefix { $0 == "#" }.count
        guard hashes <= 6 else { return nil }
        let rest = String(line.dropFirst(hashes))
        // "#hashtag" is not a heading: ATX needs a space after the hashes
        guard rest.hasPrefix(" ") || rest.isEmpty else { return nil }
        let text = rest.trimmingCharacters(in: .whitespaces)
            // closing hashes ("## title ##") are decoration, not content
            .replacingOccurrences(of: "\\s*#+$", with: "", options: .regularExpression)
        return .heading(level: hashes, text: text)
    }

    private static func bulletContent(_ line: String) -> String? {
        for marker in ["- ", "* ", "+ ", "• "] where line.hasPrefix(marker) {
            return String(line.dropFirst(marker.count)).trimmingCharacters(in: .whitespaces)
        }
        return nil
    }

    private static func numberedContent(_ line: String) -> (number: Int, text: String)? {
        let digits = line.prefix { $0.isNumber }
        guard !digits.isEmpty, let number = Int(digits) else { return nil }
        let rest = line.dropFirst(digits.count)
        guard rest.hasPrefix(". ") || rest.hasPrefix(") ") else { return nil }
        return (number, String(rest.dropFirst(2)).trimmingCharacters(in: .whitespaces))
    }
}

/// Inline markers → styled runs. Nesting beyond one level is deliberately not
/// supported: it is rare in real documents and would double the state machine.
public enum MarkdownInline {
    public static func spans(_ text: String) -> [InlineSpan] {
        var out: [InlineSpan] = []
        var plain = ""
        var index = text.startIndex

        func flush() {
            guard !plain.isEmpty else { return }
            out.append(InlineSpan(text: plain))
            plain = ""
        }

        while index < text.endIndex {
            let rest = text[index...]
            if rest.hasPrefix("\\"), text.index(after: index) < text.endIndex {
                // a backslash escapes the next character, marker or not
                let next = text.index(after: index)
                plain.append(text[next])
                index = text.index(after: next)
                continue
            }
            if let found = link(in: rest) {
                flush()
                out.append(found.span)
                index = text.index(index, offsetBy: found.length)
                continue
            }
            var matched = false
            for marker in ["**", "__", "`", "*", "_"] where rest.hasPrefix(marker) {
                if let found = delimited(rest, marker: marker) {
                    flush()
                    out.append(found.span)
                    index = text.index(index, offsetBy: found.length)
                    matched = true
                }
                // the first marker matching this position decides; an unmatched
                // one falls through and is kept as literal text
                break
            }
            if matched { continue }
            plain.append(text[index])
            index = text.index(after: index)
        }
        flush()
        return out
    }

    /// A span between two identical markers, or nil when the closer is missing.
    private static func delimited(
        _ text: Substring, marker: String
    ) -> (span: InlineSpan, length: Int)? {
        let body = text.dropFirst(marker.count)
        guard let closing = body.range(of: marker) else { return nil }
        let inner = String(body[body.startIndex..<closing.lowerBound])
        guard !inner.isEmpty else { return nil }
        let length = marker.count * 2 + inner.count
        switch marker {
        case "`": return (InlineSpan(text: inner, code: true), length)
        case "**", "__": return (InlineSpan(text: inner, bold: true), length)
        default: return (InlineSpan(text: inner, italic: true), length)
        }
    }

    /// [label](destination) — the only link form worth supporting here.
    private static func link(in text: Substring) -> (span: InlineSpan, length: Int)? {
        guard text.hasPrefix("["), let labelEnd = text.firstIndex(of: "]") else { return nil }
        let afterLabel = text.index(after: labelEnd)
        guard afterLabel < text.endIndex, text[afterLabel] == "(",
              let urlEnd = text[afterLabel...].firstIndex(of: ")") else { return nil }
        let label = String(text[text.index(after: text.startIndex)..<labelEnd])
        let url = String(text[text.index(after: afterLabel)..<urlEnd])
        guard !label.isEmpty else { return nil }
        let length = text.distance(from: text.startIndex, to: urlEnd) + 1
        return (InlineSpan(text: label, link: url), length)
    }
}

/// Blocks → markdown text. The inverse direction of the converter: a .docx or
/// .pdf is described as blocks and written out here.
public enum MarkdownWriter {
    public static func text(from blocks: [MarkdownBlock]) -> String {
        var out: [String] = []
        for block in blocks {
            switch block {
            case .heading(let level, let text):
                out.append(String(repeating: "#", count: min(max(level, 1), 6)) + " " + text)
            case .paragraph(let text):
                out.append(escapeLeadingMarker(text))
            case .bullet(let text):
                out.append("- " + text)
            case .numbered(let number, let text):
                out.append("\(number). " + text)
            case .code(let lines, let language):
                out.append("```" + (language ?? ""))
                out.append(contentsOf: lines)
                out.append("```")
            case .quote(let text):
                out.append("> " + text)
            case .rule:
                out.append("---")
            }
            out.append("")   // blank line between blocks
        }
        // exactly one trailing newline, like every well-behaved text file
        return out.joined(separator: "\n").trimmingCharacters(in: .newlines) + "\n"
    }

    /// A paragraph that happens to start with "#", "- " or "> " would read as a
    /// heading, a list or a quote when the file is opened again — escape it.
    private static func escapeLeadingMarker(_ text: String) -> String {
        for marker in ["#", "- ", "* ", "+ ", "> ", "```"] where text.hasPrefix(marker) {
            return "\\" + text
        }
        return text
    }
}
