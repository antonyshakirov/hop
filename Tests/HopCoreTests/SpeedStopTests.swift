import XCTest
@testable import HopCore

final class SpeedStopTests: XCTestCase {
    func testStoppedDuringTheUploadKeepsBoth() {
        let result = SpeedSummary.stopped(down: 480, up: 36.5)
        XCTAssertEqual(result?.down, 480)
        XCTAssertEqual(result?.up, 36.5)
    }

    func testStoppedDuringTheDownloadLeavesTheUploadOpen() {
        let result = SpeedSummary.stopped(down: 212, up: nil)
        XCTAssertEqual(result?.down, 212)
        XCTAssertNil(result?.up)
    }

    func testAZeroIsANumberNotYetMeasured() {
        XCTAssertNil(SpeedSummary.stopped(down: 150, up: 0)?.up)
    }

    func testStoppedBeforeAnyNumberKeepsTheResultBefore() {
        XCTAssertNil(SpeedSummary.stopped(down: nil, up: nil))
        XCTAssertNil(SpeedSummary.stopped(down: 0, up: 0))
    }
}
