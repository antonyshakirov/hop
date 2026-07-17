import Foundation

/// A clipboard-history entry. Lives in HopCore so the history rules are
/// unit-testable; the app side owns the pasteboard, image files and storage.
public struct ClipboardItem: Identifiable, Equatable, Codable {
    public let id: UUID
    public var text: String
    /// PNG file name in the images dir — set for image entries (screenshots
    /// copied straight to the clipboard); `text` then holds "1280 × 800".
    public var imageFile: String?

    public init(id: UUID = UUID(), text: String, imageFile: String? = nil) {
        self.id = id
        self.text = text
        self.imageFile = imageFile
    }
}

/// Pure history rules: what a fresh copy does to the list and how the
/// caps trim it. No pasteboard, no files — those stay in the controller.
public enum ClipboardRules {
    /// Protection against "accidentally copied a book": every entry is
    /// truncated, so even a full history weighs next to nothing.
    public static let maxItemLength = 20_000

    /// A fresh text copy folded into the history. Returns nil when the
    /// list should not change (empty text, exact repeat of the top entry).
    public static func remembering(_ raw: String, in items: [ClipboardItem]) -> [ClipboardItem]? {
        // normalization: trailing spaces/newlines used to create "duplicates"
        let text = String(raw.prefix(maxItemLength))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        // case-insensitive comparison: dictation changes capitalization
        // retroactively. Image entries never take part in text dedup —
        // their "1280 × 800" label may collide with genuinely copied text
        let key = text.lowercased()
        if let first = items.first, first.imageFile == nil {
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
        var out = items.filter { !($0.imageFile == nil && $0.text.lowercased() == key) }
        out.insert(ClipboardItem(text: text), at: 0)
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
