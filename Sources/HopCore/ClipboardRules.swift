import Foundation

/// A clipboard-history entry. Lives in HopCore so the history rules are
/// unit-testable; the app side owns the pasteboard, image files and storage.
public struct ClipboardItem: Identifiable, Equatable, Codable {
    public let id: UUID
    public var text: String
    /// PNG file name in the images dir — set for image entries (screenshots
    /// copied straight to the clipboard); `text` then holds "1280 × 800".
    public var imageFile: String?
    /// Absolute file paths for a FILE entry (a copy from Finder). `text` holds
    /// the display label — the file NAME, or "name +N" for several files copied
    /// at once. Non-nil is what makes this a file entry; activating it puts the
    /// file URL(s) back on the pasteboard.
    public var filePaths: [String]?

    public init(id: UUID = UUID(), text: String, imageFile: String? = nil, filePaths: [String]? = nil) {
        self.id = id
        self.text = text
        self.imageFile = imageFile
        self.filePaths = filePaths
    }

    /// A plain-text entry — neither an image nor a file. Only these take part in
    /// text dedup, so a file label like "notes.txt" is never swallowed by later
    /// copying the literal text "notes.txt".
    public var isPlainText: Bool { imageFile == nil && filePaths == nil }
}

/// What a fresh pasteboard change should be captured as. Pure and in HopCore so
/// the capture ORDER is unit-tested without touching NSPasteboard: a copied
/// FILE beats the icon/thumbnail preview Finder ships beside it, and image data
/// beats a bare string.
public enum ClipboardCapture: Equatable {
    case files([String])   // absolute paths, in pasteboard order
    case image             // the controller owns the bytes and the label
    case text(String)
    case ignore
}

/// Pure history rules: what a fresh copy does to the list and how the
/// caps trim it. No pasteboard, no files — those stay in the controller.
public enum ClipboardRules {
    /// Protection against "accidentally copied a book": every entry is
    /// truncated, so even a full history weighs next to nothing.
    public static let maxItemLength = 20_000

    /// Decide what a fresh pasteboard change should become. A copied FILE always
    /// wins over image data — Finder puts the file's icon/thumbnail on the
    /// pasteboard next to the file URL, and that preview must never mask the
    /// real file (the bug this fixes: a copied 1024×1024 icon landing as a
    /// "1024 × 1024" image row). Image data beats bare text — a screenshot copy
    /// carries no useful string.
    public static func classify(fileURLPaths: [String], hasImage: Bool, text: String?) -> ClipboardCapture {
        let paths = fileURLPaths.filter { !$0.isEmpty }
        if !paths.isEmpty { return .files(paths) }
        if hasImage { return .image }
        if let text, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return .text(text)
        }
        return .ignore
    }

    /// Display label for a file entry: the single file's name, or "name +N" when
    /// several files were copied at once (N counts the others).
    public static func fileLabel(for paths: [String]) -> String {
        let names = paths.map { ($0 as NSString).lastPathComponent }
        guard let first = names.first else { return "" }
        return names.count > 1 ? "\(first) +\(names.count - 1)" : first
    }

    /// A fresh text copy folded into the history. Returns nil when the
    /// list should not change (empty text, exact repeat of the top entry).
    public static func remembering(_ raw: String, in items: [ClipboardItem]) -> [ClipboardItem]? {
        // normalization: trailing spaces/newlines used to create "duplicates"
        let text = String(raw.prefix(maxItemLength))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        // case-insensitive comparison: dictation changes capitalization
        // retroactively. Image and file entries never take part in text dedup —
        // their label ("1280 × 800", a file name) may collide with copied text
        let key = text.lowercased()
        if let first = items.first, first.isPlainText {
            if first.text.lowercased() == key {
                guard first.text != text else { return nil }
                var out = items
                out[0].text = text // update capitalization in place
                return out
            }
            // dictation writes growing text: substitute the new version
            let firstKey = first.text.lowercased()
            if key.hasPrefix(firstKey) || firstKey.hasPrefix(key) {
                var out = items
                out[0].text = text
                return out
            }
        }
        var out = items.filter { !($0.isPlainText && $0.text.lowercased() == key) }
        out.insert(ClipboardItem(text: text), at: 0)
        return out
    }

    /// A fresh file copy folded into the history. Returns nil when nothing should
    /// change (no paths, or an exact repeat of the top file entry). An identical
    /// file set deeper in the list moves to the top as a fresh entry.
    public static func remembering(files paths: [String], in items: [ClipboardItem]) -> [ClipboardItem]? {
        guard !paths.isEmpty else { return nil }
        if let first = items.first, first.filePaths == paths { return nil }
        var out = items.filter { $0.filePaths != paths }
        out.insert(ClipboardItem(text: fileLabel(for: paths), filePaths: paths), at: 0)
        return out
    }

    /// Enforce both caps at once; the caller deletes the files of the
    /// removed entries. Images have their own cap — they are far heavier
    /// than text, and the oldest ones fall off first.
    public static func pruned(
        _ items: [ClipboardItem], maxItems: Int, maxImageItems: Int
    ) -> (kept: [ClipboardItem], removed: [ClipboardItem]) {
        var kept = items
        var removed: [ClipboardItem] = []
        if kept.count > maxItems {
            removed.append(contentsOf: kept.suffix(kept.count - maxItems))
            kept = Array(kept.prefix(maxItems))
        }
        let images = kept.filter { $0.imageFile != nil }
        if images.count > maxImageItems {
            let excess = Set(images.suffix(images.count - maxImageItems).map(\.id))
            removed.append(contentsOf: kept.filter { excess.contains($0.id) })
            kept.removeAll { excess.contains($0.id) }
        }
        return (kept, removed)
    }
}
