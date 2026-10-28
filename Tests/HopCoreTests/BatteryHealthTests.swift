import XCTest
@testable import HopCore

final class BatteryHealthTests: XCTestCase {
    func testMacOS27NestedCapacitiesRestoreHealth() {
        let properties: [String: Any] = [
            "CurrentCapacity": 100, "MaxCapacity": 100, "CycleCount": 154,
            "BatteryData": ["DesignCapacity": 4629, "NominalChargeCapacity": 4464,
                            "FullChargeCapacity": 4337]
        ]
        XCTAssertEqual(BatteryHealth.percent(properties: properties), 96)
    }

    func testLegacyCalibratedCapacityStillWinsOverRawCapacity() {
        XCTAssertEqual(BatteryHealth.percent(properties: [
            "DesignCapacity": 5000, "NominalChargeCapacity": 4900,
            "AppleRawMaxCapacity": 4600
        ]), 98)
    }

    func testNestedCalibratedCapacityWinsOverTopLevelRawCapacity() {
        XCTAssertEqual(BatteryHealth.percent(properties: [
            "DesignCapacity": 5000, "AppleRawMaxCapacity": 4500,
            "BatteryData": ["NominalChargeCapacity": 4800]
        ]), 96)
    }

    func testRawAndFullChargeCapacityFallbacks() {
        for key in ["AppleRawMaxCapacity", "FullChargeCapacity"] {
            XCTAssertEqual(BatteryHealth.percent(properties: [
                "BatteryData": ["DesignCapacity": 5000, key: 4000]
            ]), 80, key)
        }
        XCTAssertEqual(BatteryHealth.percent(properties: [
            "DesignCapacity": 5000, "AppleRawMaxCapacity": 4000
        ]), 80)
    }

    func testRemainingChargeIsNotBatteryHealth() {
        XCTAssertNil(BatteryHealth.percent(properties: [
            "DesignCapacity": 5000, "CurrentCapacity": 50, "MaxCapacity": 100,
            "BatteryData": ["RemainingCapacity": 2500]
        ]))
    }

    func testInvalidCapacitiesRemainUnavailable() {
        for design in [0, -1] {
            XCTAssertNil(BatteryHealth.percent(properties: [
                "DesignCapacity": design, "NominalChargeCapacity": 4000
            ]))
        }
        for capacity in [0, -1] {
            XCTAssertNil(BatteryHealth.percent(properties: [
                "DesignCapacity": 5000, "NominalChargeCapacity": capacity
            ]))
        }
        XCTAssertNil(BatteryHealth.percent(properties: ["BatteryData": "unavailable"]))
    }

    func testInvalidPrimaryValuesAllowValidNestedFallback() {
        XCTAssertEqual(BatteryHealth.percent(properties: [
            "DesignCapacity": 0, "NominalChargeCapacity": -1,
            "BatteryData": ["DesignCapacity": 5000, "NominalChargeCapacity": 4500]
        ]), 90)
    }

    func testHealthCannotExceedOneHundredOrOverflow() {
        XCTAssertEqual(BatteryHealth.percent(properties: [
            "DesignCapacity": 1, "NominalChargeCapacity": Int.max
        ]), 100)
    }
}
