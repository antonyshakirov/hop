import XCTest
@testable import HopCore

final class PanelTabsTests: XCTestCase {

    // MARK: - migrate

    func testMigrateBuildsTwoTabLayout() {
        let model = PanelTabsModel.migrate(moduleOrder: ["timer", "awake", "clipboard"])

        XCTAssertEqual(model.tabs.count, 2)
        XCTAssertEqual(model.tabs[0].icon, "house")
        XCTAssertEqual(model.tabs[0].moduleKeys, ["timer", "awake", "clipboard"])
        XCTAssertEqual(model.tabs[1].icon, "gauge")
        XCTAssertEqual(model.tabs[1].moduleKeys, ["system"])
    }

    // MARK: - addTab

    func testAddTabAppendsEmptyTabAndReturnsItsID() {
        var model = PanelTabsModel(tabs: [PanelTab(icon: "house", moduleKeys: ["timer"])])

        let newID = model.addTab(icon: "star")

        XCTAssertNotNil(newID)
        XCTAssertEqual(model.tabs.count, 2)
        XCTAssertEqual(model.tabs.last?.id, newID)
        XCTAssertEqual(model.tabs.last?.icon, "star")
        XCTAssertEqual(model.tabs.last?.moduleKeys, [])
    }

    func testAddTabReturnsNilAtCapAndLeavesModelUnchanged() {
        var model = PanelTabsModel(tabs: (0..<PanelTabsModel.maxTabs).map { PanelTab(icon: "tab\($0)", moduleKeys: []) })
        let before = model

        let result = model.addTab(icon: "extra")

        XCTAssertNil(result)
        XCTAssertEqual(model, before)
    }

    // MARK: - deleteTab

    func testDeleteTabAppendsModulesToFirstRemainingTab() {
        let first = PanelTab(icon: "house", moduleKeys: ["timer"])
        let second = PanelTab(icon: "gauge", moduleKeys: ["system"])
        let third = PanelTab(icon: "star", moduleKeys: ["clipboard"])
        var model = PanelTabsModel(tabs: [first, second, third])

        model.deleteTab(second.id)

        XCTAssertEqual(model.tabs.map(\.id), [first.id, third.id])
        XCTAssertEqual(model.tabs[0].moduleKeys, ["timer", "system"])
        XCTAssertEqual(model.tabs[1].moduleKeys, ["clipboard"])
    }

    func testDeleteTabOfFirstTabAppendsToNewFirstTab() {
        let first = PanelTab(icon: "house", moduleKeys: ["timer"])
        let second = PanelTab(icon: "gauge", moduleKeys: ["system"])
        var model = PanelTabsModel(tabs: [first, second])

        model.deleteTab(first.id)

        XCTAssertEqual(model.tabs.map(\.id), [second.id])
        XCTAssertEqual(model.tabs[0].moduleKeys, ["system", "timer"])
    }

    func testDeleteTabIsNoOpOnLastRemainingTab() {
        let only = PanelTab(icon: "house", moduleKeys: ["timer"])
        var model = PanelTabsModel(tabs: [only])

        model.deleteTab(only.id)

        XCTAssertEqual(model.tabs, [only])
    }

    func testDeleteTabIsNoOpForUnknownID() {
        let first = PanelTab(icon: "house", moduleKeys: ["timer"])
        let second = PanelTab(icon: "gauge", moduleKeys: ["system"])
        var model = PanelTabsModel(tabs: [first, second])
        let before = model

        model.deleteTab(UUID())

        XCTAssertEqual(model, before)
    }

    // MARK: - moveTab

    func testMoveTabReordersTabs() {
        let a = PanelTab(icon: "a", moduleKeys: [])
        let b = PanelTab(icon: "b", moduleKeys: [])
        let c = PanelTab(icon: "c", moduleKeys: [])
        var model = PanelTabsModel(tabs: [a, b, c])

        model.moveTab(from: 0, to: 2)

        XCTAssertEqual(model.tabs.map(\.id), [b.id, c.id, a.id])
    }

    func testMoveTabIsNoOpForOutOfRangeIndices() {
        let a = PanelTab(icon: "a", moduleKeys: [])
        let b = PanelTab(icon: "b", moduleKeys: [])
        var model = PanelTabsModel(tabs: [a, b])
        let before = model

        model.moveTab(from: -1, to: 1)
        model.moveTab(from: 0, to: 5)

        XCTAssertEqual(model, before)
    }

    // MARK: - setIcon

    func testSetIconUpdatesMatchingTab() {
        let tab = PanelTab(icon: "house", moduleKeys: [])
        var model = PanelTabsModel(tabs: [tab])

        model.setIcon("star", tabID: tab.id)

        XCTAssertEqual(model.tabs[0].icon, "star")
    }

    func testSetIconIsNoOpForUnknownTabID() {
        let tab = PanelTab(icon: "house", moduleKeys: [])
        var model = PanelTabsModel(tabs: [tab])

        model.setIcon("star", tabID: UUID())

        XCTAssertEqual(model.tabs[0].icon, "house")
    }

    // MARK: - move(module:)

    func testMoveModuleRemovesFromSourceAndAppendsToTarget() {
        let first = PanelTab(icon: "house", moduleKeys: ["timer", "awake"])
        let second = PanelTab(icon: "gauge", moduleKeys: ["system"])
        var model = PanelTabsModel(tabs: [first, second])

        model.move(module: "awake", toTab: second.id)

        XCTAssertEqual(model.tabs[0].moduleKeys, ["timer"])
        XCTAssertEqual(model.tabs[1].moduleKeys, ["system", "awake"])
    }

    func testMoveModuleIsNoOpForUnknownModule() {
        let first = PanelTab(icon: "house", moduleKeys: ["timer"])
        let second = PanelTab(icon: "gauge", moduleKeys: ["system"])
        var model = PanelTabsModel(tabs: [first, second])
        let before = model

        model.move(module: "nonexistent", toTab: second.id)

        XCTAssertEqual(model, before)
    }

    func testMoveModuleIsNoOpForUnknownTab() {
        let first = PanelTab(icon: "house", moduleKeys: ["timer"])
        var model = PanelTabsModel(tabs: [first])
        let before = model

        model.move(module: "timer", toTab: UUID())

        XCTAssertEqual(model, before)
    }

    // MARK: - reorder

    func testReorderMovesModuleWithinTab() {
        let tab = PanelTab(icon: "house", moduleKeys: ["timer", "awake", "clipboard"])
        var model = PanelTabsModel(tabs: [tab])

        model.reorder(module: "timer", inTab: tab.id, to: 2)

        XCTAssertEqual(model.tabs[0].moduleKeys, ["awake", "clipboard", "timer"])
    }

    func testReorderClampsTargetIndexToValidBounds() {
        let tab = PanelTab(icon: "house", moduleKeys: ["timer", "awake", "clipboard"])
        var model = PanelTabsModel(tabs: [tab])

        model.reorder(module: "clipboard", inTab: tab.id, to: -5)
        XCTAssertEqual(model.tabs[0].moduleKeys, ["clipboard", "timer", "awake"])

        model.reorder(module: "clipboard", inTab: tab.id, to: 999)
        XCTAssertEqual(model.tabs[0].moduleKeys, ["timer", "awake", "clipboard"])
    }

    func testReorderIsNoOpForUnknownModuleOrTab() {
        let tab = PanelTab(icon: "house", moduleKeys: ["timer"])
        var model = PanelTabsModel(tabs: [tab])
        let before = model

        model.reorder(module: "nonexistent", inTab: tab.id, to: 0)
        model.reorder(module: "timer", inTab: UUID(), to: 0)

        XCTAssertEqual(model, before)
    }

    // MARK: - ensure

    func testEnsureAppendsOnlyMissingKeysToFirstTab() {
        let first = PanelTab(icon: "house", moduleKeys: ["timer"])
        let second = PanelTab(icon: "gauge", moduleKeys: ["system"])
        var model = PanelTabsModel(tabs: [first, second])

        model.ensure(modules: ["timer", "system", "clipboard"])

        XCTAssertEqual(model.tabs[0].moduleKeys, ["timer", "clipboard"])
        XCTAssertEqual(model.tabs[1].moduleKeys, ["system"])
    }

    // MARK: - tabID(containing:)

    func testTabIDContainingFindsOwningTab() {
        let first = PanelTab(icon: "house", moduleKeys: ["timer"])
        let second = PanelTab(icon: "gauge", moduleKeys: ["system"])
        let model = PanelTabsModel(tabs: [first, second])

        XCTAssertEqual(model.tabID(containing: "system"), second.id)
        XCTAssertNil(model.tabID(containing: "nonexistent"))
    }

    // MARK: - encode/decode

    func testEncodedDecodeRoundTrips() {
        let model = PanelTabsModel.migrate(moduleOrder: ["timer", "awake", "clipboard"])

        let raw = model.encoded()
        let decoded = PanelTabsModel.decode(raw)

        XCTAssertEqual(decoded, model)
    }

    func testDecodeGarbageReturnsNil() {
        XCTAssertNil(PanelTabsModel.decode("not json at all"))
        XCTAssertNil(PanelTabsModel.decode(""))
    }
}
