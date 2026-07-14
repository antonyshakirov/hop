import XCTest
@testable import HopCore

final class LaunchGuardTests: XCTestCase {
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        defaults = UserDefaults(suiteName: "LaunchGuardTests")!
        defaults.removePersistentDomain(forName: "LaunchGuardTests")
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: "LaunchGuardTests")
        super.tearDown()
    }

    func testFirstLaunchIsNotCrashLoop() {
        XCTAssertFalse(LaunchGuard.registerLaunch(defaults: defaults))
    }

    func testThresholdTriggersSafeMode() {
        XCTAssertFalse(LaunchGuard.registerLaunch(defaults: defaults)) // 1
        XCTAssertFalse(LaunchGuard.registerLaunch(defaults: defaults)) // 2
        XCTAssertTrue(LaunchGuard.registerLaunch(defaults: defaults))  // 3 — crash loop
    }

    func testMarkStableResetsCounter() {
        _ = LaunchGuard.registerLaunch(defaults: defaults)
        _ = LaunchGuard.registerLaunch(defaults: defaults)
        LaunchGuard.markStable(defaults: defaults)
        XCTAssertFalse(LaunchGuard.registerLaunch(defaults: defaults))
    }

    func testStaysInSafeModeWhileCrashing() {
        for _ in 1...3 { _ = LaunchGuard.registerLaunch(defaults: defaults) }
        // safe mode crashed too — the next launch is safe mode again
        XCTAssertTrue(LaunchGuard.registerLaunch(defaults: defaults))
    }
}
