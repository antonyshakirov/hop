import AppKit
import Foundation
import HopCore

/// Clipboard history: once a second we compare the NSPasteboard changeCount
/// (macOS has no clipboard events — every clipboard manager does it this way).
/// Concealed content (password managers mark it with ConcealedType) is not saved.
/// The history RULES (dedup, caps) live in HopCore.ClipboardRules with tests;
/// this controller owns the pasteboard, image files and persistence.
@MainActor
final class ClipboardController: ObservableObject {
    typealias Item = ClipboardItem

    @Published private(set) var items: [Item] = []

    static let defaultMaxItems = 100
    static let maxItemsKey = "clipboardMaxItems"
    /// Images are far heavier than text: their own cap, oldest files deleted.
    static let maxImageItems = 20
    /// A pathological clipboard image (a poster-size TIFF) is skipped, not stored.
    nonisolated static let maxImageBytes = 25_000_000
    /// how many rows the collapsed clipboard shows (1...10, default 3)
    static let visibleRowsKey = "clipboardVisibleRows"
    static let defaultVisibleRows = 3

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

        // raw image data (a screenshot copied straight to the clipboard,
        // "copy image" in a browser) has no file and often no string —
        // store it as a PNG file next to the history
        if let (data, label) = Self.pngFromPasteboard(pasteboard) {
            rememberImage(data, label: label)
            return
        }

        if let text = pasteboard.string(forType: .string),
           !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            remember(text)
        }
    }

    /// PNG data + a "1280 × 800" label from clipboard image content.
    nonisolated private static func pngFromPasteboard(_ pasteboard: NSPasteboard) -> (Data, String)? {
        let raw: Data?
        if let png = pasteboard.data(forType: .png) {
            raw = png
        } else if let tiff = pasteboard.data(forType: .tiff),
                  let rep = NSBitmapImageRep(data: tiff) {
            raw = rep.representation(using: .png, properties: [:])
        } else {
            raw = nil
        }
        guard let raw, raw.count <= maxImageBytes,
              let rep = NSBitmapImageRep(data: raw), rep.pixelsWide > 0
        else { return nil }
        return (raw, "\(rep.pixelsWide) × \(rep.pixelsHigh)")
    }

    /// Directory for stored clipboard images; per bundle id, so the dev
    /// build never mixes files with the production one.
    nonisolated static var imagesDir: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base
            .appendingPathComponent(Bundle.main.bundleIdentifier ?? "com.antonshakirov.minimo")
            .appendingPathComponent("clipboard-images")
    }

    private func rememberImage(_ data: Data, label: String) {
        // the same image copied twice in a row stays a single entry
        if let first = items.first, let file = first.imageFile,
           let existing = try? Data(contentsOf: Self.imagesDir.appendingPathComponent(file)),
           existing == data {
            return
        }
        let id = UUID()
        let fileName = "\(id.uuidString).png"
        do {
            try FileManager.default.createDirectory(at: Self.imagesDir, withIntermediateDirectories: true)
            try data.write(to: Self.imagesDir.appendingPathComponent(fileName))
        } catch {
            return // no file — no entry; a dead row would be worse
        }
        items.insert(Item(id: id, text: label, imageFile: fileName), at: 0)
        pruneOverflow()
        save()
    }

    /// Enforce both caps and delete the files of everything that falls off.
    private func pruneOverflow() {
        let (kept, removed) = ClipboardRules.pruned(
            items, maxItems: maxItems, maxImageItems: Self.maxImageItems)
        items = kept
        deleteFiles(of: removed)
    }

    private func deleteFiles(of removed: [Item]) {
        for item in removed {
            if let file = item.imageFile {
                try? FileManager.default.removeItem(at: Self.imagesDir.appendingPathComponent(file))
            }
        }
    }

    private func remember(_ raw: String) {
        guard let updated = ClipboardRules.remembering(raw, in: items) else { return }
        items = updated
        pruneOverflow()
        save()
    }

    /// Clicking a history row puts the text on the clipboard WITHOUT moving it in the list.
    /// Only content copied fresh outside the history goes to the top.
    /// A row that is a path to an existing file goes back as the FILE:
    /// pasting in Finder pastes the file itself, text fields get the path.
    func copy(_ item: Item) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        if let file = item.imageFile {
            // an image entry goes back as the picture itself
            if let image = NSImage(contentsOf: Self.imagesDir.appendingPathComponent(file)) {
                pasteboard.writeObjects([image])
            }
            changeCount = pasteboard.changeCount
            return
        }
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
        deleteFiles(of: items)
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
        // entries whose file vanished are dropped; orphan files (a crash
        // between write and save) are swept
        items = stored.filter { item in
            guard let file = item.imageFile else { return true }
            return FileManager.default.fileExists(
                atPath: Self.imagesDir.appendingPathComponent(file).path)
        }
        let referenced = Set(items.compactMap(\.imageFile))
        if let onDisk = try? FileManager.default.contentsOfDirectory(atPath: Self.imagesDir.path) {
            for file in onDisk where !referenced.contains(file) {
                try? FileManager.default.removeItem(at: Self.imagesDir.appendingPathComponent(file))
            }
        }
    }
}
