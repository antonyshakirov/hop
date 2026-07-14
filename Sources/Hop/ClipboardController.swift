import AppKit
import Foundation

/// Clipboard history: once a second we compare the NSPasteboard changeCount
/// (macOS has no clipboard events — every clipboard manager does it this way).
/// Concealed content (password managers mark it with ConcealedType) is not saved.
@MainActor
final class ClipboardController: ObservableObject {
    struct Item: Identifiable, Equatable, Codable {
        let id: UUID
        let text: String
    }

    @Published private(set) var items: [Item] = []

    static let defaultMaxItems = 100
    static let maxItemsKey = "clipboardMaxItems"
    /// Protection against "accidentally copied a book": every entry is truncated,
    /// so even a full history weighs next to nothing.
    static let maxItemLength = 20_000

    private var maxItems: Int {
        let stored = UserDefaults.standard.integer(forKey: Self.maxItemsKey)
        return stored > 0 ? min(stored, 300) : Self.defaultMaxItems
    }

    private var changeCount = NSPasteboard.general.changeCount
    private var ticker: Timer?
    private let storageKey = "clipboardHistory"

    init() {
        load()
        let t = Timer(timeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.check() }
        }
        t.tolerance = 0.25
        RunLoop.main.add(t, forMode: .common)
        ticker = t
    }

    private func check() {
        let pasteboard = NSPasteboard.general
        guard pasteboard.changeCount != changeCount else { return }
        changeCount = pasteboard.changeCount

        let concealed = pasteboard.types?.contains {
            $0.rawValue == "org.nspasteboard.ConcealedType"
        } ?? false
        guard !concealed else { return }

        // a file was copied — store the FULL path, not the contents.
        // Checked BEFORE plain text: Finder puts both a file-url and the
        // bare file NAME as string, and the name alone is useless later
        if let urls = pasteboard.readObjects(forClasses: [NSURL.self]) as? [URL],
           let first = urls.first, first.isFileURL {
            remember(first.path)
            return
        }

        if let text = pasteboard.string(forType: .string),
           !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            remember(text)
        }
    }

    private func remember(_ raw: String) {
        // normalization: trailing spaces/newlines used to create "duplicates"
        let text = String(raw.prefix(Self.maxItemLength))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        // case-insensitive comparison: dictation changes capitalization retroactively
        let key = text.lowercased()
        guard !text.isEmpty, items.first?.text.lowercased() != key else {
            if let first = items.first, first.text != text {
                items[0] = Item(id: first.id, text: text) // update capitalization
                save()
            }
            return
        }

        // dictation writes growing text: substitute the new version for the old one
        if let first = items.first {
            let firstKey = first.text.lowercased()
            if key.hasPrefix(firstKey) || firstKey.hasPrefix(key) {
                items[0] = Item(id: first.id, text: text)
                save()
                return
            }
        }
        items.removeAll { $0.text.lowercased() == key }
        items.insert(Item(id: UUID(), text: text), at: 0)
        if items.count > maxItems {
            items = Array(items.prefix(maxItems))
        }
        save()
    }

    /// Clicking a history row puts the text on the clipboard WITHOUT moving it in the list.
    /// Only content copied fresh outside the history goes to the top.
    /// A row that is a path to an existing file goes back as the FILE:
    /// pasting in Finder pastes the file itself, text fields get the path.
    func copy(_ item: Item) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        if item.text.hasPrefix("/") || item.text.hasPrefix("~"),
           case let path = NSString(string: item.text).expandingTildeInPath,
           FileManager.default.fileExists(atPath: path) {
            let url = URL(fileURLWithPath: path)
            pasteboard.writeObjects([url as NSURL])
            // the path as text alongside: apps that only take strings
            // still receive something meaningful
            pasteboard.setString(item.text, forType: .string)
        } else {
            pasteboard.setString(item.text, forType: .string)
        }
        changeCount = pasteboard.changeCount
    }

    /// "Copy and paste": put it on the clipboard, close the panel
    /// and press ⌘V for the user (requires Accessibility permission).
    func copyAndPaste(_ item: Item, closePanel: @escaping () -> Void) {
        copy(item)
        let options = [kAXTrustedCheckOptionPrompt.takeRetainedValue() as String: true] as CFDictionary
        guard AXIsProcessTrustedWithOptions(options) else { return }
        closePanel()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            let source = CGEventSource(stateID: .combinedSessionState)
            let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: true) // V
            keyDown?.flags = .maskCommand
            let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: false)
            keyUp?.flags = .maskCommand
            keyDown?.post(tap: .cghidEventTap)
            keyUp?.post(tap: .cghidEventTap)
        }
    }

    func clear() {
        items = []
        save()
    }

    private func save() {
        if let data = try? JSONEncoder().encode(items) {
            UserDefaults.standard.set(data, forKey: storageKey)
        }
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let stored = try? JSONDecoder().decode([Item].self, from: data)
        else { return }
        items = stored
    }
}
