import XCTest
@testable import Hop

@MainActor
final class UpdateCadenceTests: XCTestCase {
    func testTheSiteIsAskedForANewReleaseEveryHalfHour() {
        XCTAssertEqual(UpdateChecker.checkInterval, 30 * 60)
    }

    func testAFoundReleaseRetriesItsInstallEveryMinute() {
        XCTAssertEqual(UpdateChecker.installRetryInterval, 60)
    }
}
