import Foundation
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
}
