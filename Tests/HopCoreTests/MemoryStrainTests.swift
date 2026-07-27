import XCTest
@testable import HopCore

final class MemoryStrainTests: XCTestCase {
    private let gb = 1_073_741_824.0

    // MARK: - macOS's own signal

    func testPressureLevelsMapToVerdicts() {
        XCTAssertEqual(MemoryStrain.fromPressure(1), .normal)
        XCTAssertEqual(MemoryStrain.fromPressure(2), .warning)
        XCTAssertEqual(MemoryStrain.fromPressure(4), .critical)
    }

    func testAnUnknownPressureValueIsNotAVerdict() {
        // the kernel numbers these 1, 2, 4 — anything else is not a level
        XCTAssertEqual(MemoryStrain.fromPressure(nil), .unknown)
        XCTAssertEqual(MemoryStrain.fromPressure(3), .unknown)
        XCTAssertEqual(MemoryStrain.fromPressure(0), .unknown)
    }

    // MARK: - swap against RAM

    private func swap(_ swapGB: Double, ramGB: Double) -> MemoryStrain.Level {
        MemoryStrain.fromSwap(swapBytes: swapGB * gb, physicalBytes: ramGB * gb,
                              yellowPercent: 25, redPercent: 50)
    }

    func testLittleSwapIsNormal() {
        XCTAssertEqual(swap(0, ramGB: 24), .normal)
        XCTAssertEqual(swap(2, ramGB: 24), .normal)
    }

    func testAQuarterOfRAMInSwapWarns() {
        XCTAssertEqual(swap(6, ramGB: 24), .warning)
        // the reading that started this: 24 GB machine, 9.4 GB swapped out
        XCTAssertEqual(swap(9.4, ramGB: 24), .warning)
    }

    func testHalfOfRAMInSwapIsCritical() {
        XCTAssertEqual(swap(12, ramGB: 24), .critical)
        XCTAssertEqual(swap(30, ramGB: 24), .critical)
    }

    func testTheShareIsOfRAMSoASmallMacWarnsSooner() {
        // 2 GB on disk is a quarter of an 8 GB machine and a twelfth of a 24 GB one
        XCTAssertEqual(swap(2, ramGB: 8), .warning)
        XCTAssertEqual(swap(2, ramGB: 24), .normal)
    }

    func testMissingCountersAreNotAVerdict() {
        XCTAssertEqual(MemoryStrain.fromSwap(swapBytes: nil, physicalBytes: 24 * gb,
                                             yellowPercent: 25, redPercent: 50), .unknown)
        XCTAssertEqual(MemoryStrain.fromSwap(swapBytes: 9 * gb, physicalBytes: nil,
                                             yellowPercent: 25, redPercent: 50), .unknown)
        XCTAssertEqual(MemoryStrain.fromSwap(swapBytes: 9 * gb, physicalBytes: 0,
                                             yellowPercent: 25, redPercent: 50), .unknown)
    }

    // MARK: - the two together

    func testSwapSpeaksUpWhileMacOSStaysCalm() {
        // the whole point: pressure says normal, swap says a lot is on disk
        let level = MemoryStrain.level(pressure: 1, swapBytes: 9.4 * gb,
                                       physicalBytes: 24 * gb,
                                       yellowPercent: 25, redPercent: 50)
        XCTAssertEqual(level, .warning)
    }

    func testMacOSSpeaksUpWhileSwapIsQuiet() {
        // pressure can spike with barely any swap written yet
        let level = MemoryStrain.level(pressure: 4, swapBytes: 0,
                                       physicalBytes: 24 * gb,
                                       yellowPercent: 25, redPercent: 50)
        XCTAssertEqual(level, .critical)
    }

    func testACalmMachineStaysCalm() {
        let level = MemoryStrain.level(pressure: 1, swapBytes: 0.4 * gb,
                                       physicalBytes: 24 * gb,
                                       yellowPercent: 25, redPercent: 50)
        XCTAssertEqual(level, .normal)
    }

    func testOneSignalIsEnoughWhenTheOtherIsMissing() {
        XCTAssertEqual(MemoryStrain.level(pressure: nil, swapBytes: 12 * gb,
                                          physicalBytes: 24 * gb,
                                          yellowPercent: 25, redPercent: 50), .critical)
        XCTAssertEqual(MemoryStrain.level(pressure: 2, swapBytes: nil,
                                          physicalBytes: nil,
                                          yellowPercent: 25, redPercent: 50), .warning)
    }

    func testNoSignalAtAllIsNoVerdict() {
        XCTAssertEqual(MemoryStrain.level(pressure: nil, swapBytes: nil, physicalBytes: nil,
                                          yellowPercent: 25, redPercent: 50), .unknown)
    }

    func testThresholdsAreHonoured() {
        // a user who only wants to hear about it when half the machine is on disk
        XCTAssertEqual(MemoryStrain.fromSwap(swapBytes: 9.4 * gb, physicalBytes: 24 * gb,
                                             yellowPercent: 50, redPercent: 80), .normal)
    }
}
