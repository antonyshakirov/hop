import XCTest
@testable import HopHardwareKit

final class IdleLidPolicyTests: XCTestCase {
    private var clear: [String: Int] { Dictionary(uniqueKeysWithValues: IdleLidPolicy.blockingAssertions.map { ($0, 0) }) }

    func testOnlyKnownExpiredIdleWithNoBlockersIsEligible() {
        XCTAssertTrue(IdleLidPolicy.eligible(idleSeconds: 120, sleepMinutes: 2, assertions: clear))
        for idle in [nil, -1, .nan, .infinity, 119] as [Double?] {
            XCTAssertFalse(IdleLidPolicy.eligible(idleSeconds: idle, sleepMinutes: 2, assertions: clear))
        }
        for minutes in [nil, 0, -1, .nan, .infinity] as [Double?] {
            XCTAssertFalse(IdleLidPolicy.eligible(idleSeconds: 120, sleepMinutes: minutes, assertions: clear))
        }
        XCTAssertFalse(IdleLidPolicy.eligible(idleSeconds: 120, sleepMinutes: 1, assertions: nil))
        XCTAssertFalse(IdleLidPolicy.eligible(idleSeconds: 120, sleepMinutes: 1, assertions: [:]))
        for key in IdleLidPolicy.blockingAssertions {
            var blocked = clear; blocked[key] = 1
            XCTAssertFalse(IdleLidPolicy.eligible(idleSeconds: 120, sleepMinutes: 1, assertions: blocked), key)
        }
    }

    func testUnknownOrInternalActiveAssertionsBlockAndMalformedLevelsAreRejected() {
        for key in ["UserIsActive", "InternalPreventSleep", "InternalPreventDisplaySleep", "SystemIsActive", "FutureAssertion"] {
            var values = clear; values[key] = 1
            XCTAssertFalse(IdleLidPolicy.unblocked(values))
        }
        var harmless = clear; harmless["PreventDiskIdle"] = 1; harmless["EnableIdleSleep"] = 1
        XCTAssertTrue(IdleLidPolicy.unblocked(harmless))
        for value in [0.5, -1, Double.nan, Double.infinity, "0", true] as [Any] {
            XCTAssertNil(IdleLidPolicy.levels(["test": value]))
        }
        XCTAssertEqual(IdleLidPolicy.levels(["test": NSNumber(value: 1)]), ["test": 1])
    }

    func testCurrentPowerSourceSleepSettingIsParsedWithoutAssertionSuffix() {
        XCTAssertEqual(IdleLidPolicy.sleepMinutes(" sleep 15 (sleep prevented by coreaudiod)\n SleepDisabled 1\n"), 15)
        XCTAssertEqual(IdleLidPolicy.sleepMinutes(" sleep 0\n"), 0)
        for text in ["", "SleepDisabled 1", "sleep unknown", "sleep 1\nsleep 2"] {
            XCTAssertNil(IdleLidPolicy.sleepMinutes(text))
        }
    }
}
