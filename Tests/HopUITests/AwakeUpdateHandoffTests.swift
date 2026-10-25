import Foundation
import XCTest
@testable import Hop

final class AwakeUpdateHandoffTests: XCTestCase {
    func testGuardAcknowledgesOnlyAfterAssertionAndReleasesOnAdoption() throws {
        let id = UUID()
        let directory = try AwakeUpdateHandoff.makeDirectory(id: id)
        defer { try? FileManager.default.removeItem(at: directory) }
        var acquired = false, released = false, sleeps = 0
        AwakeUpdateHandoff.serve(id: id, keepDisplay: true, acquire: { display in
            XCTAssertTrue(display)
            XCTAssertFalse(FileManager.default.fileExists(atPath: directory.appendingPathComponent("ready").path))
            acquired = true
            return { released = true }
        }, sleep: { _ in
            XCTAssertTrue(acquired)
            XCTAssertEqual(AwakeUpdateHandoff.processID(id: id), ProcessInfo.processInfo.processIdentifier)
            XCTAssertFalse(released)
            XCTAssertTrue(FileManager.default.fileExists(atPath: directory.appendingPathComponent("ready").path))
            sleeps += 1
            AwakeUpdateHandoff.finish(id: id)
        })
        XCTAssertEqual(sleeps, 1)
        XCTAssertTrue(released)
    }

    func testGuardFailureDoesNotAdvertiseReadiness() throws {
        let id = UUID()
        let directory = try AwakeUpdateHandoff.makeDirectory(id: id)
        defer { try? FileManager.default.removeItem(at: directory) }
        AwakeUpdateHandoff.serve(id: id, keepDisplay: false, acquire: { _ in nil },
            sleep: { _ in XCTFail("Failed assertion must not wait") })
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.appendingPathComponent("ready").path))
    }

    func testEndlessGuardWaitsUntilExplicitRelease() throws {
        let id = UUID()
        let directory = try AwakeUpdateHandoff.makeDirectory(id: id)
        var released = false, checks = 0
        AwakeUpdateHandoff.serve(id: id, keepDisplay: false, acquire: { _ in { released = true } },
            sleep: { _ in
                checks += 1
                XCTAssertFalse(released)
                XCTAssertTrue(AwakeUpdateHandoff.isLive(id: id))
                if checks == 3 { AwakeUpdateHandoff.finish(id: id) }
            })
        XCTAssertTrue(released)
        XCTAssertEqual(checks, 3)
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.path))
    }

    func testMissingLeaseNeverAcquiresPowerAssertion() {
        AwakeUpdateHandoff.serve(id: UUID(), keepDisplay: false, acquire: { _ in
            XCTFail("No lease must not change power state"); return nil
        }, sleep: { _ in XCTFail("No lease must not wait") })
    }
    func testReadyFileWithoutLiveGuardCannotBypassSingleInstance() throws {
        let id = UUID()
        let directory = try AwakeUpdateHandoff.makeDirectory(id: id)
        defer { AwakeUpdateHandoff.finish(id: id) }
        try Data("12345".utf8).write(to: directory.appendingPathComponent("ready"))
        _ = FileManager.default.createFile(atPath: directory.appendingPathComponent("lock").path, contents: Data())
        XCTAssertFalse(AwakeUpdateHandoff.isLive(id: id))
        XCTAssertNil(AwakeUpdateHandoff.processID(id: id))
    }

    func testGuardRecoveryDistinguishesLiveLostAndRestoredProtection() throws {
        let id = UUID()
        _ = try AwakeUpdateHandoff.makeDirectory(id: id)
        AwakeUpdateHandoff.serve(id: id, keepDisplay: false, acquire: { _ in {} }, sleep: { _ in
            XCTAssertEqual(AwakeUpdateHandoff.recover(id: id, acquire: { false }), .guarded)
            XCTAssertEqual(AwakeUpdateHandoff.recover(id: id, acquire: { true }), .owned)
            AwakeUpdateHandoff.finish(id: id)
        })
        XCTAssertEqual(AwakeUpdateHandoff.recover(id: id, acquire: { false }), .lost)
        XCTAssertEqual(AwakeUpdateHandoff.recover(id: id, acquire: { true }), .owned)
    }

}
