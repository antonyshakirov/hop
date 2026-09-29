import XCTest
@testable import Hop

@MainActor
final class LowBatteryBadgeTests: XCTestCase {
    func testLowBatteryOnlyCountsWhenEnabledAndNotCharging() {
        // One fixed name, and the file itself removed: a fresh name per run left an
        // empty plist in ~/Library/Preferences every time.
        let suite = "HopUITests.lowBattery"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        defer {
            defaults.removePersistentDomain(forName: suite)
            let file = FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Library/Preferences/\(suite).plist")
            try? FileManager.default.removeItem(at: file)
        }
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
