import Foundation

/// A key combination as Carbon stores it, spelled out so HopCore needs no Carbon import.
public struct ModuleCombo: Equatable, Hashable, Sendable {
    public static let control: UInt32 = 0x1000
    public static let option: UInt32 = 0x0800
    public static let shift: UInt32 = 0x0200
    public static let command: UInt32 = 0x0100

    public let keyCode: UInt32
    public let modifiers: UInt32

    public init(keyCode: UInt32, modifiers: UInt32) {
        self.keyCode = keyCode
        self.modifiers = modifiers
    }
}

/// One thing a hotkey can do: `defaultCombo` nil means nothing is claimed until the user picks one.
public struct ModuleAction: Equatable, Hashable, Sendable {
    public let id: String
    public let storageKey: String
    public let hotKeyID: UInt32
    public let defaultCombo: ModuleCombo?

    public init(id: String, storageKey: String, hotKeyID: UInt32, defaultCombo: ModuleCombo? = nil) {
        self.id = id
        self.storageKey = storageKey
        self.hotKeyID = hotKeyID
        self.defaultCombo = defaultCombo
    }
}

/// One module of the panel, as data: identity, how it ships, and what it can be
/// asked to do. A module has an "open" action only when pressing a key would
/// show something without the panel — a window of its own, or a change on screen
/// (Anton, 2026-09-01): the rest of the modules are read IN the panel, so a key
/// for them would only open the panel a key already opens.
public struct ModuleEntry: Equatable, Hashable, Sendable {
    public let id: String
    public let hiddenOnFirstRun: Bool
    public let actions: [ModuleAction]

    public init(id: String, hiddenOnFirstRun: Bool = false, actions: [ModuleAction]) {
        self.id = id
        self.hiddenOnFirstRun = hiddenOnFirstRun
        self.actions = actions
    }

    /// The action that shows the module, when it has one.
    public var openAction: ModuleAction? { actions.first { $0.id == "open" } }
}

/// SPEC: hop-private/specs/2026-09-01-settings-window-design.md — the one list of modules.
public enum ModuleCatalog {
    private static let controlOption = ModuleCombo.control | ModuleCombo.option

    public static let panelAction = ModuleAction(
        id: "panel", storageKey: "hotkey_panel", hotKeyID: 1,
        defaultCombo: ModuleCombo(keyCode: 46, modifiers: controlOption)
    )

    public static let modules: [ModuleEntry] = [
        ModuleEntry(id: "timer", actions: [
            ModuleAction(id: "open", storageKey: "hotkey_timer", hotKeyID: 2,
                         defaultCombo: ModuleCombo(keyCode: 17, modifiers: controlOption)),
        ]),
        ModuleEntry(id: "awake", actions: [
            ModuleAction(id: "open", storageKey: "hotkey_awake", hotKeyID: 3,
                         defaultCombo: ModuleCombo(keyCode: 13, modifiers: controlOption)),
        ]),
        ModuleEntry(id: "clipboard", actions: []),
        ModuleEntry(id: "convert", actions: [
            ModuleAction(id: "open", storageKey: "hotkey_convert", hotKeyID: 21),
        ]),
        ModuleEntry(id: "windows", actions: []),
        ModuleEntry(id: "speedtest", actions: []),
        ModuleEntry(id: "torrent", actions: []),
        ModuleEntry(id: "color", hiddenOnFirstRun: true, actions: [
            ModuleAction(id: "open", storageKey: "hotkey_color", hotKeyID: 4,
                         defaultCombo: ModuleCombo(keyCode: 35, modifiers: controlOption)),
        ]),
        ModuleEntry(id: "ocr", hiddenOnFirstRun: true, actions: [
            ModuleAction(id: "open", storageKey: "hotkey_ocr", hotKeyID: 5,
                         defaultCombo: ModuleCombo(keyCode: 15, modifiers: controlOption)),
        ]),
        ModuleEntry(id: "archive", actions: [
            ModuleAction(id: "open", storageKey: "hotkey_archive", hotKeyID: 25),
        ]),
        ModuleEntry(id: "keyboard", actions: [
            ModuleAction(id: "open", storageKey: "hotkey_keyboardLock", hotKeyID: 6,
                         defaultCombo: ModuleCombo(keyCode: 7, modifiers: controlOption)),
        ]),
        ModuleEntry(id: "vpn", hiddenOnFirstRun: true, actions: []),
        ModuleEntry(id: "uninstall", actions: [
            ModuleAction(id: "open", storageKey: "hotkey_uninstall", hotKeyID: 27),
        ]),
        ModuleEntry(id: "system", actions: []),
        ModuleEntry(id: "tracker", actions: []),
        ModuleEntry(id: "todos", actions: []),
    ]

    public static func module(_ id: String) -> ModuleEntry? {
        modules.first { $0.id == id }
    }

    /// The "open" action of one module, or nil when no such module exists.
    public static func open(_ id: String) -> ModuleAction? {
        module(id)?.openAction
    }

    /// Every action the app can register, the panel's own included.
    public static var allActions: [ModuleAction] {
        [panelAction] + modules.flatMap(\.actions)
    }

    public static var allIDs: [String] { modules.map(\.id) }
}
