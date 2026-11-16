import Foundation

// SPEC: docs/spec.md — Clipboard, entry hover preview.
public enum ClipboardHoverPreview {
    public static let characterLimit = 1500
    public static let lineLimit = 20

    /// A bounded multiline preview; no pasteboard or external body file is read.
    public static func text(for item: ClipboardItem) -> String {
        let source = item.filePaths.map { $0.prefix(8).joined(separator: "\n") } ?? item.text
        var preview = "", lines = 1, characters = 0
        var truncated = (item.filePaths?.count ?? 0) > 8 || item.textFile != nil
        for character in source {
            guard characters < characterLimit, !(character.isNewline && lines == lineLimit) else {
                truncated = true
                break
            }
            preview.append(character)
            characters += 1
            if character.isNewline { lines += 1 }
        }
        return preview + (truncated ? "…" : "")
    }
}
