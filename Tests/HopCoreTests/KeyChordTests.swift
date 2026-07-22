import XCTest
@testable import HopCore

final class KeyChordTests: XCTestCase {
    // Modifier raw values matching NSEvent.ModifierFlags.
    private let command: UInt = 1 << 20
    private let shift: UInt = 1 << 17
    private let control: UInt = 1 << 18
    private let option: UInt = 1 << 19
    private let capsLock: UInt = 1 << 16

    // ANSI layout: ⌘V produces "v", keyCode 9. Pastes.
    func testCommandVPastes() {
        XCTAssertTrue(KeyChord.isPasteChord(keyCode: 9, modifierFlags: command))
    }

    // The reproduced bug: a Russian layout makes ⌘V arrive as a Cyrillic
    // character, but the PHYSICAL key is still keyCode 9. Matching by code, it
    // pastes — a character check ("v") silently dropped it.
    func testCommandVOnCyrillicLayoutPastes() {
        // charactersIgnoringModifiers would be a Cyrillic letter; the gate never
        // sees it — only the key code (9) and the modifiers matter.
        XCTAssertTrue(KeyChord.isPasteChord(keyCode: 9, modifierFlags: command))
    }

    // ⌘⇧V (shift-arriving paste) still counts.
    func testCommandShiftVPastes() {
        XCTAssertTrue(KeyChord.isPasteChord(keyCode: 9, modifierFlags: command | shift))
    }

    // Caps lock on must not defeat ⌘V.
    func testCapsLockedCommandVPastes() {
        XCTAssertTrue(KeyChord.isPasteChord(keyCode: 9, modifierFlags: command | capsLock))
    }

    // Plain V with no command (just typing the key, any layout) is not a paste chord.
    func testVWithoutCommandDoesNotPaste() {
        XCTAssertFalse(KeyChord.isPasteChord(keyCode: 9, modifierFlags: 0))
        XCTAssertFalse(KeyChord.isPasteChord(keyCode: 9, modifierFlags: shift))
    }

    // ⌘⌥V and ⌘⌃V are different chords — not paste.
    func testCommandWithOtherModifiersDoesNotPaste() {
        XCTAssertFalse(KeyChord.isPasteChord(keyCode: 9, modifierFlags: command | option))
        XCTAssertFalse(KeyChord.isPasteChord(keyCode: 9, modifierFlags: command | control))
    }

    // A different physical key with ⌘ (e.g. ⌘C = keyCode 8) is not a paste chord.
    func testCommandOnOtherKeyDoesNotPaste() {
        XCTAssertFalse(KeyChord.isPasteChord(keyCode: 8, modifierFlags: command))
    }
}
