import XCTest
@testable import HopCore

final class PowerMathTests: XCTestCase {
    // MARK: - signedAmperage

    func testNormalDischargePassesThrough() {
        // A battery reporting a genuine signed negative needs no correction.
        XCTAssertEqual(PowerMath.signedAmperage(-500), -500)
    }

    func testChargePassesThrough() {
        XCTAssertEqual(PowerMath.signedAmperage(1200), 1200)
    }

    func testZeroPassesThrough() {
        XCTAssertEqual(PowerMath.signedAmperage(0), 0)
    }

    func testWrapped32BitNegativeIsRecovered() {
        // -500 mA widened into 64 bits without sign extension: 2^32 - 500.
        XCTAssertEqual(PowerMath.signedAmperage(4_294_966_796), -500)
    }

    func testWrappedMinusOneIsRecovered() {
        // 0xFFFFFFFF ⇒ -1
        XCTAssertEqual(PowerMath.signedAmperage(4_294_967_295), -1)
    }

    func testInt32MaxIsNotTreatedAsWrapped() {
        // Exactly Int32.max is a plausible (huge) charge current, not a wrap.
        XCTAssertEqual(PowerMath.signedAmperage(Int(Int32.max)), Int(Int32.max))
    }

    func testJustAboveInt32MaxIsWrapped() {
        // First value past the boundary is a wrapped negative (2^31, i.e. Int32.min).
        XCTAssertEqual(PowerMath.signedAmperage(Int(Int32.max) + 1), Int(Int32.min))
    }

    // MARK: - batteryWatts

    func testWattsDischargeIsNegative() {
        // -500 mA at 12000 mV = -6 W.
        XCTAssertEqual(PowerMath.batteryWatts(amperage: 4_294_966_796, voltage: 12_000), -6, accuracy: 0.0001)
    }

    func testWattsChargeIsPositive() {
        // 1500 mA at 12000 mV = 18 W.
        XCTAssertEqual(PowerMath.batteryWatts(amperage: 1500, voltage: 12_000), 18, accuracy: 0.0001)
    }

    func testWattsRegressionGuardAgainstOldNoOp() {
        // The old `1<<64` no-op produced a ~51_500 W reading here; the corrected
        // math must be a small negative. Guard the magnitude so it can't creep back.
        let watts = PowerMath.batteryWatts(amperage: 4_294_966_796, voltage: 12_000)
        XCTAssertLessThan(watts, 0)
        XCTAssertGreaterThan(watts, -100)
    }
}
