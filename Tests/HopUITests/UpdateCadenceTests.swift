import XCTest
@testable import Hop

@MainActor
final class UpdateCadenceTests: XCTestCase {
    func testTheSiteIsAskedForANewReleaseEveryHour() {
        XCTAssertEqual(UpdateChecker.checkInterval, 60 * 60)
    }

    func testAFoundReleaseRetriesItsInstallEveryMinute() {
        XCTAssertEqual(UpdateChecker.installRetryInterval, 60)
    }
}
