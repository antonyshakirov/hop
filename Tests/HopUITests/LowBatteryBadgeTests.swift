import XCTest
@testable import Hop

@MainActor
final class LowBatteryBadgeTests: XCTestCase {
    func testLowBatteryOnlyCountsWhenEnabledAndNotCharging() {
        let suite = "HopUITests.lowBattery.\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        var sample = StatsSample()
        sample.battery = BatteryInfo(percent: 5, tempC: nil, cycles: nil,
                                     healthPercent: nil, isCharging: false,
                                     batteryWatts: nil, adapterWatts: nil)

        XCTAssertFalse(SystemStatsController.isRedZone(sample, defaults: defaults))
        defaults.set(true, forKey: SettingsKey.menuBarRedAlertBattery)
        XCTAssertTrue(SystemStatsController.isRedZone(sample, defaults: defaults))
        sample.battery?.isCharging = true
        XCTAssertFalse(SystemStatsController.isRedZone(sample, defaults: defaults))
    }
}
