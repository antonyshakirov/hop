import XCTest
@testable import HopCore

final class SettingsModuleGroupsTests: XCTestCase {
    func testEveryModuleAppearsExactlyOnceInFiveLogicalGroups() {
        let groups = ModuleCatalog.settingsGroups(in: [])
        XCTAssertEqual(groups.map(\.id), ["time", "files", "screen", "system", "network"])
        let ids = groups.flatMap(\.modules)
        XCTAssertEqual(ids.count, Set(ids).count)
        XCTAssertEqual(Set(ids), Set(ModuleCatalog.allIDs))
        XCTAssertEqual(groups.first { $0.id == "time" }?.modules, ["timer", "tracker", "todos"])
        XCTAssertEqual(Set(groups.first { $0.id == "screen" }?.modules ?? []),
                       ["color", "ocr", "shot", "annotate", "windows"])
    }

    func testPanelOrderWinsWithinEachGroupWithoutMovingBetweenGroups() {
        let groups = ModuleCatalog.settingsGroups(in: ["vpn", "todos", "timer", "system", "tracker"])
        XCTAssertEqual(groups.first?.modules, ["todos", "timer", "tracker"])
        XCTAssertEqual(groups.last?.modules.first, "vpn")
        XCTAssertEqual(groups.map(\.id), ["time", "files", "screen", "system", "network"])
    }

    func testUnknownDuplicateAndMissingPanelIDsNeverDropOrDuplicateModules() {
        let groups = ModuleCatalog.settingsGroups(in: ["unknown", "apps:custom", "sound", "sound"])
        XCTAssertEqual(groups.flatMap(\.modules).count, ModuleCatalog.allIDs.count)
        XCTAssertEqual(Set(groups.flatMap(\.modules)), Set(ModuleCatalog.allIDs))
        XCTAssertEqual(groups.first { $0.id == "system" }?.modules.first, "sound")
        XCTAssertEqual(groups, ModuleCatalog.settingsGroups(in: ["sound"]))
    }
}
