import Foundation

/// A key combination as Carbon stores it, spelled out so HopCore needs no Carbon import.
public struct ModuleCombo: Equatable, Sendable {
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
public struct ModuleAction: Equatable, Sendable {
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

/// One module of the panel, as data: identity, how it ships, and what it can be asked to do.
public struct ModuleEntry: Equatable, Sendable {
    public let id: String
    public let hiddenOnFirstRun: Bool
    public let actions: [ModuleAction]

    public init(id: String, hiddenOnFirstRun: Bool = false, actions: [ModuleAction]) {
        self.id = id
        self.hiddenOnFirstRun = hiddenOnFirstRun
        self.actions = actions
    }
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
        ModuleEntry(id: "clipboard", actions: [
            ModuleAction(id: "open", storageKey: "hotkey_clipboard", hotKeyID: 20),
        ]),
        ModuleEntry(id: "convert", actions: [
            ModuleAction(id: "open", storageKey: "hotkey_convert", hotKeyID: 21),
        ]),
        ModuleEntry(id: "windows", actions: [
            ModuleAction(id: "open", storageKey: "hotkey_windows", hotKeyID: 22),
        ]),
        ModuleEntry(id: "speedtest", actions: [
            ModuleAction(id: "open", storageKey: "hotkey_speedtest", hotKeyID: 23),
        ]),
        ModuleEntry(id: "torrent", actions: [
            ModuleAction(id: "open", storageKey: "hotkey_torrent", hotKeyID: 24),
        ]),
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
        ModuleEntry(id: "vpn", hiddenOnFirstRun: true, actions: [
            ModuleAction(id: "open", storageKey: "hotkey_vpn", hotKeyID: 26),
        ]),
        ModuleEntry(id: "uninstall", actions: [
            ModuleAction(id: "open", storageKey: "hotkey_uninstall", hotKeyID: 27),
        ]),
        ModuleEntry(id: "system", actions: [
            ModuleAction(id: "open", storageKey: "hotkey_system", hotKeyID: 28),
        ]),
        ModuleEntry(id: "tracker", actions: [
            ModuleAction(id: "open", storageKey: "hotkey_tracker", hotKeyID: 29),
        ]),
        ModuleEntry(id: "todos", actions: [
            ModuleAction(id: "open", storageKey: "hotkey_todos", hotKeyID: 30),
        ]),
    ]

    public static func module(_ id: String) -> ModuleEntry? {
        modules.first { $0.id == id }
    }

    public static var allIDs: [String] { modules.map(\.id) }
}
