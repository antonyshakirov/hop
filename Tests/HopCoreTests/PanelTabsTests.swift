import XCTest
@testable import HopCore

final class PanelTabsTests: XCTestCase {

    // MARK: - migrate

    func testMigrateBuildsThreeTabLayout() {
        let model = PanelTabsModel.migrate(moduleOrder: ["timer", "awake", "clipboard"])

        XCTAssertEqual(model.tabs.count, 3)
        XCTAssertEqual(model.tabs[0].icon, "house")
        XCTAssertEqual(model.tabs[0].moduleKeys, ["timer", "awake", "clipboard"])
        XCTAssertEqual(model.tabs[1].icon, "gauge")
        XCTAssertEqual(model.tabs[1].moduleKeys, ["system"])
        XCTAssertEqual(model.tabs[2].icon, "clock")
        XCTAssertEqual(model.tabs[2].moduleKeys, ["tracker"])
        XCTAssertEqual(model.inactive, [], "a fresh migrate has an empty inactive bucket")
    }

    // MARK: - inactive bucket

    // Models saved before the `inactive` field existed must keep decoding, with
    // an empty bucket — otherwise an update wipes everyone's spaces to migrate.
    func testDecodeOldJSONWithoutInactiveFieldYieldsEmptyBucket() {
        let json = """
        {"tabs":[
            {"id":"11111111-1111-1111-1111-111111111111","icon":"house","moduleKeys":["timer"]},
            {"id":"22222222-2222-2222-2222-222222222222","icon":"gauge","moduleKeys":["system"]}
        ]}
        """

        let model = PanelTabsModel.decode(json)

        XCTAssertNotNil(model)
        XCTAssertEqual(model?.inactive, [])
        XCTAssertEqual(model?.tabs.count, 2)
    }

    func testEncodedDecodeRoundTripsWithInactive() {
        var model = PanelTabsModel.migrate(moduleOrder: ["timer", "awake"])
        model.deactivate(module: "awake")

        let decoded = PanelTabsModel.decode(model.encoded())

        XCTAssertEqual(decoded, model)
        XCTAssertEqual(decoded?.inactive, ["awake"])
    }

    // The uniqueness invariant now spans tabs AND the inactive bucket.
    func testDecodeRejectsModuleInBothATabAndInactive() {
        let json = """
        {"tabs":[
            {"id":"11111111-1111-1111-1111-111111111111","icon":"house","moduleKeys":["timer"]}
        ],"inactive":["timer"]}
        """

        XCTAssertNil(PanelTabsModel.decode(json))
    }

    func testDeactivateMovesModuleFromTabToInactive() {
        let first = PanelTab(icon: "house", moduleKeys: ["timer", "awake"])
        var model = PanelTabsModel(tabs: [first])

        model.deactivate(module: "awake")

        XCTAssertEqual(model.tabs[0].moduleKeys, ["timer"])
        XCTAssertEqual(model.inactive, ["awake"])
    }

    func testDeactivateIsNoOpForUnknownOrAlreadyInactiveModule() {
        let first = PanelTab(icon: "house", moduleKeys: ["timer"])
        var model = PanelTabsModel(tabs: [first], inactive: ["awake"])
        let before = model

        model.deactivate(module: "nonexistent")
        model.deactivate(module: "awake")   // already inactive

        XCTAssertEqual(model, before)
    }

    // Reactivation: moving an inactive module onto a tab lifts it out of the bucket.
    func testMoveModuleLiftsItOutOfInactive() {
        let first = PanelTab(icon: "house", moduleKeys: ["timer"])
        var model = PanelTabsModel(tabs: [first], inactive: ["awake"])

        model.move(module: "awake", toTab: first.id)

        XCTAssertEqual(model.tabs[0].moduleKeys, ["timer", "awake"])
        XCTAssertEqual(model.inactive, [])
    }

    func testReorderInInactiveMovesWithinBucketAndClamps() {
        var model = PanelTabsModel(tabs: [PanelTab(icon: "house", moduleKeys: ["timer"])],
                                   inactive: ["awake", "clipboard", "convert"])

        model.reorder(inInactive: "convert", to: 0)
        XCTAssertEqual(model.inactive, ["convert", "awake", "clipboard"])

        model.reorder(inInactive: "convert", to: 999)
        XCTAssertEqual(model.inactive, ["awake", "clipboard", "convert"])
    }

    // A deactivated module must NOT be re-added to a tab by ensure — it is known.
    func testEnsureDoesNotReactivateInactiveModule() {
        let first = PanelTab(icon: "house", moduleKeys: ["timer"])
        var model = PanelTabsModel(tabs: [first], inactive: ["awake"])

        model.ensure(modules: ["timer", "awake", "clipboard"])

        XCTAssertEqual(model.tabs[0].moduleKeys, ["timer", "clipboard"])
        XCTAssertEqual(model.inactive, ["awake"], "awake stays inactive; only the unknown key lands on a tab")
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

    func testDeleteTabSendsItsModulesToInactive() {
        let first = PanelTab(icon: "house", moduleKeys: ["timer"])
        let second = PanelTab(icon: "gauge", moduleKeys: ["system"])
        let third = PanelTab(icon: "star", moduleKeys: ["clipboard"])
        var model = PanelTabsModel(tabs: [first, second, third])

        model.deleteTab(second.id)

        XCTAssertEqual(model.tabs.map(\.id), [first.id, third.id])
        XCTAssertEqual(model.tabs[0].moduleKeys, ["timer"], "modules are NOT folded into the first tab anymore")
        XCTAssertEqual(model.tabs[1].moduleKeys, ["clipboard"])
        XCTAssertEqual(model.inactive, ["system"])
    }

    func testDeleteFirstTabSendsItsModulesToInactive() {
        let first = PanelTab(icon: "house", moduleKeys: ["timer"])
        let second = PanelTab(icon: "gauge", moduleKeys: ["system"])
        var model = PanelTabsModel(tabs: [first, second])

        model.deleteTab(first.id)

        XCTAssertEqual(model.tabs.map(\.id), [second.id])
        XCTAssertEqual(model.tabs[0].moduleKeys, ["system"])
        XCTAssertEqual(model.inactive, ["timer"])
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

    func testMoveModuleAlreadyInDestinationTabLeavesSingleOccurrence() {
        let first = PanelTab(icon: "house", moduleKeys: ["awake"])
        let second = PanelTab(icon: "gauge", moduleKeys: ["timer", "system"])
        var model = PanelTabsModel(tabs: [first, second])

        model.move(module: "timer", toTab: second.id)

        XCTAssertEqual(model.tabs[0].moduleKeys, ["awake"])
        XCTAssertEqual(model.tabs[1].moduleKeys, ["system", "timer"])
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

    // A model exactly at the cap (maxTabs) must decode; one tab over must not.
    func testDecodeAcceptsMaxTabs() {
        let json = """
        {"tabs":[
            {"id":"11111111-1111-1111-1111-111111111111","icon":"a","moduleKeys":["m1"]},
            {"id":"22222222-2222-2222-2222-222222222222","icon":"b","moduleKeys":["m2"]},
            {"id":"33333333-3333-3333-3333-333333333333","icon":"c","moduleKeys":["m3"]},
            {"id":"44444444-4444-4444-4444-444444444444","icon":"d","moduleKeys":["m4"]}
        ]}
        """

        XCTAssertNotNil(PanelTabsModel.decode(json))
    }

    // Storage is UserDefaults, which a user can hand-edit, so well-formed
    // JSON that breaks the model's own invariants must not decode either.
    // Five tabs is now over the cap (maxTabs = 4) and must be rejected.
    func testDecodeRejectsTooManyTabs() {
        let json = """
        {"tabs":[
            {"id":"11111111-1111-1111-1111-111111111111","icon":"a","moduleKeys":["m1"]},
            {"id":"22222222-2222-2222-2222-222222222222","icon":"b","moduleKeys":["m2"]},
            {"id":"33333333-3333-3333-3333-333333333333","icon":"c","moduleKeys":["m3"]},
            {"id":"44444444-4444-4444-4444-444444444444","icon":"d","moduleKeys":["m4"]},
            {"id":"55555555-5555-5555-5555-555555555555","icon":"e","moduleKeys":["m5"]}
        ]}
        """

        XCTAssertNil(PanelTabsModel.decode(json))
    }

    func testDecodeRejectsDuplicateModuleKeyAcrossTabs() {
        let json = """
        {"tabs":[
            {"id":"11111111-1111-1111-1111-111111111111","icon":"house","moduleKeys":["timer"]},
            {"id":"22222222-2222-2222-2222-222222222222","icon":"gauge","moduleKeys":["timer"]}
        ]}
        """

        XCTAssertNil(PanelTabsModel.decode(json))
    }
}
