import XCTest
@testable import HopCore

final class ToolVersionTests: XCTestCase {
    func testNoMinimumNeverAsksForUpdate() {
        XCTAssertFalse(ToolVersion.isBelow("1.0", minimum: nil))
        XCTAssertFalse(ToolVersion.isBelow(nil, minimum: nil))
    }

    /// Installs made before versions were recorded have no version on disk; the
    /// only engine ever shipped that way is 8.1.1, so unknown counts as old.
    func testUnknownInstalledVersionIsBelowAnyMinimum() {
        XCTAssertTrue(ToolVersion.isBelow(nil, minimum: "9.0.1"))
        XCTAssertTrue(ToolVersion.isBelow("", minimum: "9.0.1"))
        XCTAssertTrue(ToolVersion.isBelow("garbage", minimum: "9.0.1"))
    }

    func testComparesComponentsNumerically() {
        XCTAssertTrue(ToolVersion.isBelow("8.1.1", minimum: "9.0.1"))
        XCTAssertFalse(ToolVersion.isBelow("9.0.1", minimum: "9.0.1"))
        XCTAssertFalse(ToolVersion.isBelow("9.0.10", minimum: "9.0.2"))
        XCTAssertTrue(ToolVersion.isBelow("9.0.2", minimum: "9.0.10"))
        XCTAssertFalse(ToolVersion.isBelow("9.1", minimum: "9.0.1"))
        XCTAssertFalse(ToolVersion.isBelow("9.0", minimum: "9.0.0"))
        XCTAssertFalse(ToolVersion.isBelow("v9.0.1", minimum: "9.0.1"))
    }
}
