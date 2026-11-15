import XCTest
@testable import HopHardwareKit

final class FanPolicyTests: XCTestCase {
    private let fans = [FanReading(id: 0, rpm: 1200, minimum: 1000, maximum: 6000, manual: false),
                        FanReading(id: 2, rpm: 1400, minimum: 1200, maximum: 7000, manual: false)]

    func testMaximumAndCurveUseEachActualFanRangeAndStableIndex() throws {
        XCTAssertEqual(try FanPolicy(mode: .maximum).speeds(for: fans, temperature: nil), [0: 6000, 2: 7000])
        let curve = FanPolicy(mode: .curve)
        XCTAssertEqual(try curve.speeds(for: fans, temperature: 50), [0: 1000, 2: 1200])
        XCTAssertEqual(try curve.speeds(for: fans, temperature: 72.5), [0: 3500, 2: 4100])
        XCTAssertEqual(try curve.speeds(for: fans, temperature: 100), [0: 6000, 2: 7000])
    }

    func testInvalidAndMissingSensorsOrTargetsNeverProduceWrites() {
        for value in [Double.nan, .infinity, -.infinity, 0, 150] {
            XCTAssertThrowsError(try FanPolicy(mode: .curve).speeds(for: fans, temperature: value))
            XCTAssertThrowsError(try FanPolicy(mode: .fixed, targets: [0: value, 2: 3000])
                .speeds(for: fans, temperature: nil))
        }
        XCTAssertThrowsError(try FanPolicy(mode: .curve).speeds(for: fans, temperature: nil))
        XCTAssertThrowsError(try FanPolicy(mode: .curve, cool: 85, hot: 60).speeds(for: fans, temperature: 70))
        XCTAssertThrowsError(try FanPolicy(mode: .fixed, targets: [0: 3000]).speeds(for: fans, temperature: nil))
        XCTAssertThrowsError(try FanPolicy(mode: .maximum).speeds(for: [], temperature: 70))
        XCTAssertThrowsError(try FanPolicy(mode: .maximum).speeds(for: [fans[0], fans[0]], temperature: 70))
    }

    func testFixedDoesNotClampAnInvalidRequestIntoSuccess() throws {
        XCTAssertThrowsError(try FanPolicy(mode: .fixed, targets: [0: 999, 2: 3000]).speeds(for: fans, temperature: nil))
        XCTAssertThrowsError(try FanPolicy(mode: .fixed, targets: [0: 3000, 2: 7001]).speeds(for: fans, temperature: nil))
        XCTAssertEqual(try FanPolicy(mode: .fixed, targets: [0: 3000, 2: 3500])
            .speeds(for: fans, temperature: nil), [0: 3000, 2: 3500])
    }

    func testProtocolBoundsAndDurations() throws {
        XCTAssertThrowsError(try HardwareRequest.decode(Data(repeating: 0, count: 16385)))
        XCTAssertThrowsError(try HardwareRequest.decode(Data("{\"version\":2,\"operation\":\"status\"}".utf8)))
        for duration in [Double.nan, .infinity, -1, 0, 28801] {
            XCTAssertFalse(HardwareConfiguration(lid: true, duration: duration).valid)
        }
        let request = HardwareRequest(.configure, configuration: .init(lid: true, duration: 600))
        XCTAssertEqual(try HardwareRequest.decode(JSONEncoder().encode(request)).configuration?.duration, 600)
        XCTAssertNil(HardwareObservation(temperature: 70, temperatureAge: 11).freshTemperature)
    }
}
