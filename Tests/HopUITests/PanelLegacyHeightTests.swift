import AppKit
import HopCore
import SwiftUI
import XCTest
@testable import Hop

@MainActor
final class PanelLegacyHeightTests: XCTestCase {
    private static var retained: [AnyObject] = []

    private final class Content: ObservableObject {
        @Published var height: CGFloat
        init(height: CGFloat) { self.height = height }
    }

    private struct Space: View {
        @ObservedObject var content: Content
        var body: some View {
            VStack(spacing: 0) {
                Text("tabs").frame(height: 50)
                Color.gray.frame(height: content.height - 50)
            }
            .frame(width: 368)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
    }

    func testShortSpaceDoesNotKeepThePreviousTallWindow() {
        checkHeights([700, 200, 500, 200])
    }

    func testTallSpaceDoesNotKeepThePreviousShortWindow() {
        checkHeights([200, 700, 350, 700])
    }

    func testRealPanelFitsEachSpaceFromEitherInitialSpace() throws {
        let defaults = UserDefaults.standard
        let migrationKeys = [SettingsKey.trackerTabSeeded, SettingsKey.todosSeeded,
            SettingsKey.moduleVisibilityMigrated, SettingsKey.canonicalLayoutSeeded,
            SettingsKey.optInModulesSeeded, SettingsKey.optInModulesSeeded170]
        let keys = [SettingsKey.panelTabs, "activeSpaceID", "onboardingDone"] + migrationKeys
        let saved = keys.map { defaults.object(forKey: $0) }
        let snapshot = Snapshot.active
        Snapshot.active = false
        defer {
            Snapshot.active = snapshot
            for (key, value) in zip(keys, saved) {
                if let value { defaults.set(value, forKey: key) }
                else { defaults.removeObject(forKey: key) }
            }
        }
        for key in migrationKeys { defaults.set(true, forKey: key) }
        defaults.set(false, forKey: "onboardingDone")
        let tall = PanelTab(icon: "house", moduleKeys: ["timer", "awake", "clipboard", "keyboard", "windows"])
        let short = PanelTab(icon: "tray", moduleKeys: ["archive", "color", "convert"])
        let tabs = [tall, short]
        let inactive = ModuleCatalog.allIDs.filter { !Set(tabs.flatMap(\.moduleKeys)).contains($0) }
        for initial in [0, 1] {
            defaults.set(PanelTabsModel(tabs: tabs, inactive: inactive).encoded(), forKey: SettingsKey.panelTabs)
            defaults.set(tabs[initial].id.uuidString, forKey: "activeSpaceID")
            let model = AppModel(preview: true)
            model.clipboard.clear()
            model.panelScreenVisibleHeight = 1200
            model.isPanelOpen = { true }
            let controller = IntegralSizeHostingController(rootView: AnyView(
                PanelView(initial: .space(tabs[initial].id)).environmentObject(model)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)))
            controller.configureForPopover()
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 368, height: 700),
                styleMask: .borderless, backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            var reported: CGSize?
            model.panelContentSizeChanged = { [weak window] size in
                DispatchQueue.main.async {
                    reported = size
                    window?.setContentSize(size)
                }
            }
            model.panelContentSizeWillChange = { [weak window] size in
                reported = size
                window?.setContentSize(size)
            }
            window.contentViewController = controller
            var heights: [Int: CGFloat] = [:]
            for index in [initial, 1 - initial, initial, 1 - initial] {
                model.openTab = .space(tabs[index].id)
                for _ in 0..<20 {
                    controller.view.layoutSubtreeIfNeeded()
                    RunLoop.main.run(until: Date().addingTimeInterval(0.01))
                }
                let measured = try XCTUnwrap(reported)
                XCTAssertFalse(window.isVisible)
                XCTAssertEqual(window.contentLayoutRect.height, measured.height, accuracy: 1)
                XCTAssertEqual(controller.view.frame.height, measured.height, accuracy: 1)
                if let previous = heights[index] { XCTAssertEqual(measured.height, previous, accuracy: 1) }
                heights[index] = measured.height
            }
            XCTAssertGreaterThan(try XCTUnwrap(heights[0]), try XCTUnwrap(heights[1]) + 100)
            model.soundCallMix.shutdown()
            Self.retained.append(contentsOf: [model as AnyObject, controller, window])
        }
    }

    private func checkHeights(_ heights: [CGFloat], file: StaticString = #filePath, line: UInt = #line) {
        _ = NSApplication.shared
        let content = Content(height: heights[0])
        let controller = IntegralSizeHostingController(rootView: AnyView(Space(content: content)))
        controller.configureForPopover()
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 368, height: heights[0]),
                              styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentViewController = controller
        for height in heights {
            content.height = height
            window.setContentSize(NSSize(width: 368, height: height))
            for _ in 0..<8 {
                controller.view.layoutSubtreeIfNeeded()
                RunLoop.main.run(until: Date().addingTimeInterval(0.01))
            }
            XCTAssertFalse(window.isVisible, file: file, line: line)
            XCTAssertEqual(window.contentLayoutRect.height, height, accuracy: 1,
                "The requested space height must survive deferred hosting layout", file: file, line: line)
            XCTAssertEqual(controller.view.frame.height, height, accuracy: 1,
                "Hosting must not leave a blank band outside the active space", file: file, line: line)
        }
        Self.retained.append(contentsOf: [content as AnyObject, controller, window])
    }
}
