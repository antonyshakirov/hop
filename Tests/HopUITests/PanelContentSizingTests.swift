import AppKit
import SwiftUI
import XCTest
import HopCore
@testable import Hop

@MainActor
final class PanelContentSizingTests: XCTestCase {
    private static var retainedFixtures: [AnyObject] = []

    func testSingleTabWithFourModulesAndVPNUsesNaturalHeightAfterReconfiguration() throws {
        let defaults = UserDefaults.standard
        let keys = [SettingsKey.panelTabs, "activeSpaceID", SettingsKey.trackerTabSeeded,
                    SettingsKey.todosSeeded, SettingsKey.moduleVisibilityMigrated,
                    SettingsKey.canonicalLayoutSeeded, SettingsKey.optInModulesSeeded,
                    SettingsKey.optInModulesSeeded170]
        let saved = Dictionary(uniqueKeysWithValues: keys.map { ($0, defaults.object(forKey: $0)) })
        defer {
            for (key, value) in saved {
                if let value { defaults.set(value, forKey: key) }
                else { defaults.removeObject(forKey: key) }
            }
        }
        for key in keys.dropFirst(2) { defaults.set(true, forKey: key) }
        let compact = PanelTab(icon: "house", moduleKeys: ["awake", "clipboard", "speedtest", "keyboard"])
        let extra = PanelTab(icon: "clock", moduleKeys: ["timer"])
        let third = PanelTab(icon: "tray", moduleKeys: ["convert"])
        func layout(_ tabs: [PanelTab]) -> String {
            let active = Set(tabs.flatMap(\.moduleKeys))
            return PanelTabsModel(tabs: tabs, inactive: ModuleCatalog.allIDs.filter {
                !active.contains($0)
            }).encoded()
        }
        defaults.set(layout([compact, extra, third]), forKey: SettingsKey.panelTabs)
        defaults.set(compact.id.uuidString, forKey: "activeSpaceID")
        let model = AppModel(preview: true)
        model.panelScreenVisibleHeight = 1000
        let host = IntegralSizeHostingController(rootView: AnyView(
            PanelView(initial: .firstSpace).environmentObject(model)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)))
        host.enableExplicitPopoverSizing()
        host.enableFirstMouse()
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 368, height: 800),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentViewController = host
        var reported: CGSize?
        model.panelContentSizeChanged = { size in
            reported = size
            window.setContentSize(size)
        }
        func settle() {
            for _ in 0..<10 {
                host.view.layoutSubtreeIfNeeded()
                RunLoop.main.run(until: Date().addingTimeInterval(0.02))
            }
        }
        settle()
        try XCTSkipIf(reported == nil, "SwiftUI geometry was not measured without a window server")
        defaults.set(layout([compact]), forKey: SettingsKey.panelTabs)
        settle()
        let fourModuleHeight = try XCTUnwrap(reported).height
        XCTAssertLessThan(fourModuleHeight, 600, "four compact modules must not retain an 800pt host")
        var withVPN = compact
        withVPN.moduleKeys.append("vpn")
        defaults.set(layout([withVPN]), forKey: SettingsKey.panelTabs)
        settle()
        let fiveModuleHeight = try XCTUnwrap(reported).height
        XCTAssertGreaterThan(fiveModuleHeight, fourModuleHeight)
        defaults.set(layout([compact]), forKey: SettingsKey.panelTabs)
        settle()
        XCTAssertEqual(try XCTUnwrap(reported).height, fourModuleHeight, accuracy: 1,
                       "removing VPN must restore the measured compact height without an empty bottom")
        Self.retainedFixtures.append(contentsOf: [model as AnyObject, host, window])
    }
}
