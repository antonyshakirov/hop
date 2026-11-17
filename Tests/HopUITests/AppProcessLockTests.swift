import Foundation
import Darwin
import XCTest
@testable import Hop

final class AppProcessLockTests: XCTestCase {
    func testIndependentCopiesCannotOwnTheSameUpdateAndReleasePermitsRecovery() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("process-lock-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let first = try AppProcessLock(directory: directory, name: "hardware")
        XCTAssertThrowsError(try AppProcessLock(directory: directory, name: "hardware"))
        first.release()
        let next = try AppProcessLock(directory: directory, name: "hardware")
        next.release()
    }
    func testReadOnlyPreflightNeverCreatesMissingLockStateAndCapturesContention() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("preflight-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        XCTAssertThrowsError(try AppProcessLock(directory: directory, name: "hardware", createIfMissing: false))
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.path))
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: 0o700])
        XCTAssertThrowsError(try AppProcessLock(directory: directory, name: "hardware", createIfMissing: false))
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.appendingPathComponent("hardware.lock").path))
        let first = try AppProcessLock(directory: directory, name: "hardware")
        defer { first.release() }
        var reported: Int32?
        XCTAssertThrowsError(try AppProcessLock(directory: directory, name: "hardware", createIfMissing: false, onFlock: { reported = $0 }))
        XCTAssertEqual(reported, EWOULDBLOCK)
        first.release()
        let next = try AppProcessLock(directory: directory, name: "hardware", createIfMissing: false, onFlock: { reported = $0 })
        next.release()
        XCTAssertEqual(reported, 0)
    }

}
