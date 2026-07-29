import Foundation

/// Turning a clipboard entry into a file on disk: what to call it, and what to
/// do when that name is taken. Pure — the controller does the writing.
public enum ClipboardDocument {
    /// What the entry is written as. Plain text and markdown are the text
    /// itself; pdf and docx are rendered from it, so a copied markdown snippet
    /// comes out formatted rather than as its own source.
    public enum Format: String, CaseIterable, Identifiable, Sendable {
        case txt, md, pdf, docx

        public var id: String { rawValue }
        public var fileExtension: String { rawValue }
        /// Chip label — a file extension needs no translation.
        public var label: String { rawValue }
        /// Whether the text is written as-is or rendered first.
        public var isPlainText: Bool { self == .txt || self == .md }

        public static func named(_ raw: String) -> Format { Format(rawValue: raw) ?? .txt }
    }

    public static let fileExtension = "txt"
    /// How much of the text becomes the name. Long enough to recognise the entry
    /// in a folder, short enough to stay one line in Finder.
    public static let nameLimit = 40

    /// The file name for a copied text: its first words, with everything a file
    /// name cannot hold taken out. An entry that is only punctuation, or only
    /// emoji that survive nothing, falls back to `fallback` rather than
    /// producing a nameless file.
    public static func fileName(for text: String, fallback: String = "clipboard") -> String {
        // The first LINE, not the first characters: a copied paragraph names the
        // file after its opening sentence rather than trailing into the second.
        let firstLine = text.split(whereSeparator: \.isNewline).first.map(String.init) ?? ""
        let forbidden = CharacterSet(charactersIn: "/\\:*?\"<>|")
            .union(.controlCharacters)
        let cleaned = String(String.UnicodeScalarView(
            firstLine.unicodeScalars.filter { !forbidden.contains($0) }))
        let collapsed = cleaned.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        // A leading dot would make it invisible in Finder — not what anyone means
        // by "name it after the text".
        let trimmed = String(collapsed.prefix(nameLimit))
            .trimmingCharacters(in: .whitespaces)
            .drop(while: { $0 == "." })
        return trimmed.isEmpty ? fallback : String(trimmed)
    }

    /// `name`, or `name 2`, `name 3`… — the first one `taken` does not contain.
    /// Saving the same entry twice must not overwrite the first file, and must
    /// not fail either: Finder's own duplicate rule is what people expect.
    public static func uniqueName(_ name: String, ext: String = fileExtension,
                                  taken: (String) -> Bool) -> String {
        let full = { (candidate: String) in "\(candidate).\(ext)" }
        guard taken(full(name)) else { return full(name) }
        for suffix in 2...999 where !taken(full("\(name) \(suffix)")) {
            return full("\(name) \(suffix)")
        }
        return full("\(name) \(Int.random(in: 1000...9999))")
    }
}
