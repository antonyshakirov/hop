import Foundation

/// SPEC: docs/spec.md — "Converter: web pages".
public enum HTMLConversion {
    public enum Target: String, CaseIterable, Sendable, Identifiable {
        case pdf, docx, markdown, rtf, txt, png

        public var id: String { rawValue }

        public var fileExtension: String {
            switch self {
            case .pdf: return "pdf"
            case .docx: return "docx"
            case .markdown: return "md"
            case .rtf: return "rtf"
            case .txt: return "txt"
            case .png: return "png"
            }
        }

        public var label: String { fileExtension }

        /// Whether producing this means laying the page out, rather than reading it.
        public var rendersPage: Bool { self == .pdf || self == .png }
    }

    public static let handledExtensions: Set<String> = [
        "html", "htm", "xhtml", "webarchive", "mhtml", "mht",
    ]

    public static func isPage(_ url: URL) -> Bool {
        handledExtensions.contains(url.pathExtension.lowercased())
    }

    // MARK: - A pasted address

    /// Extensions that make a dotted word a filename rather than a host.
    private static let filenameEndings: Set<String> = [
        "html", "htm", "xhtml", "mhtml", "mht", "webarchive",
        "pdf", "doc", "docx", "rtf", "txt", "md", "markdown", "pages", "numbers", "key",
        "png", "jpg", "jpeg", "heic", "heif", "gif", "tiff", "tif", "webp", "avif", "bmp", "svg",
        "mp4", "mov", "m4v", "mkv", "webm", "avi", "wmv", "flv",
        "mp3", "wav", "flac", "aac", "m4a", "aiff", "ogg",
        "zip", "rar", "7z", "tar", "gz", "dmg", "app", "csv", "xlsx", "pptx", "json", "xml",
    ]

    /// A pasted string read as a page address, or nil when it is just text.
    public static func address(fromPasted text: String) -> URL? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        guard !trimmed.contains(where: { $0.isWhitespace }) else { return nil }
        guard !trimmed.hasPrefix("/"), !trimmed.hasPrefix("~") else { return nil }

        if let scheme = URL(string: trimmed)?.scheme?.lowercased() {
            guard scheme == "http" || scheme == "https" else { return nil }
            guard let url = URL(string: trimmed), url.host?.isEmpty == false else { return nil }
            return url
        }
        guard let host = hostLike(trimmed) else { return nil }
        let hasPath = trimmed.dropFirst(host.count).hasPrefix("/")
        if !hasPath, let ending = host.split(separator: ".").last,
           filenameEndings.contains(ending.lowercased()) {
            return nil
        }
        return URL(string: "https://" + trimmed)
    }

    private static func hostLike(_ text: String) -> String? {
        let host = String(text.prefix(while: { $0 != "/" && $0 != "?" && $0 != "#" }))
        let labels = host.split(separator: ".", omittingEmptySubsequences: false)
        guard labels.count >= 2, labels.allSatisfy({ !$0.isEmpty }) else { return nil }
        guard let last = labels.last, last.count >= 2,
              last.allSatisfy({ $0.isLetter && $0.isASCII }) else { return nil }
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: ".-"))
        guard host.unicodeScalars.allSatisfy(allowed.contains) else { return nil }
        return host
    }

    // MARK: - Batch identity

    /// What tells one batch row from another — unique for a file and an address alike.
    public static func batchKey(_ url: URL) -> String { url.absoluteString }

    /// Whether "next to the original" means anything for this source.
    public static func hasOwnFolder(_ url: URL) -> Bool { url.isFileURL }

    // MARK: - What the result is called

    /// The base name of the converted file: a file's own, or a page's title.
    public static func outputName(for url: URL, title: String?) -> String {
        if url.isFileURL {
            let own = Substitutions.plain(url.deletingPathExtension().lastPathComponent)
            return own.isEmpty ? "page" : own
        }
        if let title, case let cleaned = filenameSafe(title), !cleaned.isEmpty {
            return cleaned
        }
        if case let cleaned = filenameSafe(url.deletingPathExtension().lastPathComponent),
           !cleaned.isEmpty {
            return cleaned
        }
        if case let cleaned = filenameSafe(url.host ?? ""), !cleaned.isEmpty { return cleaned }
        return "page"
    }

    private static func filenameSafe(_ text: String) -> String {
        var out = ""
        for character in text {
            switch character {
            case "/", "\\": out.append("-")
            case ":", "*", "?", "\"", "<", ">", "|": continue
            default:
                if character.isNewline || character == "\t" { out.append(" "); continue }
                out.unicodeScalars.append(contentsOf: character.unicodeScalars.filter {
                    !CharacterSet.controlCharacters.contains($0)
                })
            }
        }
        while out.contains("  ") { out = out.replacingOccurrences(of: "  ", with: " ") }
        out = String(out.prefix(nameLimit))
        return out.trimmingCharacters(in: CharacterSet(charactersIn: " .-"))
    }

    private static let nameLimit = 80

    // MARK: - The snapshot of a whole page

    /// How much a full-page snapshot has to shrink to fit the cap.
    public static func snapshotScale(contentHeight: Double, cap: Double) -> Double {
        guard contentHeight > 0, cap > 0, contentHeight > cap else { return 1 }
        return cap / contentHeight
    }

    public static let snapshotHeightCap: Double = 16_000
}
