import AppKit
import Carbon.HIToolbox

/// Global hotkeys via Carbon RegisterEventHotKey.
/// Registration honestly reports whether the combo is taken by another app.
@MainActor
final class HotkeyManager: ObservableObject {
    static let shared = HotkeyManager()

    enum Action: String, CaseIterable, Identifiable {
        case panel, timer, awake

        var id: String { rawValue }
        var storageKey: String { "hotkey_\(rawValue)" }
        var hotKeyID: UInt32 {
            switch self {
            case .panel: return 1
            case .timer: return 2
            case .awake: return 3
            }
        }

        /// Unconventional defaults: ⌃⌥ combos are almost always free.
        var defaultCombo: Combo {
            switch self {
            case .panel: return Combo(keyCode: UInt32(kVK_ANSI_M), modifiers: UInt32(controlKey | optionKey))
            case .timer: return Combo(keyCode: UInt32(kVK_ANSI_T), modifiers: UInt32(controlKey | optionKey))
            case .awake: return Combo(keyCode: UInt32(kVK_ANSI_W), modifiers: UInt32(controlKey | optionKey))
            }
        }
    }

    struct Combo: Equatable {
        var keyCode: UInt32
        var modifiers: UInt32 // Carbon flags

        var storage: String { "\(modifiers):\(keyCode)" }

        init(keyCode: UInt32, modifiers: UInt32) {
            self.keyCode = keyCode
            self.modifiers = modifiers
        }

        init?(storage: String) {
            let parts = storage.split(separator: ":")
            guard parts.count == 2,
                  let mods = UInt32(parts[0]), let code = UInt32(parts[1])
            else { return nil }
            self.init(keyCode: code, modifiers: mods)
        }

        init?(event: NSEvent) {
            var carbon: UInt32 = 0
            if event.modifierFlags.contains(.control) { carbon |= UInt32(controlKey) }
            if event.modifierFlags.contains(.option) { carbon |= UInt32(optionKey) }
            if event.modifierFlags.contains(.shift) { carbon |= UInt32(shiftKey) }
            if event.modifierFlags.contains(.command) { carbon |= UInt32(cmdKey) }
            guard carbon != 0 else { return nil } // no modifiers means not global
            self.init(keyCode: UInt32(event.keyCode), modifiers: carbon)
        }

        var display: String {
            var parts: [String] = []
            if modifiers & UInt32(controlKey) != 0 { parts.append("⌃") }
            if modifiers & UInt32(optionKey) != 0 { parts.append("⌥") }
            if modifiers & UInt32(shiftKey) != 0 { parts.append("⇧") }
            if modifiers & UInt32(cmdKey) != 0 { parts.append("⌘") }
            parts.append(Self.keyName(keyCode))
            return parts.joined(separator: " ")
        }

        private static let names: [UInt32: String] = [
            UInt32(kVK_ANSI_A): "A", UInt32(kVK_ANSI_B): "B", UInt32(kVK_ANSI_C): "C",
            UInt32(kVK_ANSI_D): "D", UInt32(kVK_ANSI_E): "E", UInt32(kVK_ANSI_F): "F",
            UInt32(kVK_ANSI_G): "G", UInt32(kVK_ANSI_H): "H", UInt32(kVK_ANSI_I): "I",
            UInt32(kVK_ANSI_J): "J", UInt32(kVK_ANSI_K): "K", UInt32(kVK_ANSI_L): "L",
            UInt32(kVK_ANSI_M): "M", UInt32(kVK_ANSI_N): "N", UInt32(kVK_ANSI_O): "O",
            UInt32(kVK_ANSI_P): "P", UInt32(kVK_ANSI_Q): "Q", UInt32(kVK_ANSI_R): "R",
            UInt32(kVK_ANSI_S): "S", UInt32(kVK_ANSI_T): "T", UInt32(kVK_ANSI_U): "U",
            UInt32(kVK_ANSI_V): "V", UInt32(kVK_ANSI_W): "W", UInt32(kVK_ANSI_X): "X",
            UInt32(kVK_ANSI_Y): "Y", UInt32(kVK_ANSI_Z): "Z",
            UInt32(kVK_ANSI_0): "0", UInt32(kVK_ANSI_1): "1", UInt32(kVK_ANSI_2): "2",
            UInt32(kVK_ANSI_3): "3", UInt32(kVK_ANSI_4): "4", UInt32(kVK_ANSI_5): "5",
            UInt32(kVK_ANSI_6): "6", UInt32(kVK_ANSI_7): "7", UInt32(kVK_ANSI_8): "8",
            UInt32(kVK_ANSI_9): "9",
            UInt32(kVK_Space): "Space", UInt32(kVK_Return): "↩", UInt32(kVK_Tab): "⇥",
            UInt32(kVK_UpArrow): "↑", UInt32(kVK_DownArrow): "↓",
            UInt32(kVK_LeftArrow): "←", UInt32(kVK_RightArrow): "→",
        ]

        static func keyName(_ code: UInt32) -> String {
            names[code] ?? "#\(code)"
        }
    }

    /// Combos that failed to register (taken by the system/other apps).
    @Published private(set) var conflicts: Set<Action> = []

    // MARK: - Window zone hotkeys

    /// Fixed ⌃⌥ scheme in the Rectangle spirit; enabled by a toggle
    /// in the windows settings, OFF by default. IDs start at 101
    /// to avoid overlapping with Action.
    static let snapHotkeysKey = "windowsHotkeysOn"

    static let snapScheme: [(position: WindowSnapController.Position, keyCode: Int, id: UInt32)] = [
        (.leftHalf, kVK_LeftArrow, 101),
        (.rightHalf, kVK_RightArrow, 102),
        (.topHalf, kVK_UpArrow, 103),
        (.bottomHalf, kVK_DownArrow, 104),
        (.maximize, kVK_Return, 105),
        (.center, kVK_ANSI_C, 106),
        (.topLeft, kVK_ANSI_U, 107),
        (.topRight, kVK_ANSI_I, 108),
        (.bottomLeft, kVK_ANSI_J, 109),
        (.bottomRight, kVK_ANSI_K, 110),
    ]

    private var snapRefs: [UInt32: EventHotKeyRef] = [:]

    /// Re-register the zones according to the current toggle state.
    func refreshSnapHotkeys() {
        installIfNeeded()
        for (_, ref) in snapRefs { UnregisterEventHotKey(ref) }
        snapRefs.removeAll()
        guard UserDefaults.standard.bool(forKey: Self.snapHotkeysKey) else { return }
        for entry in Self.snapScheme {
            handlers[entry.id] = { WindowSnapController.shared.apply(entry.position) }
            var ref: EventHotKeyRef?
            let hotKeyID = EventHotKeyID(signature: OSType(0x4D4E4D4F), id: entry.id)
            let status = RegisterEventHotKey(
                UInt32(entry.keyCode), UInt32(controlKey | optionKey),
                hotKeyID, GetEventDispatcherTarget(), 0, &ref
            )
            if status == noErr, let ref {
                snapRefs[entry.id] = ref
            }
        }
    }

    private var handlers: [UInt32: () -> Void] = [:]
    private var refs: [UInt32: EventHotKeyRef] = [:]
    private var handlerInstalled = false

    func combo(for action: Action) -> Combo {
        if let raw = UserDefaults.standard.string(forKey: action.storageKey),
           let combo = Combo(storage: raw) {
            return combo
        }
        return action.defaultCombo
    }

    @discardableResult
    func setCombo(_ combo: Combo, for action: Action) -> Bool {
        UserDefaults.standard.set(combo.storage, forKey: action.storageKey)
        return register(action)
    }

    func setHandler(_ action: Action, _ handler: @escaping () -> Void) {
        installIfNeeded()
        handlers[action.hotKeyID] = handler
        _ = register(action)
    }

    @discardableResult
    private func register(_ action: Action) -> Bool {
        if let existing = refs[action.hotKeyID] {
            UnregisterEventHotKey(existing)
            refs[action.hotKeyID] = nil
        }
        let combo = combo(for: action)
        var ref: EventHotKeyRef?
        let id = EventHotKeyID(signature: OSType(0x4D4E4D4F), id: action.hotKeyID) // 'MNMO'
        let status = RegisterEventHotKey(
            combo.keyCode, combo.modifiers, id, GetEventDispatcherTarget(), 0, &ref
        )
        if status == noErr, let ref {
            refs[action.hotKeyID] = ref
            conflicts.remove(action)
            return true
        }
        conflicts.insert(action) // taken by another application
        return false
    }

    private func installIfNeeded() {
        guard !handlerInstalled else { return }
        handlerInstalled = true
        var spec = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        InstallEventHandler(GetEventDispatcherTarget(), { _, event, userData in
            guard let event, let userData else { return noErr }
            var hotKeyID = EventHotKeyID()
            GetEventParameter(
                event, EventParamName(kEventParamDirectObject),
                EventParamType(typeEventHotKeyID), nil,
                MemoryLayout<EventHotKeyID>.size, nil, &hotKeyID
            )
            let manager = Unmanaged<HotkeyManager>.fromOpaque(userData).takeUnretainedValue()
            MainActor.assumeIsolated {
                manager.handlers[hotKeyID.id]?()
            }
            return noErr
        }, 1, &spec, Unmanaged.passUnretained(self).toOpaque(), nil)
    }
}
