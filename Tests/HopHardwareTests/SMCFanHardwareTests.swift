import XCTest
@testable import HopHardwareKit

final class SMCFanHardwareTests: XCTestCase {
    private final class Transport: SMCTransport {
        var values: [String: SMCValue] = [:]
        var writes: [String] = []
        var reject: Set<String> = []
        var ignore: Set<String> = []
        var transientFailures: [String: Int] = [:]
        var systemAutomaticOnRelease = false
        var targetReadDelay = 0
        var staleReads: [String: (SMCValue, Int)] = [:]
        var reclaimOnTarget = false
        var reclaimOnSecondTargetRead = false
        var targetReads = 0
        func read(_ key: String) -> SMCValue? {
            if reclaimOnSecondTargetRead, key == "F0Tg", writes.contains(key) {
                targetReads += 1
                if targetReads == 2 { byte("F0Md", 3); return values["F0Ac"] }
            }
            if let (value, count) = staleReads[key], count > 0 {
                staleReads[key] = (value, count - 1)
                return value
            }
            return values[key]
        }
        func write(_ key: String, bytes: [UInt8]) throws {
            writes.append(key)
            if reject.contains(key) { throw HardwareReason.commandFailed }
            if let remaining = transientFailures[key], remaining > 0 {
                transientFailures[key] = remaining - 1
                throw HardwareReason.commandFailed
            }
            guard let old = values[key], old.bytes.count == bytes.count else { throw HardwareReason.invalid }
            if !ignore.contains(key) {
                let released = systemAutomaticOnRelease && (key.hasSuffix("Md") || key.hasSuffix("md")) && bytes == [0]
                values[key] = SMCValue(type: old.type, bytes: released ? [3] : bytes)
                if key.hasSuffix("Tg") {
                    if targetReadDelay > 0 { staleReads[key] = (old, targetReadDelay) }
                    if reclaimOnTarget { byte(String(key.prefix(2)) + "Md", 3) }
                }
            }
        }
        func keyCount() -> Int { values.keys.count }
        func key(at index: Int) -> String? { values.keys.sorted()[index] }
        func byte(_ key: String, _ value: UInt8) { values[key] = SMCValue(type: "ui8 ", bytes: [value]) }
        func float(_ key: String, _ value: Float) {
            values[key] = SMCValue(type: "flt ", bytes: withUnsafeBytes(of: value) { Array($0) })
        }
        func fixed(_ key: String, _ value: Double) {
            let raw = UInt16(value * 4)
            values[key] = SMCValue(type: "fpe2", bytes: [UInt8(raw >> 8), UInt8(raw & 255)])
        }
    }

    private func apple() -> Transport {
        let transport = Transport()
        transport.byte("FNum", 2); transport.byte("Ftst", 0)
        transport.float("Tp00", 65); transport.float("Te00", 55)
        for index in 0..<2 {
            transport.float("F\(index)Ac", 1500)
            transport.float("F\(index)Mn", 1000)
            transport.float("F\(index)Mx", 6000)
            transport.float("F\(index)Tg", 1500)
            transport.byte("F\(index)Md", 0)
        }
        return transport
    }

    func testFanlessIdentificationNeedsPositiveModelEvidence() {
        let unknown = SMCFanHardware(transport: nil, canWrite: { false }, modelIdentifier: "MacBookPro18,1")
        XCTAssertEqual(unknown.read().availability, .unavailable)
        let air = SMCFanHardware(transport: nil, canWrite: { false }, modelIdentifier: "Mac17,3")
        XCTAssertEqual(air.read().availability, .fanless)
        XCTAssertFalse(FanDevice.isKnownFanless("MacBookAir7,2"))
        XCTAssertFalse(FanDevice.isKnownFanless("Mac99,99"))
        XCTAssertTrue(FanDevice.isKnownFanless("MacBookAir10,1"))
        let zero = Transport(); zero.byte("FNum", 0)
        XCTAssertEqual(SMCFanHardware(transport: zero, canWrite: { false }).read().availability, .unavailable)
    }

    func testAFailedInitialConnectionRetriesWithABoundedBackoff() {
        let transport = apple()
        var clock: Double = 0, attempts = 0
        let hardware = SMCFanHardware(transport: nil, canWrite: { false }, connect: {
            attempts += 1
            return attempts == 1 ? nil : transport
        }, clock: { clock })
        XCTAssertEqual(hardware.read().availability, .unavailable)
        clock = 2.9
        XCTAssertEqual(hardware.read().availability, .unavailable)
        XCTAssertEqual(attempts, 1)
        clock = 3
        XCTAssertTrue(hardware.read().supportsControl)
        XCTAssertEqual(hardware.read().fans.count, 2)
        XCTAssertEqual(attempts, 2)
        XCTAssertTrue(transport.writes.isEmpty)
    }

    func testFailedTargetWriteReportsOnlyBoundedHardwareDetails() {
        let transport = apple(); transport.reject.insert("F0Tg")
        let hardware = SMCFanHardware(transport: transport, canWrite: { true })
        XCTAssertThrowsError(try hardware.setTargets([0: 5000, 1: 5500]))
        XCTAssertEqual(hardware.lastFailure?.phase, .targetWrite)
        XCTAssertEqual(hardware.lastFailure?.key, "F0Tg")
        XCTAssertEqual(hardware.lastFailure?.expected, 5000)
        XCTAssertEqual(hardware.lastFailure?.actual, 1500)
        XCTAssertTrue(hardware.lastFailure?.valid == true)
        XCTAssertNil(FanFailure(phase: .targetReadback, actual: .nan).actual)
        XCTAssertFalse(FanFailure(phase: .targetWrite, key: "untrusted").valid)
    }

    func testManualModesDoNotRequireTheUnlockTriggerToRemainSet() throws {
        let transport = apple()
        transport.byte("F0Md", 1); transport.byte("F1Md", 1)
        transport.byte("Ftst", 0); transport.reject.insert("Ftst")
        let hardware = SMCFanHardware(transport: transport, canWrite: { true })
        try hardware.setTargets([0: 5000, 1: 5500])
        XCTAssertEqual(transport.read("F0Tg")?.number, 5000)
        XCTAssertEqual(transport.read("F1Tg")?.number, 5500)
        XCTAssertFalse(transport.writes.contains("Ftst"))
    }

    func testAcceptedTargetsCanAcknowledgeAfterOneStaleRead() throws {
        let transport = apple()
        transport.targetReadDelay = 1
        let hardware = SMCFanHardware(transport: transport, canWrite: { true })
        try hardware.setTargets([0: 5000, 1: 5500])
        XCTAssertEqual(transport.read("F0Tg")?.number, 5000)
        XCTAssertEqual(transport.read("F1Tg")?.number, 5500)
        try hardware.restore(indices: [0, 1])
    }

    func testFirmwareReclaimDuringTheFinalTargetPollCannotAcknowledgeManualControl() {
        let transport = apple(); transport.reclaimOnSecondTargetRead = true
        let hardware = SMCFanHardware(transport: transport, canWrite: { true })
        XCTAssertThrowsError(try hardware.setTargets([0: 5000, 1: 5500]))
        XCTAssertEqual(hardware.lastFailure?.phase, .modeReadback)
        XCTAssertEqual(hardware.lastFailure?.actual, 3)
    }

    func testFirmwareReclaimDuringTargetWriteCannotAcknowledgeManualControl() throws {
        let transport = apple()
        transport.reclaimOnTarget = true
        let hardware = SMCFanHardware(transport: transport, canWrite: { true })
        XCTAssertThrowsError(try hardware.setTargets([0: 5000, 1: 5500]))
    }

    func testAlreadyConfirmedAutomaticModesDoNotRequireRedundantReleaseWrites() throws {
        let transport = apple()
        transport.byte("F0Md", 3); transport.byte("F1Md", 0)
        transport.byte("Ftst", 0)
        transport.reject = ["F0Md", "F1Md", "Ftst"]
        let hardware = SMCFanHardware(transport: transport, canWrite: { true })
        try hardware.restore(indices: [0, 1])
        XCTAssertTrue(transport.writes.isEmpty)
    }

    func testAppleSiliconTakeoverAndRestorationHaveReadback() throws {
        let transport = apple()
        let hardware = SMCFanHardware(transport: transport, canWrite: { true })
        XCTAssertTrue(hardware.read().supportsControl)
        XCTAssertEqual(hardware.read().temperature, 60)
        try hardware.setTargets([0: 3000, 1: 4000])
        XCTAssertEqual(transport.read("F0Tg")?.number, 3000)
        XCTAssertEqual(transport.read("F1Tg")?.number, 4000)
        XCTAssertTrue(hardware.read().fans.allSatisfy(\.manual))
        try hardware.restore(indices: [0, 1])
        XCTAssertEqual(transport.read("Ftst")?.number, 0)
        XCTAssertFalse(hardware.read().fans.contains(where: \.manual))
    }

    func testLowercaseDirectControlWithoutTestKeyKeepsFanIDsAndRestores() throws {
        let transport = apple()
        transport.values["Ftst"] = nil
        for index in 0..<2 {
            transport.values["F\(index)md"] = transport.values.removeValue(forKey: "F\(index)Md")
        }
        let hardware = SMCFanHardware(transport: transport, canWrite: { true })
        XCTAssertTrue(hardware.read().supportsControl)
        try hardware.setTargets([0: 3000, 1: 4000])
        XCTAssertEqual(transport.read("F1Tg")?.number, 4000)
        XCTAssertTrue(hardware.read().fans.allSatisfy(\.manual))
        try hardware.restore(indices: [0, 1])
        XCTAssertFalse(hardware.read().fans.contains(where: \.manual))
        XCTAssertFalse(transport.writes.contains("Ftst"))
    }

    func testUppercaseDirectControlDoesNotRequireGlobalTestKey() throws {
        let transport = apple()
        transport.values["Ftst"] = nil
        let hardware = SMCFanHardware(transport: transport, canWrite: { true })
        XCTAssertTrue(hardware.read().supportsControl)
        try hardware.setTargets([0: 3000, 1: 4000])
        try hardware.restore(indices: [0, 1])
        XCTAssertFalse(transport.writes.contains("Ftst"))
    }

    func testTemporaryModeWriteRejectionCanYieldBeforeTakeover() throws {
        let transport = apple()
        transport.transientFailures["F0Md"] = 2
        let hardware = SMCFanHardware(transport: transport, canWrite: { true })
        try hardware.setTargets([0: 3000, 1: 4000])
        XCTAssertEqual(transport.read("F0Md")?.number, 1)
        try hardware.restore(indices: [0, 1])
    }

    func testPermanentFirmwareRejectionAndIgnoredModeWritesCannotApplyTargets() throws {
        for silent in [false, true] {
            let transport = apple()
            if silent { transport.ignore.insert("F0Md") }
            else { transport.reject.insert("F0Md") }
            let hardware = SMCFanHardware(transport: transport, canWrite: { true })
            let start = ProcessInfo.processInfo.systemUptime
            XCTAssertThrowsError(try hardware.setTargets([0: 3000, 1: 4000]))
            let elapsed = ProcessInfo.processInfo.systemUptime - start
            XCTAssertGreaterThanOrEqual(elapsed, 2.8)
            XCTAssertLessThan(elapsed, 6)
            XCTAssertFalse(transport.writes.contains("F0Tg"))
            XCTAssertFalse(transport.writes.contains("F1Tg"))
            transport.reject.removeAll(); transport.ignore.removeAll()
            try hardware.restore(indices: [0, 1])
            XCTAssertEqual(transport.values["F0Md"]?.number, 0)
            XCTAssertEqual(transport.values["F1Md"]?.number, 0)
        }
    }

    func testSystemAutomaticReadbackAfterReleaseIsNotARecoveryFailure() throws {
        let transport = apple()
        transport.systemAutomaticOnRelease = true
        let hardware = SMCFanHardware(transport: transport, canWrite: { true })
        try hardware.setTargets([0: 3000, 1: 4000])
        try hardware.restore(indices: [0, 1])
        XCTAssertEqual(transport.read("F0Md")?.number, 3)
        XCTAssertFalse(hardware.read().fans.contains(where: \.manual))
    }

    func testIntelUsesFixedPointAndPreservesOtherManualBits() throws {
        let transport = Transport()
        transport.byte("FNum", 1)
        transport.byte("Ftst", 0)
        transport.values["FS! "] = SMCValue(type: "ui16", bytes: [0, 4])
        for (suffix, value) in [("Ac", 1500.0), ("Mn", 1000.0), ("Mx", 6000.0), ("Tg", 1500.0)] {
            transport.fixed("F0" + suffix, value)
        }
        let hardware = SMCFanHardware(transport: transport, canWrite: { true })
        XCTAssertTrue(hardware.read().supportsControl)
        try hardware.setTargets([0: 3210.25])
        XCTAssertEqual(transport.read("F0Tg")?.number, 3210.25)
        XCTAssertEqual(transport.read("FS! ")?.number, 5)
        try hardware.restore(indices: [0])
        XCTAssertEqual(transport.read("FS! ")?.number, 4)
    }

    func testMissingOrInvalidFanDoesNotShiftIDsOrAllowAnyWrite() {
        let transport = apple()
        transport.values["F0Ac"] = nil
        let hardware = SMCFanHardware(transport: transport, canWrite: { true })
        XCTAssertEqual(hardware.read().fans.map(\.id), [1])
        XCTAssertFalse(hardware.read().supportsControl)
        XCTAssertThrowsError(try hardware.setTargets([1: 3000]))
        XCTAssertTrue(transport.writes.isEmpty)
        transport.float("F0Ac", .nan)
        XCTAssertFalse(hardware.read().supportsControl)
        transport.byte("FNum", 250)
        XCTAssertTrue(hardware.read().fans.isEmpty)
    }

    func testDuplicateRecoveryIndicesAreRejectedBeforeWriting() {
        let transport = apple()
        let hardware = SMCFanHardware(transport: transport, canWrite: { true })
        XCTAssertThrowsError(try hardware.restore(indices: [0, 0]))
        XCTAssertTrue(transport.writes.isEmpty)
    }

    func testRootAndRangeChecksPrecedeEveryWrite() {
        let transport = apple()
        let unprivileged = SMCFanHardware(transport: transport, canWrite: { false })
        XCTAssertThrowsError(try unprivileged.setTargets([0: 3000, 1: 3000]))
        XCTAssertThrowsError(try unprivileged.restore(indices: [0, 1]))
        let hardware = SMCFanHardware(transport: transport, canWrite: { true })
        for values in [[0: Double.nan, 1: 3000], [0: 3000, 1: 999], [0: 3000], [0: 3000, 1: 6001]] {
            XCTAssertThrowsError(try hardware.setTargets(values))
        }
        XCTAssertTrue(transport.writes.isEmpty)
    }

    func testSuccessfulWriteWithoutReadbackIsAnErrorAndReleaseTriesAllFans() throws {
        let transport = apple()
        let hardware = SMCFanHardware(transport: transport, canWrite: { true })
        transport.ignore = ["F1Tg"]
        XCTAssertThrowsError(try hardware.setTargets([0: 3000, 1: 4000]))
        transport.reject = ["F0Md"]
        let previous = transport.writes.count
        XCTAssertThrowsError(try hardware.restore(indices: [0, 1]))
        XCTAssertEqual(Array(transport.writes.dropFirst(previous)), ["F0Md", "F1Md", "Ftst"])
        transport.reject = []; transport.ignore = []
        try hardware.restore(indices: [0, 1])
        XCTAssertFalse(hardware.read().fans.contains(where: \.manual))
    }

    func testUnknownControlSchemaRemainsReadOnly() {
        let transport = apple()
        transport.values["F1Tg"] = SMCValue(type: "ui16", bytes: [0, 1])
        let hardware = SMCFanHardware(transport: transport, canWrite: { true })
        XCTAssertFalse(hardware.read().supportsControl)
        XCTAssertThrowsError(try hardware.setTargets([0: 3000, 1: 3000]))
        XCTAssertTrue(transport.writes.isEmpty)
    }
}
