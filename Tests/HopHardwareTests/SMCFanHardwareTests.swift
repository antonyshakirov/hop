import XCTest
@testable import HopHardwareKit

final class SMCFanHardwareTests: XCTestCase {
    private final class Transport: SMCTransport {
        var values: [String: SMCValue] = [:]
        var writes: [String] = []
        var reject: Set<String> = []
        var ignore: Set<String> = []
        func read(_ key: String) -> SMCValue? { values[key] }
        func write(_ key: String, bytes: [UInt8]) throws {
            writes.append(key)
            if reject.contains(key) { throw HardwareReason.commandFailed }
            guard let old = values[key], old.bytes.count == bytes.count else { throw HardwareReason.invalid }
            if !ignore.contains(key) { values[key] = SMCValue(type: old.type, bytes: bytes) }
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
