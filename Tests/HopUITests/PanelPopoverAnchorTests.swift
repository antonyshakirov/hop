import AppKit
import XCTest
@testable import Hop

@MainActor
final class PanelPopoverAnchorTests: XCTestCase {
    private static var retainedFixtures: [AnyObject] = []

    func testMixerWidthChangesKeepTheOpenPopoverFixedAndReopenUsesTheNewPosition() throws {
        _ = NSApplication.shared
        let screen = try XCTUnwrap(NSScreen.screens.first)
        let openingRect = NSRect(x: screen.visibleFrame.midX, y: screen.visibleFrame.maxY,
                                 width: 22, height: 17)
        let statusWindow = NSWindow(contentRect: openingRect, styleMask: .borderless,
                                    backing: .buffered, defer: false)
        statusWindow.isReleasedWhenClosed = false
        let content = NSViewController()
        content.view = NSView(frame: NSRect(x: 0, y: 0, width: 368, height: 240))
        let popover = NSPopover()
        popover.animates = false
        popover.behavior = .transient
        popover.contentViewController = content
        popover.contentSize = content.view.frame.size
        var anchor = PanelPopoverAnchor(screenRect: statusWindow.frame)
        defer {
            popover.close(); anchor.close(); statusWindow.orderOut(nil)
            Self.retainedFixtures.append(contentsOf: [statusWindow, content, popover])
        }
        anchor.show(popover)
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        let openingFrame = try XCTUnwrap(content.view.window?.frame)
        XCTAssertTrue(popover.isShown)
        for width: CGFloat in [30, 41, 33, 22, 41] {
            statusWindow.setFrame(NSRect(x: openingRect.minX - width + 22,
                y: openingRect.minY, width: width, height: 17), display: false)
            anchor.realign(popover)
            RunLoop.main.run(until: Date().addingTimeInterval(0.02))
            let frame = try XCTUnwrap(content.view.window?.frame)
            XCTAssertEqual(frame.minX, openingFrame.minX, accuracy: 0.5)
            XCTAssertEqual(frame.maxY, openingFrame.maxY, accuracy: 0.5)
        }
        popover.close(); anchor.close()
        let nextRect = openingRect.offsetBy(dx: -100, dy: 0)
        anchor = PanelPopoverAnchor(screenRect: nextRect)
        anchor.show(popover)
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        let reopenedFrame = try XCTUnwrap(content.view.window?.frame)
        XCTAssertEqual(reopenedFrame.minX, openingFrame.minX - 100, accuracy: 0.5)
        XCTAssertEqual(reopenedFrame.maxY, openingFrame.maxY, accuracy: 0.5)
    }

    func testStatusControllerKeepsPanelFixedWhileMixerIndicatorsChange() throws {
        let snapshot = Snapshot.active
        Snapshot.active = true
        let defaults = UserDefaults.standard
        let keys = [SettingsKey.menuBarIconOnly, SettingsKey.soundMenuBarMark, SettingsKey.panelTabs]
        let saved = keys.map { defaults.object(forKey: $0) }
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
        let controller = StatusItemController(model: model, statusItem: item)
        let existing = Set(NSApp.windows.map(\.windowNumber))
        controller.togglePanel()
        RunLoop.main.run(until: Date().addingTimeInterval(0.1))
        let panel = try XCTUnwrap(NSApp.windows.first {
            !existing.contains($0.windowNumber) && $0.isVisible && $0.frame.height > 200
        })
        defer {
            controller.togglePanel()
            RunLoop.main.run(until: Date().addingTimeInterval(0.05))
            model.soundCallMix.shutdown()
            NSStatusBar.system.removeStatusItem(item)
            Self.retainedFixtures.append(controller)
        }
        let openingFrame = panel.frame
        for enabled in [true, false, true, false] {
            if enabled { model.soundCallMix.stageDemo(model.soundMixer.apps) }
            else { model.soundCallMix.stop() }
            controller.refreshButton()
            RunLoop.main.run(until: Date().addingTimeInterval(0.05))
            XCTAssertEqual(item.button?.image?.size.width, enabled ? 30 : 22)
            XCTAssertTrue(panel.isVisible)
            XCTAssertEqual(panel.frame.minX, openingFrame.minX, accuracy: 0.5)
            XCTAssertEqual(panel.frame.maxY, openingFrame.maxY, accuracy: 0.5)
        }
    }
}
