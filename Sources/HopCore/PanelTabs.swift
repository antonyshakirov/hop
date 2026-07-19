import Foundation

/// A single user-managed tab ("space") in the panel: an icon plus the
/// ordered module keys shown while that tab is selected.
public struct PanelTab: Codable, Equatable, Identifiable {
    public let id: UUID
    public var icon: String
    public var moduleKeys: [String]

    public init(id: UUID = UUID(), icon: String, moduleKeys: [String]) {
        self.id = id
        self.icon = icon
        self.moduleKeys = moduleKeys
    }
}

/// The user's arrangement of panel tabs. Every mutating method below
/// preserves two invariants: `tabs.count` stays within `1...maxTabs`, and
/// each module key lives in at most one place — a tab OR the inactive bucket.
/// Methods that would otherwise break an invariant (deleting the last tab,
/// referencing an unknown tab or module) are no-ops rather than errors, since
/// callers are UI actions that can simply be stale.
///
/// Module visibility is MEMBERSHIP: a module is shown iff it sits on a tab, and
/// hidden iff it sits in `inactive`. There is no separate on/off flag.
public struct PanelTabsModel: Codable, Equatable {
    public var tabs: [PanelTab]
    /// Hidden modules, ordered. A permanent, non-deletable bucket in the UI.
    public var inactive: [String]

    public static let maxTabs = 4

    public init(tabs: [PanelTab], inactive: [String] = []) {
        self.tabs = tabs
        self.inactive = inactive
    }

    private enum CodingKeys: String, CodingKey { case tabs, inactive }

    /// `inactive` is decoded leniently so models saved before the field
    /// existed keep loading (missing → empty bucket) instead of failing to
    /// decode and wiping the user's spaces back to a fresh migrate.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        tabs = try container.decode([PanelTab].self, forKey: .tabs)
        inactive = try container.decodeIfPresent([String].self, forKey: .inactive) ?? []
    }

    /// Adds an empty tab with `icon`. Returns its id, or nil (no change) if
    /// `maxTabs` is already reached.
    @discardableResult
    public mutating func addTab(icon: String) -> UUID? {
        guard tabs.count < Self.maxTabs else { return nil }
        let tab = PanelTab(icon: icon, moduleKeys: [])
        tabs.append(tab)
        return tab.id
    }

    /// Removes the tab, sending its modules to the inactive bucket (they are
    /// hidden, not silently merged into another space). No-op if `id` is
    /// unknown or this is the last tab.
    public mutating func deleteTab(_ id: UUID) {
        guard tabs.count > 1, let index = tabs.firstIndex(where: { $0.id == id }) else { return }
        let removed = tabs.remove(at: index)
        inactive.append(contentsOf: removed.moduleKeys)
    }

    /// Moves the tab at `from` to `to`. No-op if either index is out of
    /// bounds for the current tab count.
    public mutating func moveTab(from: Int, to: Int) {
        guard tabs.indices.contains(from), tabs.indices.contains(to) else { return }
        let tab = tabs.remove(at: from)
        tabs.insert(tab, at: to)
    }

    /// No-op if `tabID` doesn't match any tab.
    public mutating func setIcon(_ icon: String, tabID: UUID) {
        guard let index = tabs.firstIndex(where: { $0.id == tabID }) else { return }
        tabs[index].icon = icon
    }

    /// Moves `module` to the end of `toTab`'s module list, removing it from
    /// wherever it currently lives — another tab OR the inactive bucket (so
    /// this is also how a hidden module is reactivated). No-op if the module or
    /// the target tab isn't known.
    public mutating func move(module: String, toTab: UUID) {
        guard let toIndex = tabs.firstIndex(where: { $0.id == toTab }) else { return }
        if let fromIndex = tabs.firstIndex(where: { $0.moduleKeys.contains(module) }) {
            tabs[fromIndex].moduleKeys.removeAll { $0 == module }
        } else if inactive.contains(module) {
            inactive.removeAll { $0 == module }
        } else {
            return   // unknown module — no-op
        }
        tabs[toIndex].moduleKeys.append(module)
    }

    /// Hides `module`: removes it from its tab and appends it to the inactive
    /// bucket. No-op if the module is unknown or already inactive.
    public mutating func deactivate(module: String) {
        guard let fromIndex = tabs.firstIndex(where: { $0.moduleKeys.contains(module) }) else { return }
        tabs[fromIndex].moduleKeys.removeAll { $0 == module }
        inactive.append(module)
    }

    /// Repositions `module` within `inTab`'s own module list. `to` is
    /// clamped to the tab's valid index range, so a caller can pass an
    /// out-of-range index to mean "move to the start/end". No-op if the tab
    /// or the module within it isn't known.
    public mutating func reorder(module: String, inTab: UUID, to: Int) {
        guard let tabIndex = tabs.firstIndex(where: { $0.id == inTab }),
              let moduleIndex = tabs[tabIndex].moduleKeys.firstIndex(of: module) else { return }
        tabs[tabIndex].moduleKeys.remove(at: moduleIndex)
        let clamped = min(max(to, 0), tabs[tabIndex].moduleKeys.count)
        tabs[tabIndex].moduleKeys.insert(module, at: clamped)
    }

    /// Repositions `module` within the inactive bucket — the symmetric sibling
    /// of `reorder(module:inTab:to:)`, treating `inactive` as a pseudo-column.
    /// `to` is clamped; no-op if the module isn't in the bucket.
    public mutating func reorder(inInactive module: String, to: Int) {
        guard let moduleIndex = inactive.firstIndex(of: module) else { return }
        inactive.remove(at: moduleIndex)
        let clamped = min(max(to, 0), inactive.count)
        inactive.insert(module, at: clamped)
    }

    /// Appends any of `modules` not already present in a tab OR the inactive
    /// bucket to the first tab. Used at app-update time to place newly
    /// introduced modules somewhere (new modules ship visible) without
    /// disturbing existing tabs or reactivating a hidden module.
    public mutating func ensure(modules: [String]) {
        var known = Set(tabs.flatMap(\.moduleKeys)).union(inactive)
        let missing = modules.filter { key in
            guard !known.contains(key) else { return false }
            known.insert(key)
            return true
        }
        tabs[0].moduleKeys.append(contentsOf: missing)
    }

    /// The id of the tab holding `module`, or nil if no tab does.
    public func tabID(containing module: String) -> UUID? {
        tabs.first { $0.moduleKeys.contains(module) }?.id
    }

    /// JSON representation for UserDefaults storage.
    public func encoded() -> String {
        guard let data = try? JSONEncoder().encode(self),
              let string = String(data: data, encoding: .utf8) else {
            return ""
        }
        return string
    }

    /// Inverse of `encoded()`. Returns nil for anything that isn't a valid
    /// encoding of this type, so callers can fall back to `migrate` on
    /// first launch or corrupted storage. This also rejects well-formed
    /// JSON that violates the model's own invariants (tab count, unique
    /// module keys) — storage is UserDefaults, which a user can hand-edit.
    public static func decode(_ raw: String) -> PanelTabsModel? {
        guard let data = raw.data(using: .utf8),
              let model = try? JSONDecoder().decode(PanelTabsModel.self, from: data),
              model.isValid else { return nil }
        return model
    }

    /// Whether the model currently satisfies both documented invariants: a
    /// valid tab count, and every module key unique across tabs AND inactive.
    private var isValid: Bool {
        guard (1...Self.maxTabs).contains(tabs.count) else { return false }
        let allKeys = tabs.flatMap(\.moduleKeys) + inactive
        return Set(allKeys).count == allKeys.count
    }

    /// First-launch migration from the old flat module order: everything
    /// goes into a "house" tab, with the system monitor split into its own
    /// "display" tab (it should LOOK like a monitor) and the time-management
    /// pair — tracker + to-dos — into a "clock" tab. A fresh migrate already
    /// contains "system", "tracker" and "todos", so `ensure` appends nothing
    /// for them.
    public static func migrate(moduleOrder: [String]) -> PanelTabsModel {
        let primary = PanelTab(icon: "house", moduleKeys: moduleOrder)
        let system = PanelTab(icon: "display", moduleKeys: ["system"])
        let tracker = PanelTab(icon: "clock", moduleKeys: ["tracker", "todos"])
        return PanelTabsModel(tabs: [primary, system, tracker])
    }
}
