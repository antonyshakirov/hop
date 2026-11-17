import AppKit
import SwiftUI
import HopCore
import XCTest
@testable import Hop

@MainActor
final class PatchSettingsRenderingTests: XCTestCase {
    private func buttons(_ view: NSView) -> [NSButton] {
        (view as? NSButton).map { [$0] } ?? view.subviews.flatMap(buttons)
    }

    private func host(_ model: AppModel, section: String, dark: Bool) async throws -> (NSWindow, NSView) {
        model.settingsSectionRequest = section
        let content = PanelView(standaloneSettings: true).environmentObject(model)
            .frame(width: 940, height: 720).environment(\.colorScheme, dark ? .dark : .light)
        let host = NSHostingView(rootView: content)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 940, height: 720), styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false; window.contentView = host
        window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        host.layoutSubtreeIfNeeded()
        let deadline = Date().addingTimeInterval(2)
        while model.settingsSectionRequest != nil, Date() < deadline { try await Task.sleep(nanoseconds: 10_000_000) }
        XCTAssertNil(model.settingsSectionRequest)
        host.layoutSubtreeIfNeeded()
        return (window, host)
    }

    private func save(_ host: NSView, name: String) throws {
        guard let directory = ProcessInfo.processInfo.environment["HOP_PLUGIN_RENDER_DIR"] else { return }
        let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: bitmap)
        try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
            .write(to: URL(fileURLWithPath: directory).appendingPathComponent(name + ".png"))
    }

    func testActualMonitoringSettingsOpenCoolingAndHotkeysCanBeCleared() async throws {
        let defaults = UserDefaults.standard
        let language = defaults.object(forKey: SettingsKey.appLanguage), theme = defaults.object(forKey: Theme.themeKey)
        let savedSnapshot = Snapshot.active
        Snapshot.active = false
        let clipboard = try XCTUnwrap(ModuleCatalog.module("clipboard")?.actions.first)
        let savedCombo = defaults.object(forKey: clipboard.storageKey)
        let manager = HotkeyManager.shared
        defer {
            manager.disable(clipboard)
            if let savedCombo { defaults.set(savedCombo, forKey: clipboard.storageKey) } else { defaults.removeObject(forKey: clipboard.storageKey) }
            if let language { defaults.set(language, forKey: SettingsKey.appLanguage) } else { defaults.removeObject(forKey: SettingsKey.appLanguage) }
            if let theme { defaults.set(theme, forKey: Theme.themeKey) } else { defaults.removeObject(forKey: Theme.themeKey) }
            Snapshot.active = savedSnapshot
        }
        for lang in [AppLanguage.en, .ru, .de, .fr] {
            for dark in [false, true] {
                defaults.set(lang.rawValue, forKey: SettingsKey.appLanguage)
                defaults.set(dark ? "dark" : "light", forKey: Theme.themeKey)
                let model = AppModel(preview: true)
                defer { model.soundCallMix.shutdown() }
                var opened = 0
                model.openCoolingWindow = { opened += 1 }
                let (monitorWindow, monitor) = try await host(model, section: "monitor", dark: dark)
                let link = try XCTUnwrap(buttons(monitor).first { $0.identifier?.rawValue == "hop.cooling.settings" })
                XCTAssertNotNil(link.image)
                try save(monitor, name: "monitor-settings-\(lang.rawValue)-\(dark ? "dark" : "light")")
                link.performClick(nil); XCTAssertEqual(opened, 1)
                monitorWindow.close()
                defaults.removeObject(forKey: clipboard.storageKey)
                manager.setHandler(clipboard) {}
                let (offWindow, offKeys) = try await host(model, section: "hotkeys", dark: dark)
                let disabled = try XCTUnwrap(buttons(offKeys).first { $0.identifier?.rawValue == "hop.hotkey.clear." + clipboard.storageKey })
                XCTAssertFalse(disabled.isEnabled)
                XCTAssertNil(manager.combo(for: clipboard))
                try save(offKeys, name: "hotkeys-default-off-\(lang.rawValue)-\(dark ? "dark" : "light")")
                offWindow.close()
                defaults.set("768:90", forKey: clipboard.storageKey)
                manager.setHandler(clipboard) {}
                let (keysWindow, keys) = try await host(model, section: "hotkeys", dark: dark)
                let clear = try XCTUnwrap(buttons(keys).first { $0.identifier?.rawValue == "hop.hotkey.clear." + clipboard.storageKey })
                try save(keys, name: "hotkeys-settings-\(lang.rawValue)-\(dark ? "dark" : "light")")
                clear.performClick(nil)
                XCTAssertNil(manager.combo(for: clipboard))
                keysWindow.close()
            }
        }
    }
}
