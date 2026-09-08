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
    public static let zonePrefix = "zone:"

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

    /// One of the window-manager's zones, which the whole set can be silenced by.
    public var isWindowZone: Bool { id.hasPrefix(Self.zonePrefix) }

    /// The zone's own name, for the view layer to draw it by.
    public var zoneName: String? {
        isWindowZone ? String(id.dropFirst(Self.zonePrefix.count)) : nil
    }
}

/// One module of the panel, as data: identity, how it ships, and what it can be
/// asked to do. A module has an "open" action only when pressing a key would
/// show something without the panel — a window of its own, or a change on
/// screen: the rest of the modules are read IN the panel, so a key for them
/// would only open the panel a key already opens.
public struct ModuleEntry: Equatable, Hashable, Sendable {
    public let id: String
    public let hiddenOnFirstRun: Bool
    /// The module's letter in the guide address; never reassigned.
    /// SPEC: hop-website/docs/guide-code.md
    public let guideLetter: String
    public let actions: [ModuleAction]

    public init(id: String, hiddenOnFirstRun: Bool = false, guideLetter: String, actions: [ModuleAction]) {
        self.id = id
        self.hiddenOnFirstRun = hiddenOnFirstRun
        self.guideLetter = guideLetter
        self.actions = actions
    }

    /// The action that shows the module, when it has one.
    public var openAction: ModuleAction? { actions.first { $0.id == "open" } }
}

/// SPEC: docs/spec.md — "Settings window", the one list of modules.
public enum ModuleCatalog {
    private static let controlOption = ModuleCombo.control | ModuleCombo.option

    public static let panelAction = ModuleAction(
        id: "panel", storageKey: "hotkey_panel", hotKeyID: 1,
        defaultCombo: ModuleCombo(keyCode: 4, modifiers: controlOption)
    )

    /// The drawing layer's second key: it hands the screen back and takes it
    /// again, so the windows underneath can be worked with without closing the
    /// layer. ⌃⌥P out of the box — the letters of the modules and of the
    /// window zones were all spoken for. It is claimed ONLY while the layer is
    /// up: a key that does nothing on ninety-nine screens out of a hundred has
    /// no business holding a combination away from every other app.
    /// SPEC: docs/spec.md — "Draw over the screen".
    public static let annotatePassAction = ModuleAction(
        id: "pass", storageKey: "hotkey_annotate_pass", hotKeyID: 35,
        defaultCombo: ModuleCombo(keyCode: 35, modifiers: controlOption)
    )

    public static let modules: [ModuleEntry] = [
        ModuleEntry(id: "timer", guideLetter: "t", actions: [
            ModuleAction(id: "open", storageKey: "hotkey_timer", hotKeyID: 2,
                         defaultCombo: ModuleCombo(keyCode: 17, modifiers: controlOption)),
        ]),
        ModuleEntry(id: "awake", guideLetter: "a", actions: [
            ModuleAction(id: "open", storageKey: "hotkey_awake", hotKeyID: 3,
                         defaultCombo: ModuleCombo(keyCode: 0, modifiers: controlOption)),
        ]),
        ModuleEntry(id: "clipboard", guideLetter: "c", actions: []),
        ModuleEntry(id: "convert", guideLetter: "f", actions: [
            ModuleAction(id: "open", storageKey: "hotkey_convert", hotKeyID: 21,
                         defaultCombo: ModuleCombo(keyCode: 8, modifiers: controlOption)),
        ]),
        ModuleEntry(id: "windows", guideLetter: "w", actions: zoneActions),
        ModuleEntry(id: "speedtest", guideLetter: "s", actions: []),
        ModuleEntry(id: "torrent", guideLetter: "d", actions: []),
        ModuleEntry(id: "color", hiddenOnFirstRun: true, guideLetter: "p", actions: [
            ModuleAction(id: "open", storageKey: "hotkey_color", hotKeyID: 4,
                         defaultCombo: ModuleCombo(keyCode: 31, modifiers: controlOption)),
        ]),
        ModuleEntry(id: "ocr", hiddenOnFirstRun: true, guideLetter: "o", actions: [
            ModuleAction(id: "open", storageKey: "hotkey_ocr", hotKeyID: 5,
                         defaultCombo: ModuleCombo(keyCode: 15, modifiers: controlOption)),
        ]),
        ModuleEntry(id: "shot", guideLetter: "g", actions: [
            ModuleAction(id: "open", storageKey: "hotkey_shot", hotKeyID: 30,
                         defaultCombo: ModuleCombo(keyCode: 1, modifiers: controlOption)),
            ModuleAction(id: "window", storageKey: "hotkey_shot_window", hotKeyID: 31),
            ModuleAction(id: "screen", storageKey: "hotkey_shot_screen", hotKeyID: 32),
            ModuleAction(id: "repeat", storageKey: "hotkey_shot_repeat", hotKeyID: 33),
        ]),
        ModuleEntry(id: "annotate", guideLetter: "i", actions: [
            ModuleAction(id: "open", storageKey: "hotkey_annotate", hotKeyID: 34,
                         defaultCombo: ModuleCombo(keyCode: 2, modifiers: controlOption)),
            annotatePassAction,
        ]),
        ModuleEntry(id: "archive", guideLetter: "z", actions: [
            ModuleAction(id: "open", storageKey: "hotkey_archive", hotKeyID: 25,
                         defaultCombo: ModuleCombo(keyCode: 3, modifiers: controlOption)),
        ]),
        ModuleEntry(id: "keyboard", guideLetter: "k", actions: [
            ModuleAction(id: "open", storageKey: "hotkey_keyboardLock", hotKeyID: 6,
                         defaultCombo: ModuleCombo(keyCode: 40, modifiers: controlOption)),
        ]),
        ModuleEntry(id: "vpn", hiddenOnFirstRun: true, guideLetter: "n", actions: []),
        ModuleEntry(id: "uninstall", guideLetter: "u", actions: [
            ModuleAction(id: "open", storageKey: "hotkey_uninstall", hotKeyID: 27,
                         defaultCombo: ModuleCombo(keyCode: 32, modifiers: controlOption)),
        ]),
        ModuleEntry(id: "system", guideLetter: "m", actions: []),
        ModuleEntry(id: "tracker", guideLetter: "r", actions: []),
        ModuleEntry(id: "todos", guideLetter: "l", actions: []),
    ]

    /// The window-manager's zones, in the order the settings grid draws them.
    /// The ⌃⌥ defaults follow Rectangle's convention, except the five letters
    /// the modules name themselves with. SPEC: docs/spec.md — hotkeys.
    public static let zoneActions: [ModuleAction] = [
        zone("leftHalf", key: 123, hotKeyID: 101),
        zone("rightHalf", key: 124, hotKeyID: 102),
        zone("topHalf", key: 126, hotKeyID: 103),
        zone("bottomHalf", key: 125, hotKeyID: 104),
        zone("maximize", key: 36, hotKeyID: 105),
        zone("center", key: 18, hotKeyID: 106),
        zone("topLeft", key: 19, hotKeyID: 107),
        zone("topRight", key: 34, hotKeyID: 108),
        zone("bottomLeft", key: 38, hotKeyID: 109),
        zone("bottomRight", key: 20, hotKeyID: 110),
        zone("leftThird", key: 21, hotKeyID: 111),
        zone("centerThird", key: 23, hotKeyID: 112),
        zone("rightThird", key: 5, hotKeyID: 113),
        zone("leftTwoThirds", key: 14, hotKeyID: 114),
        zone("rightTwoThirds", key: 22, hotKeyID: 115),
        zone("centerHalf", key: 26, hotKeyID: 116),
        zone("topThird", key: 28, hotKeyID: 117),
        zone("bottomThird", key: 37, hotKeyID: 118),
    ]

    private static func zone(_ name: String, key: UInt32, hotKeyID: UInt32) -> ModuleAction {
        ModuleAction(id: "\(ModuleAction.zonePrefix)\(name)",
                     storageKey: "hotkey_zone_\(name)",
                     hotKeyID: hotKeyID,
                     defaultCombo: ModuleCombo(keyCode: key, modifiers: controlOption))
    }

    /// The order the panel's first space is built in on a clean install; the
    /// managed spaces (the monitor, the clock, the tools) take their own
    /// modules out of it. The two markup modules sit at the BOTTOM with only
    /// the window zones under them (Anton, 2026-09-08): they are reached for
    /// mid-call and mid-write, not while the panel is being read top to bottom,
    /// and the zones are the one row that belongs lower still.
    /// SPEC: docs/spec.md — "Modules".
    public static let defaultModuleOrder =
        "timer,awake,clipboard,vpn,keyboard,ocr,convert,shot,annotate,windows,speedtest,torrent,color,archive"

    /// Modules that own settings beyond the on/off switch.
    /// SPEC: docs/spec.md — "The module page (settings window)".
    public static let modulesWithSettings: Set<String> = [
        "timer", "system", "awake", "clipboard", "color", "tracker",
        "todos", "vpn", "convert", "archive", "torrent", "windows",
        "shot", "annotate",
    ]

    public static func hasSettings(_ id: String) -> Bool {
        modulesWithSettings.contains(id)
    }

    /// The onboarding's screens, one per theme: sixteen switches on a single
    /// page said nothing about what any of them did. The view layer supplies
    /// each group's title; the order here is the order the wizard walks. "apps"
    /// is not a module until a grid exists, so it rides along as an id the
    /// catalog does not carry. SPEC: docs/spec.md — "Onboarding".
    public static let onboardingGroups: [[String]] = [
        ["timer", "tracker", "todos"],
        ["convert", "archive"],
        ["clipboard", "color", "ocr"],
        ["shot", "annotate"],
        ["system", "awake", "keyboard"],
        ["speedtest", "vpn", "torrent"],
        ["windows", "apps", "uninstall"],
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

    /// The `?m=` code the guide address takes: one letter per module the user
    /// still sees, in catalog order. SPEC: hop-website/docs/guide-code.md
    public static func guideCode(shown: Set<String>) -> String {
        modules.filter { shown.contains($0.id) }.map(\.guideLetter).joined()
    }
}
