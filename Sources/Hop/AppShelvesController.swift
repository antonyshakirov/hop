import AppKit
import Combine
import HopCore
import os

/// The launcher module: grids of apps you keep at hand, so a program you open ten
/// times a day is one click away instead of a trip to the Applications folder.
///
/// There can be several grids — a short row on one space, a full square on
/// another — and each is its own module in the panel, so they are arranged the
/// same way every other module is.
@MainActor
final class AppShelvesController: ObservableObject {
    private static let log = Logger(subsystem: "com.antonshakirov.hop", category: "AppShelves")

    @Published private(set) var shelves: AppShelves

    private let storeDir: URL
    private var file: URL { storeDir.appendingPathComponent("app-shelves.json") }
    /// Icons are read from disk and cached: a grid redraws on every hover and
    /// asking the workspace each time made the panel stutter.
    private var iconCache: [String: NSImage] = [:]

    init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        storeDir = base.appendingPathComponent(Bundle.storageIdentifier, isDirectory: true)
        if Snapshot.active {
            shelves = .empty
            return
        }
        shelves = Self.load(from: storeDir.appendingPathComponent("app-shelves.json"))
    }

    // MARK: - Shelves

    /// A fresh grid, and the module key the panel should place for it.
    @discardableResult
    func addShelf() -> String {
        let shelf = shelves.addShelf()
        save()
        return shelf.moduleKey
    }

    func removeShelf(_ id: UUID) {
        shelves.removeShelf(id)
        save()
    }

    func shelf(withKey key: String) -> AppShelf? {
        guard let id = AppShelves.shelfID(fromModuleKey: key) else { return nil }
        return shelves[id]
    }

    // MARK: - Icons on a shelf

    /// Adds whatever was dropped, as long as it is an app. A folder or a document
    /// is ignored rather than parked as a dead icon.
    @discardableResult
    func add(path: String, to shelfID: UUID) -> Bool {
        guard var shelf = shelves[shelfID] else { return false }
        let url = URL(fileURLWithPath: path)
        guard url.pathExtension.lowercased() == "app" else { return false }
        let bundle = Bundle(url: url)
        let item = ShelfItem(
            path: path,
            bundleIdentifier: bundle?.bundleIdentifier,
            name: FileManager.default.displayName(atPath: path)
                .replacingOccurrences(of: ".app", with: ""))
        guard shelf.add(item) else { return false }
        shelves[shelfID] = shelf
        save()
        return true
    }

    func remove(_ itemID: UUID, from shelfID: UUID) {
        guard var shelf = shelves[shelfID] else { return }
        shelf.remove(itemID)
        shelves[shelfID] = shelf
        save()
    }

    func move(_ itemID: UUID, to index: Int, in shelfID: UUID) {
        guard var shelf = shelves[shelfID] else { return }
        shelf.move(itemID, to: index)
        shelves[shelfID] = shelf
        save()
    }

    /// Opens the app. If it has moved since it was parked, the bundle id finds it
    /// again and the shelf quietly updates its path rather than failing.
    func launch(_ item: ShelfItem, from shelfID: UUID) {
        guard !Snapshot.active else { return }
        let manager = FileManager.default
        var url = URL(fileURLWithPath: item.path)
        if !manager.fileExists(atPath: item.path) {
            guard let bundle = item.bundleIdentifier,
                  let found = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundle) else {
                Self.log.info("shelf item is gone: \(item.name, privacy: .public)")
                return
            }
            url = found
            if var shelf = shelves[shelfID],
               let index = shelf.items.firstIndex(where: { $0.id == item.id }) {
                shelf.items[index].path = found.path
                shelves[shelfID] = shelf
                save()
            }
        }
        let options = NSWorkspace.OpenConfiguration()
        options.activates = true
        NSWorkspace.shared.openApplication(at: url, configuration: options, completionHandler: nil)
    }

    /// The app's own icon, at the size the grid draws it.
    func icon(for item: ShelfItem) -> NSImage {
        if let cached = iconCache[item.path] { return cached }
        let icon = NSWorkspace.shared.icon(forFile: item.path)
        icon.size = NSSize(width: 44, height: 44)
        iconCache[item.path] = icon
        return icon
    }

    // MARK: - Storage

    private static func load(from file: URL) -> AppShelves {
        guard let data = try? Data(contentsOf: file) else { return .empty }
        guard let decoded = try? JSONDecoder().decode(AppShelves.self, from: data) else {
            // Same rule as the other stores: an unreadable file is moved aside
            // once rather than overwritten silently.
            try? FileManager.default.moveItem(at: file, to: file.appendingPathExtension("bak"))
            return .empty
        }
        return decoded
    }

    private func save() {
        guard !Snapshot.active else { return }
        do {
            try FileManager.default.createDirectory(at: storeDir, withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(shelves)
            try data.write(to: file, options: .atomic)
        } catch {
            Self.log.error("shelves save failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}
