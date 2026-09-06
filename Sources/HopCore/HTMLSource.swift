import Foundation

/// SPEC: docs/spec.md — "Converter: web pages", what fetches is stripped
/// before AppKit reads it.
public enum HTMLSource {
    private static let dropWithContent: Set<String> = [
        "script", "style", "iframe", "object", "video", "audio", "svg", "noscript",
    ]

    private static let dropAlone: Set<String> = [
        "img", "link", "source", "embed", "track", "input",
    ]

    /// The page with those elements removed and everything else untouched.
    public static func readable(_ html: String) -> String {
        var out = ""
        out.reserveCapacity(html.count)
        var index = html.startIndex

        while index < html.endIndex {
            guard html[index] == "<" else {
                out.append(html[index])
                index = html.index(after: index)
                continue
            }
            let tag: Tag
            switch scanTag(html, from: index) {
            case .notATag:
                out.append("<")
                index = html.index(after: index)
                continue
            case .unterminated:
                index = html.endIndex
                continue
            case .tag(let scanned):
                tag = scanned
            }
            let name = tag.name.lowercased()
            if tag.closing == false, dropWithContent.contains(name) {
                index = endOfElement(html, named: name, after: tag.end) ?? html.endIndex
                continue
            }
            if dropAlone.contains(name) {
                index = tag.end
                continue
            }
            out.append(contentsOf: html[index..<tag.end])
            index = tag.end
        }
        return out
    }

    private struct Tag {
        let name: String
        let closing: Bool
        /// One past the tag's ">".
        let end: String.Index
    }

    private enum TagScan {
        case notATag
        case unterminated
        case tag(Tag)
    }

    private static func scanTag(_ html: String, from start: String.Index) -> TagScan {
        var index = html.index(after: start)
        guard index < html.endIndex else { return .notATag }
        var closing = false
        if html[index] == "/" {
            closing = true
            index = html.index(after: index)
        }
        guard index < html.endIndex, html[index].isLetter else { return .notATag }
        var name = ""
        while index < html.endIndex, html[index].isLetter || html[index].isNumber {
            name.append(html[index])
            index = html.index(after: index)
        }
        // a ">" inside a quoted attribute value does not end the tag
        var quote: Character?
        while index < html.endIndex {
            let character = html[index]
            if let open = quote {
                if character == open { quote = nil }
            } else if character == "\"" || character == "'" {
                quote = character
            } else if character == ">" {
                return .tag(Tag(name: name, closing: closing, end: html.index(after: index)))
            }
            index = html.index(after: index)
        }
        return .unterminated
    }

    /// One past the `</name>` that closes this element, or nil when none does.
    private static func endOfElement(
        _ html: String, named name: String, after start: String.Index
    ) -> String.Index? {
        var index = start
        while index < html.endIndex {
            guard html[index] == "<" else {
                index = html.index(after: index)
                continue
            }
            switch scanTag(html, from: index) {
            case .tag(let tag):
                if tag.closing, tag.name.lowercased() == name { return tag.end }
                index = tag.end
            case .notATag:
                index = html.index(after: index)
            case .unterminated:
                return nil
            }
        }
        return nil
    }
}
