import XCTest
import HopCore
import AppKit
import SwiftUI
@testable import Hop

@MainActor
final class MediaModuleTests: XCTestCase {
    func testExistingLayoutGainsAnIndependentOptInModuleOnlyOnce() throws {
        let defaults = UserDefaults.standard
        let keys = [SettingsKey.panelTabs, SettingsKey.moduleVisibilityMigrated,
                    SettingsKey.canonicalLayoutSeeded, SettingsKey.optInModulesSeeded170,
                    SettingsKey.mediaModuleSeeded, "moduleOrder"]
        let saved = Dictionary(uniqueKeysWithValues: keys.map { ($0, defaults.object(forKey: $0)) })
        defer {
            for (key, value) in saved {
                if let value { defaults.set(value, forKey: key) }
                else { defaults.removeObject(forKey: key) }
            }
        }
        let first = PanelTab(icon: "house", moduleKeys: ["convert"])
        let second = PanelTab(icon: "photo", moduleKeys: ["archive"])
        defaults.set(PanelTabsModel(tabs: [first, second]).encoded(), forKey: SettingsKey.panelTabs)
        defaults.set(true, forKey: SettingsKey.moduleVisibilityMigrated)
        defaults.set(true, forKey: SettingsKey.canonicalLayoutSeeded)
        defaults.set(true, forKey: SettingsKey.optInModulesSeeded170)
        defaults.removeObject(forKey: SettingsKey.mediaModuleSeeded)
        var tabs = PanelView.storedTabsModel()
        XCTAssertTrue(tabs.isHidden("media"))
        XCTAssertFalse(tabs.isHidden("convert"))
        XCTAssertEqual(tabs.tabs.map(\.id), [first.id, second.id])
        tabs.move(module: "media", toTab: second.id)
        tabs.setHidden("media", hidden: false)
        defaults.set(tabs.encoded(), forKey: SettingsKey.panelTabs)
        let reloaded = PanelView.storedTabsModel()
        XCTAssertFalse(reloaded.isHidden("media"))
        XCTAssertEqual(reloaded.tabID(containing: "media"), second.id)
        XCTAssertEqual(reloaded.tabID(containing: "convert"), first.id)
        XCTAssertEqual(reloaded.tabs.flatMap(\.moduleKeys).filter { $0 == "media" }.count, 1)
    }

    func testMediaHasItsOwnSettingsAndHandbookInEveryLanguage() {
        XCTAssertEqual(ModulePresentation.titleKey("media"), .mediaTitle)
        XCTAssertEqual(ModulePresentation.purposeKey("media"), .mediaPurpose)
        XCTAssertFalse(ModulePresentation.howKeys("media").isEmpty)
        for language in AppLanguage.allCases {
            for key in [L10nKey.mediaPurpose, .mediaOpen, .mediaOff] {
                XCTAssertFalse(L10n.t(key, language).isEmpty)
            }
        }
    }
    func testMediaToolsKeepSeparateQueuesSettingsAndProgress() {
        let media = MediaWorkspaces()
        let background = media.controller(for: .background)
        let upscale = media.controller(for: .upscale)
        XCTAssertFalse(background === upscale)
        XCTAssertEqual(background.operation, .background)
        XCTAssertEqual(upscale.operation, .upscale)
        let file = URL(fileURLWithPath: "/test.png")
        background.items = [.init(url: file, video: false, size: .init(width: 20, height: 10), duration: 0)]
        upscale.items = [.init(url: file, video: false, size: .init(width: 20, height: 10), duration: 0)]
        upscale.items[0].resolution = .fourK
        background.clear()
        XCTAssertTrue(background.items.isEmpty)
        XCTAssertEqual(upscale.items.count, 1)
        XCTAssertEqual(upscale.items[0].resolution, .fourK)
        upscale.busy = true
        XCTAssertTrue(media.locked)
        XCTAssertFalse(background.locked)
        upscale.busy = false
        XCTAssertFalse(media.locked)
    }

    func testMixedSelectionUsesOnlyCompatibleSizesAndLeavesOtherRowsAlone() {
        let controller = MediaController(operation: .upscale)
        let photo = MediaController.Item(url: URL(fileURLWithPath: "/photo.png"), video: false,
                                        size: .init(width: 600, height: 400), duration: 0)
        let video = MediaController.Item(url: URL(fileURLWithPath: "/video.mov"), video: true,
                                        size: .init(width: 3840, height: 2160), duration: 1)
        controller.items = [photo, video]
        XCTAssertEqual(controller.commonResolutions, [.double, .eightK])
        controller.toggleSelection(photo.id)
        XCTAssertTrue(controller.commonResolutions.contains(.quadruple))
        controller.applyResolution(.quadruple)
        XCTAssertEqual(controller.items[0].resolution, .quadruple)
        XCTAssertEqual(controller.items[1].resolution, .double)
        controller.toggleSelection(video.id)
        XCTAssertFalse(controller.commonResolutions.contains(.quadruple))
        controller.applyResolution(.quadruple)
        XCTAssertEqual(controller.items[1].resolution, .double)
        controller.selectAllFiles()
        controller.applyResolution(.eightK)
        XCTAssertEqual(controller.items.map(\.resolution), [.eightK, .eightK])
        controller.busy = true
        controller.toggleSelection(photo.id)
        controller.applyResolution(.double)
        XCTAssertTrue(controller.selection.isEmpty)
        XCTAssertEqual(controller.items.map(\.resolution), [.eightK, .eightK])
        controller.busy = false
        controller.clear()
        XCTAssertTrue(controller.selection.isEmpty)
    }

    func testMediaContentHeightGrowsAndShrinksIndependently() {
        let model = AppModel(preview: true)
        var fixtures: [(NSWindow, NSHostingController<AnyView>)] = []
        for operation in MediaOperation.allCases {
            let host = NSHostingController(rootView: AnyView(
                MediaWindowView(controller: model.media.controller(for: operation)).environmentObject(model)
            ))
            host.sizingOptions = []
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 700, height: 700),
                                  styleMask: [.titled], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.contentViewController = host
            fixtures.append((window, host))
        }
        func layout() {
            for (_, host) in fixtures { host.view.layoutSubtreeIfNeeded() }
            RunLoop.main.run(until: Date().addingTimeInterval(0.1))
        }
        layout()
        let empty = model.mediaContentHeights
        for operation in MediaOperation.allCases {
            let height = empty[operation] ?? 0
            XCTAssertGreaterThan(height, 250, "A full-height drop plate and controls must fit")
            XCTAssertLessThan(height, 380, "An empty tool should not leave a large blank area")
        }
        for operation in MediaOperation.allCases {
            let controller = model.media.controller(for: operation)
            let other: MediaOperation = operation == .background ? .upscale : .background
            let item = MediaController.Item(url: URL(fileURLWithPath: "/test.png"), video: false,
                                            size: .init(width: 600, height: 400), duration: 0)
            controller.items = [item]
            controller.selected = item.id
            layout()
            XCTAssertGreaterThan(model.mediaContentHeights[operation] ?? 0, (empty[operation] ?? 0) + 50)
            XCTAssertLessThan(model.mediaContentHeights[operation] ?? 0, (empty[operation] ?? 0) + 280)
            XCTAssertEqual(model.mediaContentHeights[other] ?? 0, empty[other] ?? 0, accuracy: 2)
            controller.clear()
            layout()
            XCTAssertEqual(model.mediaContentHeights[operation] ?? 0, empty[operation] ?? 0, accuracy: 2)
        }
        for (window, _) in fixtures { window.contentViewController = nil }
    }

}
