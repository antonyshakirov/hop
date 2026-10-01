import XCTest
@testable import Hop

@MainActor
final class RedZoneTests: XCTestCase {
    private let suite = "HopUITests.redZone"
    private var defaults: UserDefaults!
    private let gigabyte = 1_073_741_824.0

    override func setUp() {
        defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suite)
        let file = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Preferences/\(suite).plist")
        try? FileManager.default.removeItem(at: file)
    }

    func testSwapPastItsRedThresholdLightsTheMark() {
        var sample = StatsSample()
        sample.memTotal = 24 * gigabyte
        sample.memPressure = 1
        sample.swapUsed = 11 * gigabyte
        XCTAssertFalse(SystemStatsController.isRedZone(sample, defaults: defaults))
        sample.swapUsed = 14.4 * gigabyte
        XCTAssertTrue(SystemStatsController.isRedZone(sample, defaults: defaults))
    }

    func testSwapThresholdFromSettingsIsTheOneThatCounts() {
        var sample = StatsSample()
        sample.memTotal = 24 * gigabyte
        sample.swapUsed = 14.4 * gigabyte
        defaults.set(80, forKey: Thresholds.swapRedKey)
        XCTAssertFalse(SystemStatsController.isRedZone(sample, defaults: defaults))
    }

    func testCriticalMemoryPressureLightsTheMarkWithoutSwap() {
        var sample = StatsSample()
        sample.memTotal = 24 * gigabyte
        sample.swapUsed = 0
        sample.memPressure = 4
        XCTAssertTrue(SystemStatsController.isRedZone(sample, defaults: defaults))
    }

    func testGraphicsLoadHasItsOwnThreshold() {
        var sample = StatsSample()
        sample.gpuLoad = 0.90
        XCTAssertFalse(SystemStatsController.isRedZone(sample, defaults: defaults))
        defaults.set(90, forKey: Thresholds.gpuRedKey)
        XCTAssertTrue(SystemStatsController.isRedZone(sample, defaults: defaults))
    }

    func testProcessorThresholdDoesNotJudgeTheGraphicsCard() {
        var sample = StatsSample()
        sample.gpuLoad = 0.90
        defaults.set(50, forKey: Thresholds.loadRedKey)
        XCTAssertFalse(SystemStatsController.isRedZone(sample, defaults: defaults))
    }

    func testGraphicsTemperatureFallsBackToTheChipItSharesWithTheProcessor() {
        XCTAssertEqual(SystemStatsController.gpuTemperature(sensor: nil, chip: 71), 71)
        XCTAssertEqual(SystemStatsController.gpuTemperature(sensor: 64, chip: 71), 64)
        XCTAssertNil(SystemStatsController.gpuTemperature(sensor: nil, chip: nil))
    }
}
