import XCTest
@testable import HopCore

final class MenuBarReadingsTests: XCTestCase {
    func testDefaultsKeepNewReadingsOff() {
        let settings = MenuBarReadings.decode("")
        XCTAssertTrue(settings.enabled.isEmpty)
        XCTAssertEqual(settings.order, MenuBarMetric.allCases)
        XCTAssertEqual(settings.layout, .rotating)
    }

    func testPersistenceAndOrderSurviveReload() {
        var settings = MenuBarReadings()
        settings.enabled = [.disk, .memory]
        settings.move(.disk, by: -1)
        settings.layout = .together
        settings.detailed = true
        XCTAssertEqual(MenuBarReadings.decode(settings.encoded), settings)
    }

    func testUnknownAndDuplicateEntriesDoNotLoseKnownPreferences() {
        let settings = MenuBarReadings.decode("{\"order\":[\"disk\",\"future\",\"disk\"],\"enabled\":[\"disk\",\"future\"],\"layout\":\"future\"}")
        XCTAssertEqual(settings.order.first, .disk)
        XCTAssertEqual(Set(settings.order).count, MenuBarMetric.allCases.count)
        XCTAssertEqual(settings.enabled, [.disk])
        XCTAssertEqual(settings.layout, .rotating)
    }

    func testMoveAtEdgesIsSafeAndCorruptStorageUsesDefaults() {
        var settings = MenuBarReadings()
        settings.move(.timer, by: -1)
        XCTAssertEqual(settings.order.first, .timer)
        XCTAssertEqual(MenuBarReadings.decode("not json"), MenuBarReadings())
    }

    func testModuleFilteringAndLegacyClockPreferences() {
        var settings = MenuBarReadings()
        settings.enabled = [.disk, .vpn, .awake]
        XCTAssertEqual(settings.visible(inactive: ["system", "vpn"], timer: true, tracker: false), [.timer, .awake])
        XCTAssertEqual(settings.visible(inactive: [], timer: false, tracker: true), [.tracker, .disk, .awake, .vpn])
    }

    func testWideRowsRotateWithoutDroppingSelectedReadings() {
        var settings = MenuBarReadings()
        settings.layout = .together
        XCTAssertFalse(settings.rotates(texts: ["CPU 24%", "128.0 GB"]))
        XCTAssertTrue(settings.rotates(texts: Array(repeating: "CPU 24%", count: 12)))
    }
}
