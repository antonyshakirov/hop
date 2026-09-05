import AppKit
import Foundation
import HopCore
import UniformTypeIdentifiers

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
    /// Picked colours have their own cap and their own visible-row count: the
    /// eyedropper module IS this slice of the history (Anton, 2026-07-25).
    static let maxColorsKey = "colorMaxItems"
    static let defaultMaxColors = 20
    static let colorRowsKey = "colorVisibleRows"
    static let defaultColorRows = 3
    static let defaultVisibleRows = 3

    private var maxItems: Int {
        let stored = UserDefaults.standard.integer(forKey: Self.maxItemsKey)
        return stored > 0 ? min(stored, 300) : Self.defaultMaxItems
    }

    private var maxColors: Int {
        let stored = UserDefaults.standard.integer(forKey: Self.maxColorsKey)
        return stored > 0 ? min(stored, 100) : Self.defaultMaxColors
    }

    /// The colours picked so far, newest first — the eyedropper module's list.
    var colors: [Item] { items.filter { $0.colorHex != nil } }

    private var changeCount = NSPasteboard.general.changeCount
    private var ticker: Timer?
    private let storageKey = "clipboardHistory"

    init() {
        load()
        applyActivation()
        NotificationCenter.default.addObserver(
            forName: ModuleActivation.didChange, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.applyActivation() }
        }
    }

    /// SPEC: docs/spec.md — "A module that is off is off everywhere".
    func applyActivation() {
        guard ModuleActivation.isOn("clipboard") else {
            ticker?.invalidate()
            ticker = nil
            return
        }
        guard ticker == nil else { return }
        // what was copied while the module was off belongs to that time
        changeCount = NSPasteboard.general.changeCount
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

        // Read the pasteboard's three faces and let HopCore pick the winner: a
        // copied FILE beats the icon/thumbnail preview Finder ships beside it,
        // an image beats bare text. Reading file URLs FIRST is the fix for a
        // copied file landing as a "1024 × 1024" image row.
        let fileURLs = pasteboard.readObjects(
            forClasses: [NSURL.self],
            options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []
        let paths = fileURLs.filter(\.isFileURL).map(\.path)
        let text = pasteboard.string(forType: .string)
        // only touch the (potentially large) image data when no file won
        let image = paths.isEmpty ? Self.pngFromPasteboard(pasteboard) : nil

        switch ClipboardRules.classify(fileURLPaths: paths, hasImage: image != nil, text: text) {
        case .files(let paths):
            rememberFiles(paths)
        case .image:
            if let (data, label) = image { rememberImage(data, label: label) }
        case .text(let value):
            remember(value)
        case .ignore:
            break
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
            .appendingPathComponent(Bundle.storageIdentifier)
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
            items, maxItems: maxItems, maxImageItems: Self.maxImageItems,
            maxColorItems: maxColors)
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

    /// One or more files copied in Finder become a single FILE entry (the paths
    /// are stored; the row shows the file name). We never own these files, so
    /// pruning them off the history never deletes anything on disk.
    private func rememberFiles(_ paths: [String]) {
        guard let updated = ClipboardRules.remembering(files: paths, in: items) else { return }
        items = updated
        pruneOverflow()
        save()
    }

    /// Content Hop PRODUCED itself — a picked color, text read off the screen —
    /// enters the history here. Modules can't call `remember` directly (the rules
    /// and persistence are ours), and they need the value on the pasteboard in the
    /// same breath: that IS the feature ("key, then paste"). `place` also stamps
    /// the change counter, so our own write never comes back a second later as a
    /// foreign copy and a duplicate row.
    func remember(external raw: String) {
        remember(raw)
        place(raw)
    }

    /// The eyedropper's entry point: `hex` is the canonical "RRGGBB" the row's
    /// swatch is drawn from, `text` the notation the user pastes. The value goes
    /// on the pasteboard even when the history stays as it is (the same color
    /// picked twice) — the point of picking is having it ready to paste.
    func remember(color hex: String, text: String) {
        if let updated = ClipboardRules.remembering(color: hex, text: text, in: items) {
            items = updated
            pruneOverflow()
            save()
        }
        place(text)
    }

    /// Put text on the pasteboard WITHOUT touching the history — for content
    /// that is already in the list (clicking a colour the eyedropper picked
    /// earlier). Re-remembering it would move the row to the top and rebuild it,
    /// which stole the "copied" mark and reshuffled the list under the cursor
    /// (Anton, 2026-07-25).
    func putOnPasteboard(_ text: String) {
        place(text)
    }

    private func place(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        changeCount = pasteboard.changeCount
    }

    /// Clicking a history row puts the content on the clipboard WITHOUT moving it
    /// in the list. Only content copied fresh outside the history goes to the top.
    /// A FILE entry goes back as the file URL(s): pasting in Finder pastes the
    /// file itself, a text field gets the path(s).
    func copy(_ item: Item) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        if let paths = item.filePaths, !paths.isEmpty {
            // vanished files are skipped; if all are gone we still hand over the
            // path text so the row does something meaningful
            let present = paths.filter { FileManager.default.fileExists(atPath: $0) }
            let live = present.isEmpty ? paths : present
            pasteboard.writeObjects(live.map { URL(fileURLWithPath: $0) as NSURL })
            // the path(s) as text alongside: apps that only take strings still
            // receive something meaningful
            pasteboard.setString(live.joined(separator: "\n"), forType: .string)
            changeCount = pasteboard.changeCount
            return
        }
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
    /// Writes a text entry to disk. Straight to the Desktop under a name taken
    /// from the text itself, or — when `askForLocation` — through the system's
    /// own save panel, the one place a person can retype the name and pick the
    /// folder in a single step.
    ///
    /// Returns the file it wrote. An entry that is an image, a file or a colour
    /// has no document in it and returns nil.
    @discardableResult
    func saveAsDocument(_ item: Item, askForLocation: Bool,
                        format: ClipboardDocument.Format = .txt) -> URL? {
        guard !Snapshot.active,
              item.imageFile == nil, item.filePaths == nil,
              !item.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else { return nil }

        let manager = FileManager.default
        let desktop = manager.urls(for: .desktopDirectory, in: .userDomainMask).first
            ?? manager.homeDirectoryForCurrentUser
        let base = ClipboardDocument.fileName(for: item.text)

        let target: URL
        if askForLocation {
            let panel = NSSavePanel()
            panel.nameFieldStringValue = "\(base).\(format.fileExtension)"
            panel.directoryURL = desktop
            if let type = Self.contentType(for: format) { panel.allowedContentTypes = [type] }
            guard panel.runModal() == .OK, let chosen = panel.url else { return nil }
            target = chosen
        } else {
            // Finder's own rule for a name already taken: " 2", " 3"… — saving the
            // same entry twice must not quietly overwrite the first file.
            let name = ClipboardDocument.uniqueName(base, ext: format.fileExtension) { candidate in
                manager.fileExists(atPath: desktop.appendingPathComponent(candidate).path)
            }
            target = desktop.appendingPathComponent(name)
        }

        return Self.write(item.text, as: format, to: target) ? target : nil
    }

    /// Text goes to disk as it is; pdf and docx are RENDERED from it through the
    /// converter's own writers — the same ones the document module uses — so a
    /// copied markdown snippet comes out formatted instead of showing its
    /// asterisks, and the pdf carries Hop's typography rather than a default.
    private static func write(_ text: String, as format: ClipboardDocument.Format,
                              to url: URL) -> Bool {
        if format.isPlainText {
            return (try? text.write(to: url, atomically: true, encoding: .utf8)) != nil
        }
        let attributed = DocumentConversion.attributed(markdown: text)
        switch format {
        case .pdf: return DocumentConversion.writePDF(attributed, to: url)
        case .docx: return DocumentConversion.writeDocx(attributed, to: url)
        case .txt, .md: return false   // handled above
        }
    }

    private static func contentType(for format: ClipboardDocument.Format) -> UTType? {
        switch format {
        case .txt: return .plainText
        case .md: return UTType(filenameExtension: "md")
        case .pdf: return .pdf
        case .docx: return UTType(filenameExtension: "docx")
        }
    }

    func copyAndPaste(_ item: Item, closePanel: @escaping () -> Void) {
        copy(item)
        guard AXIsProcessTrusted() else {
            // The copy went through: only the keystroke failed, and the panel
            // stays open to carry the reason.
            AccessibilityWatch.shared.reportBlocked(notify: false)
            PermissionRepair.askAgain(.accessibility)
            return
        }
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
