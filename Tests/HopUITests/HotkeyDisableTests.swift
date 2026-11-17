import XCTest
import SwiftUI
import Carbon.HIToolbox
import HopCore
@testable import Hop

@MainActor
final class HotkeyDisableTests: XCTestCase {
    func testExplicitlyClearedClipboardKeyDoesNotFallBackToDefault() throws {
        let action = try XCTUnwrap(ModuleCatalog.modules.first { $0.id == "clipboard" }?.actions.first)
        let defaults = UserDefaults.standard
        let saved = defaults.object(forKey: action.storageKey)
        defer { if let saved { defaults.set(saved, forKey: action.storageKey) } else { defaults.removeObject(forKey: action.storageKey) } }
        defaults.set("", forKey: action.storageKey)
        let manager = HotkeyManager.shared
        XCTAssertNil(manager.combo(for: action))
        XCTAssertFalse(manager.isDefault(action))
        XCTAssertNil(HotkeyManager().combo(for: action))
        manager.reset(action)
        XCTAssertNotNil(manager.combo(for: action))
        XCTAssertTrue(manager.isDefault(action))
    }
    func testNativeClearButtonReleasesTheReservedCombination() throws {
        let action = try XCTUnwrap(ModuleCatalog.modules.first { $0.id == "clipboard" }?.actions.first)
        let defaults = UserDefaults.standard
        let saved = defaults.object(forKey: action.storageKey)
        let manager = HotkeyManager.shared
        let enabled = ModuleActivation.isOn("clipboard")
        defer {
            manager.disable(action)
            if let saved { defaults.set(saved, forKey: action.storageKey) } else { defaults.removeObject(forKey: action.storageKey) }
        }
        let combo = HotkeyManager.Combo(keyCode: UInt32(kVK_F20), modifiers: UInt32(controlKey | optionKey | shiftKey | cmdKey))
        XCTAssertTrue(manager.setCombo(combo, for: action))
        manager.setHandler(action) {}
        var held: EventHotKeyRef?
        let duplicate = RegisterEventHotKey(combo.keyCode, combo.modifiers,
            EventHotKeyID(signature: 0x48505453, id: 1), GetEventDispatcherTarget(), 0, &held)
        if let held { UnregisterEventHotKey(held) }
        XCTAssertNotEqual(duplicate, noErr)
        let host = NSHostingView(rootView: HotkeyClearButton(label: "disable shortcut", id: action.storageKey) {
            manager.disable(action)
        }.frame(width: 18, height: 18))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 60, height: 40), styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false; window.contentView = host
        defer { window.close() }
        host.layoutSubtreeIfNeeded()
        func buttons(_ view: NSView) -> [NSButton] { (view as? NSButton).map { [$0] } ?? view.subviews.flatMap(buttons) }
        let button = try XCTUnwrap(buttons(host).first { $0.identifier?.rawValue == "hop.hotkey.clear." + action.storageKey })
        XCTAssertNotNil(button.image); XCTAssertEqual(button.title, "")
        button.performClick(nil)
        XCTAssertNil(manager.combo(for: action))
        XCTAssertEqual(ModuleActivation.isOn("clipboard"), enabled)
        var available: EventHotKeyRef?
        let result = RegisterEventHotKey(combo.keyCode, combo.modifiers,
            EventHotKeyID(signature: 0x48505453, id: 2), GetEventDispatcherTarget(), 0, &available)
        if let available { UnregisterEventHotKey(available) }
        XCTAssertEqual(result, noErr)
    }

}
