import Foundation

/// Held modifier keys, left and right sides as separate bits.
/// Tests: Tests/HopCoreTests/HoldChordTests.swift
public struct HoldModifiers: OptionSet, Hashable, Sendable {
    public let rawValue: UInt16

    public init(rawValue: UInt16) {
        self.rawValue = rawValue
    }

    public static let fn = HoldModifiers(rawValue: 1 << 0)
    public static let leftControl = HoldModifiers(rawValue: 1 << 1)
    public static let rightControl = HoldModifiers(rawValue: 1 << 2)
    public static let leftOption = HoldModifiers(rawValue: 1 << 3)
    public static let rightOption = HoldModifiers(rawValue: 1 << 4)
    public static let leftShift = HoldModifiers(rawValue: 1 << 5)
    public static let rightShift = HoldModifiers(rawValue: 1 << 6)
    public static let leftCommand = HoldModifiers(rawValue: 1 << 7)
    public static let rightCommand = HoldModifiers(rawValue: 1 << 8)

    private static let byKeyCode: [(keyCode: UInt16, flag: HoldModifiers)] = [
        (63, .fn),
        (59, .leftControl), (62, .rightControl),
        (58, .leftOption), (61, .rightOption),
        (56, .leftShift), (60, .rightShift),
        (55, .leftCommand), (54, .rightCommand),
    ]

    /// 63 fn, 59/62 control, 58/61 option, 56/60 shift, 55/54 command; nil otherwise.
    public static func of(keyCode: UInt16) -> HoldModifiers? {
        byKeyCode.first { $0.keyCode == keyCode }?.flag
    }

    /// Modifier keycodes above plus 179 (Globe): keys that are never "another key".
    public static func isModifierKey(_ keyCode: UInt16) -> Bool {
        keyCode == 179 || of(keyCode: keyCode) != nil
    }

    private static let leftControlBit: UInt64 = 0x1
    private static let rightControlBit: UInt64 = 0x2000
    private static let leftOptionBit: UInt64 = 0x20
    private static let rightOptionBit: UInt64 = 0x40
    private static let leftShiftBit: UInt64 = 0x2
    private static let rightShiftBit: UInt64 = 0x4
    private static let leftCommandBit: UInt64 = 0x8
    private static let rightCommandBit: UInt64 = 0x10
    private static let fnBit: UInt64 = 0x800000

    /// The held set after one flagsChanged event. Fn changes only when keyCode == 63
    /// (on iff flags & 0x800000); otherwise fn is carried over from `previous`.
    /// Every other side comes from the device-dependent bits of `flags`.
    public static func next(after previous: HoldModifiers, keyCode: UInt16, flags: UInt64) -> HoldModifiers {
        var result: HoldModifiers = []
        if keyCode == 63 {
            if flags & fnBit != 0 { result.insert(.fn) }
        } else if previous.contains(.fn) {
            result.insert(.fn)
        }
        if flags & leftControlBit != 0 { result.insert(.leftControl) }
        if flags & rightControlBit != 0 { result.insert(.rightControl) }
        if flags & leftOptionBit != 0 { result.insert(.leftOption) }
        if flags & rightOptionBit != 0 { result.insert(.rightOption) }
        if flags & leftShiftBit != 0 { result.insert(.leftShift) }
        if flags & rightShiftBit != 0 { result.insert(.rightShift) }
        if flags & leftCommandBit != 0 { result.insert(.leftCommand) }
        if flags & rightCommandBit != 0 { result.insert(.rightCommand) }
        return result
    }

    public var count: Int {
        rawValue.nonzeroBitCount
    }
}

/// A hold-to-draw chord: modifiers alone, or modifiers with one ordinary key.
/// Tests: Tests/HopCoreTests/HoldChordTests.swift
public struct HoldChord: Equatable, Sendable {
    public var modifiers: HoldModifiers
    public var keyCode: UInt16?

    public init(modifiers: HoldModifiers, keyCode: UInt16? = nil) {
        self.modifiers = modifiers
        self.keyCode = keyCode
    }

    public static let standard = HoldChord(modifiers: [.fn, .leftControl])

    private static let namedOrder: [(flag: HoldModifiers, name: String, symbol: String)] = [
        (.fn, "fn", "fn"),
        (.leftControl, "leftControl", "⌃"), (.rightControl, "rightControl", "R⌃"),
        (.leftOption, "leftOption", "⌥"), (.rightOption, "rightOption", "R⌥"),
        (.leftShift, "leftShift", "⇧"), (.rightShift, "rightShift", "R⇧"),
        (.leftCommand, "leftCommand", "⌘"), (.rightCommand, "rightCommand", "R⌘"),
    ]

    /// Modifiers only: at least two keys (fn counts). With a key: at least one modifier, and the key is not a modifier key.
    public var isValid: Bool {
        if let keyCode {
            return !modifiers.isEmpty && !HoldModifiers.isModifierKey(keyCode)
        }
        return modifiers.count >= 2
    }

    /// e.g. "fn+leftOption" or "leftCommand+leftShift:40". Order: fn, control, option, shift, command; left before right.
    public var storage: String {
        var text = Self.namedOrder
            .filter { modifiers.contains($0.flag) }
            .map(\.name)
            .joined(separator: "+")
        if let keyCode {
            text += ":\(keyCode)"
        }
        return text
    }

    public init?(storage: String) {
        let sides = storage.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
        guard sides.count <= 2 else { return nil }

        var parsedKeyCode: UInt16?
        if sides.count == 2 {
            guard let code = UInt16(sides[1]) else { return nil }
            parsedKeyCode = code
        }

        var parsedModifiers: HoldModifiers = []
        let modifiersPart = sides[0]
        if !modifiersPart.isEmpty {
            for name in modifiersPart.split(separator: "+") {
                guard let match = Self.namedOrder.first(where: { $0.name == name }),
                      !parsedModifiers.contains(match.flag) else { return nil }
                parsedModifiers.insert(match.flag)
            }
        }

        self.modifiers = parsedModifiers
        self.keyCode = parsedKeyCode
        guard isValid else { return nil }
    }

    /// Symbols fn ⌃ ⌥ ⇧ ⌘ in that order, space-separated; right side prefixed "R" ("R⌥"); key name last.
    public func display(keyName: (UInt16) -> String) -> String {
        var parts = Self.namedOrder
            .filter { modifiers.contains($0.flag) }
            .map(\.symbol)
        if let keyCode {
            parts.append(keyName(keyCode))
        }
        return parts.joined(separator: " ")
    }

    /// cmdKey 0x100, shiftKey 0x200, optionKey 0x800, controlKey 0x1000 — only when the chord has a key and no fn; nil otherwise.
    public var carbonModifiers: UInt32? {
        guard keyCode != nil, !modifiers.contains(.fn) else { return nil }
        var result: UInt32 = 0
        if modifiers.contains(.leftCommand) || modifiers.contains(.rightCommand) { result |= 0x100 }
        if modifiers.contains(.leftShift) || modifiers.contains(.rightShift) { result |= 0x200 }
        if modifiers.contains(.leftOption) || modifiers.contains(.rightOption) { result |= 0x800 }
        if modifiers.contains(.leftControl) || modifiers.contains(.rightControl) { result |= 0x1000 }
        return result
    }
}
