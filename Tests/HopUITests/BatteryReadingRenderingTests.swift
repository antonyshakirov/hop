import SwiftUI
import XCTest
@testable import Hop

@MainActor
final class BatteryReadingRenderingTests: XCTestCase {
    func testMissingTemperatureLeavesOnlyCharge() throws {
        try assertReading(percent: 100, temperature: nil, expected: "100%")
    }

    func testChargingLabelSurvivesMissingTemperature() throws {
        try assertReading(percent: 100, temperature: nil, charging: true, expected: "100% · charging")
    }

    func testAvailableTemperatureStillUsesSelectedUnit() throws {
        try assertReading(percent: 75, temperature: 38, expected: "75% · 38°")
        try assertReading(percent: 75, temperature: 38, unit: "f", expected: "75% · 100°")
    }

    private func assertReading(
        percent: Int, temperature: Double?, charging: Bool = false,
        unit: String = "c", expected: String
    ) throws {
        let defaults = UserDefaults.standard
        let oldUnit = defaults.object(forKey: "tempUnit"), wasSnapshot = Snapshot.active
        defaults.set(unit, forKey: "tempUnit")
        Snapshot.active = true
        defer {
            Snapshot.active = wasSnapshot
            if let oldUnit { defaults.set(oldUnit, forKey: "tempUnit") }
            else { defaults.removeObject(forKey: "tempUnit") }
        }
        let view = StatsView(stats: SystemStatsController(demo: true),
                             cooling: CoolingController(preview: true), lang: .en)
        let battery = BatteryInfo(percent: percent, tempC: temperature, isCharging: charging)
        let actual = try XCTUnwrap(ImageRenderer(content: view.batteryValue(battery).font(Theme.mono(11))).nsImage)
        let reference = try XCTUnwrap(ImageRenderer(content: Text(expected).font(Theme.mono(11))).nsImage)
        XCTAssertEqual(actual.size, reference.size, "Battery row must render exactly the available readings")
    }
}
