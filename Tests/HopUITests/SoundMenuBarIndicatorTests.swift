import AppKit
import HopCore
import XCTest
@testable import Hop

@MainActor
final class SoundMenuBarIndicatorTests: XCTestCase {
    private final class Session: SoundMixingSession {
        func outputs(_ channels: [SoundMixerChannel]) {}
        func configure(_ channel: SoundMixerChannel) {}
        func stop() {}
    }

    func testDefaultOutputMixerUpdatesItsStatusWithoutCustomGain() throws {
        let defaults = UserDefaults.standard
        let keys = [SettingsKey.menuBarIconOnly, SettingsKey.soundMenuBarMark, SettingsKey.panelTabs]
        let saved = keys.map { defaults.object(forKey: $0) }
        let suite = "HopTests.MixerIcon." + UUID().uuidString
        let storage = UserDefaults(suiteName: suite)!
        defer {
            storage.removePersistentDomain(forName: suite)
            for (key, value) in zip(keys, saved) {
                if let value { defaults.set(value, forKey: key) }
                else { defaults.removeObject(forKey: key) }
            }
        }
        defaults.set(false, forKey: SettingsKey.menuBarIconOnly)
        defaults.set(true, forKey: SettingsKey.soundMenuBarMark)
        defaults.removeObject(forKey: SettingsKey.panelTabs)
        let mixer = SoundMixerController(defaults: storage, makeSession: { _ in Session() },
                                         discover: { [] }, outputs: { [] })
        let model = AppModel(preview: true, mixerController: mixer, soundEnabled: { true })
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        defer { mixer.stop(); NSStatusBar.system.removeStatusItem(item) }
        let button = try XCTUnwrap(item.button)
        let controller = StatusItemController(model: model, statusItem: item)
        controller.refreshButton()
        let off = try XCTUnwrap(button.image)
        mixer.start()
        XCTAssertFalse(mixer.hasCustomApplicationAudio)
        controller.refreshButton()
        XCTAssertFalse(button.image === off, "A running mixer must show its speaker even at default settings")
        mixer.stop()
        controller.refreshButton()
        XCTAssertEqual(button.image?.tiffRepresentation, off.tiffRepresentation)
    }

    func testModuleMarkCanBeHiddenWithoutChangingAudioOrGlobalPreferences() {
        let name = "HopTests.SoundMenuBarIndicator"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        defer { defaults.removePersistentDomain(forName: name) }
        XCTAssertTrue(SoundMenuBarIndicator.isVisible(running: true, moduleActive: true, defaults: defaults))
        defaults.set(false, forKey: "soundMenuBarMark")
        defaults.set(true, forKey: "soundMixerEnabled")
        XCTAssertFalse(SoundMenuBarIndicator.isVisible(running: true, moduleActive: true, defaults: defaults))
        XCTAssertTrue(defaults.bool(forKey: "soundMixerEnabled"))
        XCTAssertNil(defaults.object(forKey: "menuBarIconOnly"))
        defaults.set(true, forKey: "soundMenuBarMark")
        XCTAssertTrue(SoundMenuBarIndicator.isVisible(running: true, moduleActive: true, defaults: defaults))
    }

    func testInputMarkUsesTheSameStatusButtonAndCanBeHiddenWithoutStoppingMixer() throws {
        let defaults = UserDefaults.standard
        let keys = [SettingsKey.menuBarIconOnly, SettingsKey.soundMenuBarMark, SettingsKey.panelTabs]
        let saved = keys.map { defaults.object(forKey: $0) }
        let snapshot = Snapshot.active
        Snapshot.active = true
        defer {
            Snapshot.active = snapshot
            for (key, value) in zip(keys, saved) {
                if let value { defaults.set(value, forKey: key) }
                else { defaults.removeObject(forKey: key) }
            }
        }
        defaults.set(false, forKey: SettingsKey.menuBarIconOnly)
        defaults.set(true, forKey: SettingsKey.soundMenuBarMark)
        defaults.removeObject(forKey: SettingsKey.panelTabs)
        let model = AppModel(preview: true)
        model.soundMixer.suspend()
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        defer { model.soundCallMix.shutdown(); NSStatusBar.system.removeStatusItem(item) }
        let button = try XCTUnwrap(item.button)
        let controller = StatusItemController(model: model, statusItem: item)
        controller.refreshButton()
        let off = try XCTUnwrap(button.image)
        model.soundCallMix.stageDemo(model.soundMixer.apps)
        controller.refreshButton()
        XCTAssertFalse(button.image === off)
        defaults.set(false, forKey: SettingsKey.soundMenuBarMark)
        controller.refreshButton()
        XCTAssertEqual(button.image?.tiffRepresentation, off.tiffRepresentation)
        XCTAssertTrue(model.soundCallMix.running)
        defaults.set(true, forKey: SettingsKey.soundMenuBarMark)
        defaults.set(true, forKey: SettingsKey.menuBarIconOnly)
        controller.refreshButton()
        XCTAssertTrue(button.image === MenuBarIcon.plainDialTemplate)
        XCTAssertTrue(model.soundCallMix.running)
        defaults.set(false, forKey: SettingsKey.menuBarIconOnly)
        controller.refreshButton()
        XCTAssertNotEqual(button.image?.tiffRepresentation, off.tiffRepresentation)
        XCTAssertTrue(model.soundCallMix.running)
    }

    func testStoppedOrInactiveMixerDoesNotShowAMark() {
        XCTAssertFalse(SoundMenuBarIndicator.isVisible(running: false, moduleActive: true))
        XCTAssertTrue(SoundMenuBarIndicator.isVisible(running: true, moduleActive: true))
        XCTAssertFalse(SoundMenuBarIndicator.isVisible(running: true, moduleActive: false))
    }

    func testMixerGlyphsStayInsideOneFixedImageAndDoNotMoveTheAnchor() {
        let canvas = NSRect(origin: .zero, size: MenuBarIcon.canvasSize)
        XCTAssertTrue(canvas.contains(MenuBarIcon.microphoneFrame))
        XCTAssertTrue(canvas.contains(MenuBarIcon.speakerFrame))
        XCTAssertEqual(MenuBarIcon.microphoneFrame.midY, canvas.midY)
        XCTAssertEqual(MenuBarIcon.speakerFrame.midY, canvas.midY)
        for input in [true, false] {
            for output in [true, false] {
                XCTAssertEqual(MenuBarIcon.compose(IconComposition(outputMix: output, inputMix: input)).size, canvas.size)
            }
        }
        XCTAssertEqual(MenuBarIcon.dialTemplate.size, canvas.size)
        XCTAssertEqual(MenuBarIcon.plainDialTemplate.size, canvas.size)
    }

    func testAudioInkDoesNotOverlapOtherMarksOrReplacementSymbols() throws {
        let audio = NSImage(size: MenuBarIcon.canvasSize)
        audio.lockFocus()
        MenuBarIcon.drawAudioIndicators(IconComposition(outputMix: true, inputMix: true), glyph: .white)
        audio.unlockFocus()
        let mask = try XCTUnwrap(NSBitmapImageRep(data: XCTUnwrap(audio.tiffRepresentation)))
        for dark in [true, false] {
            for colored in [true, false] {
                for dev in [true, false] {
                    for base in [MenuBarIcon.Base.dial, .symbol("keyboard.fill"), .symbol("bell.fill")] {
                        let existing = MenuBarIcon.compose(IconComposition(alert: true, reminder: true,
                            vpn: .up, noSleep: true, lid: true, engineTime: true, taskTime: true,
                            torrent: .both, colored: colored), base: base, dark: dark, markDev: dev)
                        let bitmap = try XCTUnwrap(NSBitmapImageRep(data: XCTUnwrap(existing.tiffRepresentation)))
                        XCTAssertEqual(bitmap.pixelsWide, mask.pixelsWide)
                        var overlap = 0
                        for y in 0..<bitmap.pixelsHigh { for x in 0..<bitmap.pixelsWide {
                            if (mask.colorAt(x: x, y: y)?.alphaComponent ?? 0) > 0.5,
                               (bitmap.colorAt(x: x, y: y)?.alphaComponent ?? 0) > 0.5 { overlap += 1 }
                        }}
                        XCTAssertEqual(overlap, 0, "\(base), Dev=\(dev), dark=\(dark), colored=\(colored)")
                    }
                }
            }
        }
    }
}
