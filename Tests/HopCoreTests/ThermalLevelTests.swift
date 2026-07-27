import XCTest
@testable import HopCore

/// The monitor used to call a healthy Mac overheated: red at a fixed 90 °C,
/// while Apple Silicon sits at 90-100 °C under sustained load by design. These
/// tests pin the mapping to macOS's own verdict instead.
final class ThermalLevelTests: XCTestCase {

    // ProcessInfo.ThermalState raw values.
    private let nominal = 0, fair = 1, serious = 2, critical = 3

    func testNominalAndFairAreBothNormal() {
        // fair means the fans have picked up — a Mac doing its job. Colouring it
        // yellow would leave the row yellow under any real workload, which says
        // nothing at all.
        XCTAssertEqual(ThermalLevel.from(thermalStateRawValue: nominal), .normal)
        XCTAssertEqual(ThermalLevel.from(thermalStateRawValue: fair), .normal)
    }

    func testSeriousIsTheFirstWarning() {
        XCTAssertEqual(ThermalLevel.from(thermalStateRawValue: serious), .warning)
    }

    func testCriticalIsRed() {
        XCTAssertEqual(ThermalLevel.from(thermalStateRawValue: critical), .critical)
    }

    func testUnknownStateNeverAlarms() {
        // A future macOS may add a state. An unrecognised one must not invent a
        // red row on a machine that is running perfectly well.
        XCTAssertEqual(ThermalLevel.from(thermalStateRawValue: 99), .normal)
        XCTAssertEqual(ThermalLevel.from(thermalStateRawValue: -1), .normal)
    }
}
