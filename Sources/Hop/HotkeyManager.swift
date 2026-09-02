import AppKit
import Carbon.HIToolbox
import HopCore

/// Global hotkeys via Carbon RegisterEventHotKey.
/// Registration honestly reports whether the combo is taken by another app.
@MainActor
final class HotkeyManager: ObservableObject {
    static let shared = HotkeyManager()

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

        init(_ combo: ModuleCombo) {
            self.init(keyCode: combo.keyCode, modifiers: combo.modifiers)
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
    @Published private(set) var conflicts: Set<ModuleAction> = []

    /// The window-manager's zones, on by default (a missing key reads as ON).
    static let snapHotkeysKey = "windowsHotkeysOn"

    private var handlers: [UInt32: () -> Void] = [:]
    private var refs: [UInt32: EventHotKeyRef] = [:]
    private var claimed: [UInt32: Combo] = [:]
    private var handlerInstalled = false

    /// The combination an action answers to; nil while it has none.
    func combo(for action: ModuleAction) -> Combo? {
        if let raw = UserDefaults.standard.string(forKey: action.storageKey),
           let combo = Combo(storage: raw) {
            return combo
        }
        guard let fallback = action.defaultCombo else { return nil }
        return Combo(fallback)
    }

    @discardableResult
    func setCombo(_ combo: Combo, for action: ModuleAction) -> Bool {
        UserDefaults.standard.set(combo.storage, forKey: action.storageKey)
        guard Self.registrableActions().contains(action) else { return true }
        return register(action)
    }

    /// Whether the action does anything at all: a row offering to record a key
    /// for an action nobody answers would be a lie.
    func hasHandler(_ action: ModuleAction) -> Bool { handlers[action.hotKeyID] != nil }

    func setHandler(_ action: ModuleAction, _ handler: @escaping () -> Void) {
        installIfNeeded()
        handlers[action.hotKeyID] = handler
        refreshModuleHotkeys()
    }

    /// SPEC: docs/spec.md, "Which combination may be claimed".
    func refreshSnapHotkeys() { refreshModuleHotkeys() }

    func refreshModuleHotkeys() {
        installIfNeeded()
        let allowed = Self.registrableActions()
        for action in ModuleCatalog.allActions {
            let claimable = allowed.contains(action)
                && handlers[action.hotKeyID] != nil
                && combo(for: action) != nil
            if claimable {
                _ = register(action)
            } else {
                unregister(action)
            }
        }
    }

    private static func registrableActions() -> Set<ModuleAction> {
        Set(HotkeyActivation.registrable(
            windowZones: UserDefaults.standard.object(forKey: snapHotkeysKey) as? Bool ?? true
        ))
    }

    /// Whether the action still answers the combination it shipped with.
    func isDefault(_ action: ModuleAction) -> Bool {
        UserDefaults.standard.string(forKey: action.storageKey) == nil
    }

    /// Hand the action its shipped combination back.
    func reset(_ action: ModuleAction) {
        UserDefaults.standard.removeObject(forKey: action.storageKey)
        refreshModuleHotkeys()
    }

    /// Hand a whole group of actions their shipped combinations back.
    func reset(_ actions: [ModuleAction]) {
        for action in actions { UserDefaults.standard.removeObject(forKey: action.storageKey) }
        refreshModuleHotkeys()
    }

    private func unregister(_ action: ModuleAction) {
        claimed[action.hotKeyID] = nil
        guard let ref = refs[action.hotKeyID] else { return }
        UnregisterEventHotKey(ref)
        refs[action.hotKeyID] = nil
        conflicts.remove(action)
    }

    @discardableResult
    private func register(_ action: ModuleAction) -> Bool {
        guard let combo = combo(for: action) else { return false }
        // Re-registering an unchanged combo hands it to other apps for that instant.
        if claimed[action.hotKeyID] == combo, refs[action.hotKeyID] != nil { return true }
        if let existing = refs[action.hotKeyID] {
            UnregisterEventHotKey(existing)
            refs[action.hotKeyID] = nil
        }
        var ref: EventHotKeyRef?
        let id = EventHotKeyID(signature: OSType(0x4D4E4D4F), id: action.hotKeyID) // 'MNMO'
        let status = RegisterEventHotKey(
            combo.keyCode, combo.modifiers, id, GetEventDispatcherTarget(), 0, &ref
        )
        if status == noErr, let ref {
            refs[action.hotKeyID] = ref
            claimed[action.hotKeyID] = combo
            conflicts.remove(action)
            return true
        }
        claimed[action.hotKeyID] = nil
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
