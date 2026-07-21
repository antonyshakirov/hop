import XCTest
@testable import HopCore

/// Torrent speed-limit unit conversion: the canonical stored value is always
/// KB/s; the UI can display/enter it as KB/s or MB/s (1 MB = 1000 KB, the same
/// decimal convention the torrent card uses). 0 = unlimited.
final class RateLimitTests: XCTestCase {

    func testDisplayKB() {
        XCTAssertEqual(RateLimit.display(kb: 0, unit: .kb), "0")
        XCTAssertEqual(RateLimit.display(kb: 500, unit: .kb), "500")
        XCTAssertEqual(RateLimit.display(kb: 12500, unit: .kb), "12500")
    }

    func testDisplayMBTrimsTrailingZeros() {
        XCTAssertEqual(RateLimit.display(kb: 0, unit: .mb), "0")
        XCTAssertEqual(RateLimit.display(kb: 2000, unit: .mb), "2")
        XCTAssertEqual(RateLimit.display(kb: 1500, unit: .mb), "1.5")
        XCTAssertEqual(RateLimit.display(kb: 1200, unit: .mb), "1.2")
        XCTAssertEqual(RateLimit.display(kb: 500, unit: .mb), "0.5")
    }

    func testParseKB() {
        XCTAssertEqual(RateLimit.parse("500", unit: .kb), 500)
        XCTAssertEqual(RateLimit.parse("12500", unit: .kb), 12500)
    }

    func testParseMBDecimal() {
        XCTAssertEqual(RateLimit.parse("2", unit: .mb), 2000)
        XCTAssertEqual(RateLimit.parse("12.5", unit: .mb), 12500)
        XCTAssertEqual(RateLimit.parse("0.5", unit: .mb), 500)
        XCTAssertEqual(RateLimit.parse(".5", unit: .mb), 500)
    }

    func testEmptyOrZeroIsUnlimited() {
        XCTAssertEqual(RateLimit.parse("", unit: .kb), 0)
        XCTAssertEqual(RateLimit.parse("", unit: .mb), 0)
        XCTAssertEqual(RateLimit.parse("0", unit: .kb), 0)
        XCTAssertEqual(RateLimit.parse("0", unit: .mb), 0)
    }

    func testInvalidReturnsNil() {
        XCTAssertNil(RateLimit.parse("abc", unit: .kb))
        XCTAssertNil(RateLimit.parse("1.2.3", unit: .mb))
    }

    func testParseClampsToMax() {
        XCTAssertEqual(RateLimit.parse("99999999", unit: .kb), RateLimit.maxKB)
        XCTAssertEqual(RateLimit.parse("999999", unit: .mb), RateLimit.maxKB)
    }

    func testRoundTripKBtoMBtoKB() {
        for kb in [0, 500, 1000, 1200, 1500, 2000, 12500] {
            let shown = RateLimit.display(kb: kb, unit: .mb)
            XCTAssertEqual(RateLimit.parse(shown, unit: .mb), kb, "round-trip failed for \(kb)")
        }
    }

    func testClampKB() {
        XCTAssertEqual(RateLimit.clampKB(-5), 0)
        XCTAssertEqual(RateLimit.clampKB(500), 500)
        XCTAssertEqual(RateLimit.clampKB(RateLimit.maxKB + 10), RateLimit.maxKB)
    }
}
