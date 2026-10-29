import AppKit
import HopCore
import SwiftUI
import XCTest
@testable import Hop

@MainActor
final class PanelContentLayoutTests: XCTestCase {
    private static var retainedFixtures: [AnyObject] = []
    private var saved: [String: Any] = [:]
    private let migrationKeys = [SettingsKey.trackerTabSeeded, SettingsKey.todosSeeded,
                                 SettingsKey.moduleVisibilityMigrated, SettingsKey.canonicalLayoutSeeded,
                                 SettingsKey.optInModulesSeeded, SettingsKey.optInModulesSeeded170]
    private var keys: [String] {
        [SettingsKey.panelTabs, "activeSpaceID", "onboardingDone", ClipboardController.visibleRowsKey,
         Theme.themeKey, SettingsKey.appLanguage] + migrationKeys
    }

    override func setUp() {
        super.setUp()
        _ = NSApplication.shared
        let defaults = UserDefaults.standard
        for key in keys { saved[key] = defaults.object(forKey: key) }
        for key in migrationKeys { defaults.set(true, forKey: key) }
        defaults.set(false, forKey: "onboardingDone")
    }

    override func tearDown() {
        Snapshot.active = false
        for key in keys {
            if let value = saved[key] { UserDefaults.standard.set(value, forKey: key) }
            else { UserDefaults.standard.removeObject(forKey: key) }
        }
        super.tearDown()
    }

    func testSingleSpaceRemovesTheWholeServiceHeader() {
        Snapshot.active = true
        let tab = PanelTab(icon: "house", moduleKeys: ModuleCatalog.allIDs)
        let single = panelHeight(tabs: [tab])
        let multiple = panelHeight(tabs: [tab, PanelTab(icon: "clock", moduleKeys: [])])
        XCTAssertEqual(multiple - single, 50, accuracy: 1,
                       "A single space must remove the 34pt header and its 16pt gap")
    }

    func testClipboardShowsTenRowsAndShrinksBackWithoutAnEmptyArea() throws {
        let clipboard = ClipboardController(demo: true)
        clipboard.clear()
        for index in 1...30 { clipboard.rememberForSelfTest("Entry \(index)") }
        UserDefaults.standard.set(3, forKey: ClipboardController.visibleRowsKey)
        let host = NSHostingView(rootView: ClipboardView(clipboard: clipboard, lang: .en)
            .frame(width: 340))
        let window = NSWindow(contentRect: NSRect(x: 600, y: 300, width: 340, height: 136),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        window.orderFront(nil)
        defer { window.orderOut(nil) }
        Self.retainedFixtures.append(contentsOf: [clipboard as AnyObject, host, window])
        for rows in [3, 10, 1, 10, 3] {
            UserDefaults.standard.set(rows, forKey: ClipboardController.visibleRowsKey)
            pump()
            let natural = host.fittingSize.height
            window.setContentSize(NSSize(width: 340, height: natural))
            host.layoutSubtreeIfNeeded()
            pump()
            let scroll = try XCTUnwrap(descendants(of: host).compactMap { $0 as? NSScrollView }.first)
            XCTAssertEqual(natural, CGFloat(rows * 36 + 28), accuracy: 1)
            XCTAssertGreaterThanOrEqual(scroll.contentView.bounds.height, CGFloat(rows * 36 - 4),
                                        "The selected rows must fit in the actual viewport")
            XCTAssertLessThanOrEqual(scroll.contentView.bounds.height, CGFloat(rows * 36 + 4),
                                     "The viewport must not keep space from an old row count")
        }
    }

    func testPanelResizesWhenTheClipboardRowPreferenceChanges() {
        let tab = PanelTab(icon: "house", moduleKeys: ModuleCatalog.allIDs)
        UserDefaults.standard.set(PanelTabsModel(tabs: [tab], hidden: Set(ModuleCatalog.allIDs).subtracting(["clipboard"])).encoded(), forKey: SettingsKey.panelTabs)
        UserDefaults.standard.set(3, forKey: ClipboardController.visibleRowsKey)
        let model = AppModel(preview: true)
        model.panelScreenVisibleHeight = 1200
        model.clipboard.clear()
        for index in 1...30 { model.clipboard.rememberForSelfTest("Entry \(index)") }
        let controller = IntegralSizeHostingController(rootView: AnyView(
            PanelView(initial: .firstSpace).environmentObject(model)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        ))
        controller.enableExplicitPopoverSizing()
        controller.enableFirstMouse()
        let window = NSWindow(contentRect: NSRect(x: 600, y: 500, width: 368, height: 50),
                              styleMask: [.titled], backing: .buffered, defer: false)
        let anchor = NSView(frame: NSRect(x: 0, y: 0, width: 368, height: 50))
        window.contentView = anchor
        window.orderFront(nil)
        let popover = NSPopover()
        popover.animates = false
        popover.contentViewController = controller
        var reported: CGSize = .zero
        var publishedTabRect: CGRect?
        model.panelTabGeometryChanged = { publishedTabRect = model.panelTabHitRect }
        model.panelContentSizeChanged = { [weak popover] size in
            reported = size
            DispatchQueue.main.async { popover?.contentSize = size }
        }
        controller.view.layoutSubtreeIfNeeded()
        popover.contentSize = controller.view.fittingSize
        popover.show(relativeTo: anchor.bounds, of: anchor, preferredEdge: .minY)
        defer { popover.close(); window.orderOut(nil) }
        Self.retainedFixtures.append(contentsOf: [model as AnyObject, controller, window, popover])
        pump()
        let initial = popover.contentSize.height
        for rows in [10, 1, 10, 3] {
            UserDefaults.standard.set(rows, forKey: ClipboardController.visibleRowsKey)
            let expected = initial + CGFloat((rows - 3) * 36)
            let deadline = Date().addingTimeInterval(2)
            repeat {
                pump()
                controller.view.layoutSubtreeIfNeeded()
            } while abs(popover.contentSize.height - expected) > 1 && Date() < deadline
            XCTAssertEqual(popover.contentSize.height, expected, accuracy: 1,
                           "A preference change must resize the already visible panel")
            XCTAssertEqual(reported.height, expected, accuracy: 1)
            XCTAssertEqual(controller.view.frame.height, expected, accuracy: 1)
        }
        for count in [2, 1, 2, 1] {
            let tabs = count == 1 ? [tab] : [tab, PanelTab(icon: "clock", moduleKeys: [])]
            UserDefaults.standard.set(PanelTabsModel(tabs: tabs,
                hidden: Set(ModuleCatalog.allIDs).subtracting(["clipboard"])).encoded(),
                forKey: SettingsKey.panelTabs)
            let expected = initial + (count == 1 ? 0 : 50)
            let deadline = Date().addingTimeInterval(2)
            repeat { pump(); controller.view.layoutSubtreeIfNeeded() }
            while abs(popover.contentSize.height - expected) > 1 && Date() < deadline
            pump()
            XCTAssertEqual(popover.contentSize.height, expected, accuracy: 1)
            if count == 1 {
                XCTAssertNil(model.panelTabHitRect)
                XCTAssertNil(publishedTabRect, "The overlay subscriber must receive the removed hit area")
            } else {
                XCTAssertNotNil(publishedTabRect)
            }
        }
    }

    func testPanelHasNoHeaderGapInBothThemesAndLongLanguages() throws {
        Snapshot.active = true
        for language in ["en", "ru", "de", "fr"] {
            UserDefaults.standard.set(language, forKey: SettingsKey.appLanguage)
            for theme in ["dark", "light"] {
                UserDefaults.standard.set(theme, forKey: Theme.themeKey)
                for count in [1, 2] {
                    let tab = PanelTab(icon: "house", moduleKeys: ModuleCatalog.allIDs)
                    let tabs = count == 1 ? [tab] : [tab, PanelTab(icon: "clock", moduleKeys: [])]
                    UserDefaults.standard.set(PanelTabsModel(tabs: tabs,
                        hidden: Set(ModuleCatalog.allIDs).subtracting(["clipboard"])).encoded(),
                        forKey: SettingsKey.panelTabs)
                    let model = AppModel(preview: true)
                    model.clipboard.clear()
                    for index in 1...20 { model.clipboard.rememberForSelfTest("Entry \(index)") }
                    UserDefaults.standard.set(10, forKey: ClipboardController.visibleRowsKey)
                    let view = PanelView(initial: .firstSpace).environmentObject(model)
                    let renderer = ImageRenderer(content: view)
                    renderer.scale = 2
                    let image = try XCTUnwrap(renderer.nsImage)
                    XCTAssertEqual(image.size.width, 368, accuracy: 1)
                    XCTAssertEqual(image.size.height, count == 1 ? 424 : 474, accuracy: 1)
                    if let directory = ProcessInfo.processInfo.environment["HOP_UI_ARTIFACTS"] {
                        let url = URL(fileURLWithPath: directory)
                            .appendingPathComponent("clipboard-10-\(count)-tabs-\(language)-\(theme).png")
                        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                               withIntermediateDirectories: true)
                        let data = try XCTUnwrap(image.tiffRepresentation)
                        let bitmap = try XCTUnwrap(NSBitmapImageRep(data: data))
                        try XCTUnwrap(bitmap.representation(using: .png, properties: [:])).write(to: url)
                    }
                }
            }
        }
    }

    private func panelHeight(tabs: [PanelTab]) -> CGFloat {
        UserDefaults.standard.set(PanelTabsModel(tabs: tabs, hidden: Set(ModuleCatalog.allIDs).subtracting(["clipboard"])).encoded(), forKey: SettingsKey.panelTabs)
        let model = AppModel(preview: true)
        let host = NSHostingView(rootView: PanelView(initial: .firstSpace).environmentObject(model))
        let window = NSWindow(contentRect: NSRect(x: 600, y: 300, width: 368, height: 300),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        window.orderFront(nil)
        pump()
        host.layoutSubtreeIfNeeded()
        Self.retainedFixtures.append(contentsOf: [model as AnyObject, host, window])
        let height = host.fittingSize.height
        window.orderOut(nil)
        return height
    }

    private func pump() {
        for _ in 0..<8 { RunLoop.main.run(until: Date().addingTimeInterval(0.01)) }
    }

    private func descendants(of view: NSView) -> [NSView] {
        [view] + view.subviews.flatMap { descendants(of: $0) }
    }
}
