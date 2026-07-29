import Foundation

/// One app parked on a shelf. The path is what launches it; the bundle id is
/// what survives the app moving house (a rename, a reinstall into another
/// folder), so a shelf can heal itself instead of holding a dead icon.
public struct ShelfItem: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public var path: String
    public var bundleIdentifier: String?
    /// The name shown under the icon; the file name is the fallback.
    public var name: String

    public init(id: UUID = UUID(), path: String, bundleIdentifier: String? = nil, name: String) {
        self.id = id
        self.path = path
        self.bundleIdentifier = bundleIdentifier
        self.name = name
    }

    private enum CodingKeys: String, CodingKey { case id, path, bundleIdentifier, name }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        path = try container.decode(String.self, forKey: .path)
        bundleIdentifier = try container.decodeIfPresent(String.self, forKey: .bundleIdentifier)
        name = try container.decodeIfPresent(String.self, forKey: .name)
            ?? (path as NSString).lastPathComponent
    }
}

/// One grid of apps. There can be several — a row of six at the top of a space,
/// a full square at the bottom of another — so each carries its own id and the
/// panel addresses it by that.
public struct AppShelf: Codable, Equatable, Identifiable, Sendable {
    /// Eight across, eight down: the shape Anton asked for, and the point past
    /// which a grid stops being scannable at a glance.
    public static let columns = 8
    public static let maxItems = columns * columns

    public let id: UUID
    public var items: [ShelfItem]
    /// What this grid is called. Empty means "no name of its own" and the module
    /// falls back to the generic label — several grids on one space need telling
    /// apart, but the first one should not have to be named to be usable.
    public var title: String
    /// Whether the app names are drawn under the icons. Off gives a dense wall of
    /// icons for someone who recognises them by sight.
    public var showsLabels: Bool

    public init(id: UUID = UUID(), items: [ShelfItem] = [],
                title: String = "", showsLabels: Bool = true) {
        self.id = id
        self.items = items
        self.title = title
        self.showsLabels = showsLabels
    }

    private enum CodingKeys: String, CodingKey { case id, items, title, showsLabels }

    /// Both new fields decode leniently, so a file written before they existed
    /// keeps working.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        items = try container.decodeIfPresent([ShelfItem].self, forKey: .items) ?? []
        title = try container.decodeIfPresent(String.self, forKey: .title) ?? ""
        showsLabels = try container.decodeIfPresent(Bool.self, forKey: .showsLabels) ?? true
    }

    /// The module key the panel stores for this shelf. Every other module is one
    /// of a kind and uses a bare word; a shelf carries its id so several can live
    /// side by side.
    public var moduleKey: String { "apps:\(id.uuidString)" }

    public var isFull: Bool { items.count >= Self.maxItems }

    /// Appends an app unless the same one is already here or the grid is full.
    /// Returns false when nothing was added, so the caller can say why.
    @discardableResult
    public mutating func add(_ item: ShelfItem) -> Bool {
        guard !isFull else { return false }
        guard !items.contains(where: { $0.path == item.path }) else { return false }
        items.append(item)
        return true
    }

    public mutating func remove(_ id: UUID) {
        items.removeAll { $0.id == id }
    }

    /// Moves an icon to `destination`, the index it should end up at — the other
    /// icons shuffle around it, the way a home screen behaves. Out-of-range
    /// indices clamp rather than crash.
    public mutating func move(_ id: UUID, to destination: Int) {
        guard let from = items.firstIndex(where: { $0.id == id }) else { return }
        let item = items.remove(at: from)
        items.insert(item, at: max(0, min(destination, items.count)))
    }
}

/// Every shelf the user has, persisted as one file.
public struct AppShelves: Codable, Equatable, Sendable {
    public var shelves: [AppShelf]

    public static let empty = AppShelves(shelves: [])

    public init(shelves: [AppShelf] = []) {
        self.shelves = shelves
    }

    private enum CodingKeys: String, CodingKey { case shelves }

    /// Tolerant like the other stores: a file written by an older build, or one
    /// that lost its key, loads as empty instead of being treated as corrupt.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        shelves = try container.decodeIfPresent([AppShelf].self, forKey: .shelves) ?? []
    }

    public subscript(id: UUID) -> AppShelf? {
        get { shelves.first { $0.id == id } }
        set {
            guard let index = shelves.firstIndex(where: { $0.id == id }) else {
                if let newValue { shelves.append(newValue) }
                return
            }
            if let newValue { shelves[index] = newValue } else { shelves.remove(at: index) }
        }
    }

    /// The module keys the panel should know about, in shelf order.
    public var moduleKeys: [String] { shelves.map(\.moduleKey) }

    /// The shelf a module key names, if it names one.
    public static func shelfID(fromModuleKey key: String) -> UUID? {
        guard key.hasPrefix("apps:") else { return nil }
        return UUID(uuidString: String(key.dropFirst("apps:".count)))
    }

    @discardableResult
    public mutating func addShelf() -> AppShelf {
        let shelf = AppShelf()
        shelves.append(shelf)
        return shelf
    }

    public mutating func removeShelf(_ id: UUID) {
        shelves.removeAll { $0.id == id }
    }
}
