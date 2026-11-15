import Foundation

/// Search and keyboard selection for the standalone clipboard picker.
public enum ClipboardPicker {
    public enum Action: Equatable {
        case choose(Int), move(Int), copySelection, dismiss
    }

    public static func results(in items: [ClipboardItem], query: String) -> [ClipboardItem] {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return items }
        return items.filter { $0.text.localizedCaseInsensitiveContains(query) }
    }

    public static func action(keyCode: UInt16, modifiers: UInt) -> Action? {
        let chord = modifiers & ((1 << 20) | (1 << 19) | (1 << 18) | (1 << 17))
        if chord == 1 << 20 {
            let digits: [UInt16] = [18, 19, 20, 21, 23, 22, 26, 28, 25]
            return digits.firstIndex(of: keyCode).map(Action.choose)
        }
        guard chord == 0 else { return nil }
        switch keyCode {
        case 125: return .move(1)
        case 126: return .move(-1)
        case 36, 76: return .copySelection
        case 53: return .dismiss
        default: return nil
        }
    }

    public static func selectedIndex(id: UUID?, in items: [ClipboardItem]) -> Int? {
        guard !items.isEmpty else { return nil }
        return id.flatMap { selected in items.firstIndex { $0.id == selected } } ?? 0
    }

    public static func moving(id: UUID?, by delta: Int, in items: [ClipboardItem]) -> UUID? {
        guard let current = selectedIndex(id: id, in: items) else { return nil }
        return items[max(0, min(items.count - 1, current + delta))].id
    }
}
