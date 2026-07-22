/// Layout-independent keyboard-chord matching by PHYSICAL key code.
///
/// macOS reports `NSEvent.charactersIgnoringModifiers` in the ACTIVE keyboard
/// layout, so ⌘V pressed on a Russian layout arrives as a Cyrillic character,
/// not "v" — every character-based `== "v"` check then silently drops the paste
/// even though activation and key-window assignment are perfectly fine. Matching the
/// hardware key code (kVK_ANSI_V = 9) instead is layout-independent: the same
/// physical key is 9 on every layout, whatever character it produces.
///
/// The gate is pure (no AppKit) so it is testable in HopCore; callers pass the
/// raw `NSEvent.keyCode` and `NSEvent.modifierFlags.rawValue`.
public enum KeyChord {
    /// kVK_ANSI_V — the physical "V" key, whatever character the layout maps it to.
    public static let vKeyCode: UInt16 = 9

    // Device-independent modifier bits, mirroring NSEvent.ModifierFlags raw
    // values, so the check needs no AppKit import.
    static let commandBit: UInt = 1 << 20 // .command
    static let controlBit: UInt = 1 << 18 // .control
    static let optionBit: UInt = 1 << 19  // .option

    /// True for a paste chord: the physical V key with ⌘ held, ⇧ allowed
    /// (a shifted ⌘⇧V still pastes), and ⌃/⌥ absent (⌘⌥V is a different chord).
    public static func isPasteChord(keyCode: UInt16, modifierFlags: UInt) -> Bool {
        keyCode == vKeyCode && hasCommandOnly(modifierFlags)
    }

    /// ⌘ present, ⌃ and ⌥ absent. ⇧ and stateful bits (caps lock, fn) are
    /// ignored, so ⌘⇧V and a caps-locked ⌘V both still count.
    static func hasCommandOnly(_ modifierFlags: UInt) -> Bool {
        modifierFlags & commandBit != 0
            && modifierFlags & controlBit == 0
            && modifierFlags & optionBit == 0
    }
}
