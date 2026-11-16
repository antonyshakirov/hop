import Darwin
import Foundation
import XCTest
@testable import HopHardwareKit

final class HardwareCommandTests: XCTestCase {
    func testArgumentsArePassedLiterallyWithoutAShell() throws {
        var pid: pid_t = 0
        XCTAssertEqual(try HardwareCommand.run("/bin/echo", arguments: ["a b", "$(not-a-command);"],
                                               onSpawn: { pid = $0 }), "a b $(not-a-command);\n")
        assertReaped(pid)
    }

    func testStandardInputAndErrorAreNullAndExtraDescriptorsAreClosed() throws {
        XCTAssertEqual(try HardwareCommand.run("/bin/cat", arguments: []), "")
        let original = open("/dev/null", O_RDONLY)
        XCTAssertGreaterThanOrEqual(original, 0)
        defer { close(original) }
        let extra = fcntl(original, F_DUPFD, 128)
        XCTAssertGreaterThanOrEqual(extra, 128)
        defer { close(extra) }
        let script = "printf out; printf hidden >&2; test ! -e /dev/fd/\(extra)"
        XCTAssertEqual(try HardwareCommand.run("/bin/sh", arguments: ["-c", script]), "out")
    }

    func testNonzeroExitIsAnErrorAndChildIsAlreadyReaped() {
        var pid: pid_t = 0
        XCTAssertThrowsError(try HardwareCommand.run("/usr/bin/false", arguments: [], onSpawn: { pid = $0 })) {
            XCTAssertEqual($0 as? HardwareReason, .commandFailed)
        }
        assertReaped(pid)
    }

    func testTimeoutKillsAndReapsTheOwnedChild() {
        var pid: pid_t = 0
        let start = ProcessInfo.processInfo.systemUptime
        XCTAssertThrowsError(try HardwareCommand.run("/bin/sleep", arguments: ["5"], timeout: 0.03,
                                                     onSpawn: { pid = $0 })) {
            XCTAssertEqual($0 as? HardwareReason, .commandFailed)
        }
        XCTAssertLessThan(ProcessInfo.processInfo.systemUptime - start, 2)
        assertReaped(pid)
    }

    func testOutputAtTheLimitIsCompleteAndOneByteAboveFails() throws {
        XCTAssertEqual(try HardwareCommand.run("/usr/bin/head", arguments: ["-c", "16384", "/dev/zero"]).utf8.count, 16384)
        var pid: pid_t = 0
        XCTAssertThrowsError(try HardwareCommand.run("/usr/bin/head", arguments: ["-c", "16385", "/dev/zero"],
                                                     onSpawn: { pid = $0 })) {
            XCTAssertEqual($0 as? HardwareReason, .commandFailed)
        }
        assertReaped(pid)
    }

    func testOverflowBeforeExitCannotDeadlockOnAFullPipe() {
        var pid: pid_t = 0
        XCTAssertThrowsError(try HardwareCommand.run("/usr/bin/yes", arguments: [], timeout: 1,
                                                     onSpawn: { pid = $0 })) {
            XCTAssertEqual($0 as? HardwareReason, .commandFailed)
        }
        assertReaped(pid)
    }

    func testInvalidUTF8IsNotAcceptedAsAStatusReply() {
        XCTAssertThrowsError(try HardwareCommand.run("/usr/bin/printf", arguments: ["\\377"])) {
            XCTAssertEqual($0 as? HardwareReason, .commandFailed)
        }
    }

    func testEarlyOutputEOFDoesNotReplaceWaitingForTheChild() {
        var pid: pid_t = 0
        XCTAssertThrowsError(try HardwareCommand.run("/bin/sh", arguments: ["-c", "exec 1>&-; exec /bin/sleep 5"],
                                                     timeout: 0.03, onSpawn: { pid = $0 })) {
            XCTAssertEqual($0 as? HardwareReason, .commandFailed)
        }
        assertReaped(pid)
    }

    func testMissingChildStatusIsRejectedAfterAnotherWaiterReapsIt() {
        var pid: pid_t = 0
        XCTAssertThrowsError(try HardwareCommand.run("/usr/bin/true", arguments: [], onSpawn: {
            pid = $0
            var status: Int32 = 0
            XCTAssertEqual(waitpid(pid, &status, 0), pid)
        })) { XCTAssertEqual($0 as? HardwareReason, .commandFailed) }
        assertReaped(pid)
    }

    func testSpawnFailureDoesNotLeakDescriptors() throws {
        _ = try HardwareCommand.run("/usr/bin/true", arguments: [])
        let before = openDescriptors()
        let missing = FileManager.default.temporaryDirectory.appendingPathComponent("missing-\(UUID().uuidString)").path
        for _ in 0..<40 {
            XCTAssertThrowsError(try HardwareCommand.run(missing, arguments: [])) {
                XCTAssertEqual($0 as? HardwareReason, .commandFailed)
            }
        }
        XCTAssertEqual(openDescriptors(), before)
    }

    func testExpiredDeadlineAfterExternalReapIsRejected() {
        var pid: pid_t = 0
        XCTAssertThrowsError(try HardwareCommand.run("/usr/bin/true", arguments: [], timeout: 0.03, onSpawn: {
            pid = $0
            var status: Int32 = 0
            XCTAssertEqual(waitpid(pid, &status, 0), pid)
            usleep(40_000)
        })) { XCTAssertEqual($0 as? HardwareReason, .commandFailed) }
        assertReaped(pid)
    }

    func testEmbeddedNullAndUnboundedTimeoutAreRejectedBeforeSpawn() {
        var spawned = false
        for timeout in [0, -1, Double.nan, Double.infinity, 4] {
            XCTAssertThrowsError(try HardwareCommand.run("/usr/bin/true", arguments: [], timeout: timeout,
                                                         onSpawn: { _ in spawned = true }))
        }
        XCTAssertThrowsError(try HardwareCommand.run("/usr/bin/true", arguments: ["bad\0argument"],
                                                     onSpawn: { _ in spawned = true }))
        XCTAssertFalse(spawned)
    }

    private func openDescriptors() -> Set<Int32> {
        Set((0..<getdtablesize()).filter { fcntl($0, F_GETFD) >= 0 })
    }

    private func assertReaped(_ pid: pid_t, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertGreaterThan(pid, 0, file: file, line: line)
        guard pid > 0 else { return }
        var status: Int32 = 0
        let result = waitpid(pid, &status, WNOHANG)
        let error = errno
        XCTAssertEqual(result, -1, file: file, line: line)
        XCTAssertEqual(error, ECHILD, file: file, line: line)
    }
}
