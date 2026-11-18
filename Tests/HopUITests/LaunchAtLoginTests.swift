import XCTest
@testable import Hop

@MainActor
final class LaunchAtLoginTests: XCTestCase {
    private final class System: @unchecked Sendable {
        private let lock = NSLock()
        private var value = false
        var failWrites = false
        private var started = false
        var firstWriteStarted: Bool { lock.lock(); defer { lock.unlock() }; return started }
        let releaseFirstWrite = DispatchSemaphore(value: 0)
        var blockFirstWrite = false
        private var writes = 0
        var enabled: Bool { lock.lock(); defer { lock.unlock() }; return value }
        func write(_ on: Bool) throws {
            lock.lock(); writes += 1; let index = writes; lock.unlock()
            if blockFirstWrite, index == 1 {
                lock.lock(); started = true; lock.unlock()
                releaseFirstWrite.wait()
            }
            if failWrites { throw NSError(domain: "test", code: 1) }
            lock.lock(); value = on; lock.unlock()
        }
    }

    func testTheSwitchStateIsPublishedBeforeTheSystemAnswers() async {
        let system = System()
        let login = LaunchAtLogin(isEnabled: { system.enabled }, apply: { try system.write($0) })
        system.blockFirstWrite = true
        let task = Task { await login.set(true) }
        while !system.firstWriteStarted { await Task.yield() }
        XCTAssertEqual(login.known, true)
        XCTAssertFalse(system.enabled)
        system.releaseFirstWrite.signal()
        let result = await task.value
        XCTAssertEqual(result, true)
        XCTAssertTrue(system.enabled)
    }

    func testARefusedChangeReportsTheActualState() async {
        let system = System()
        system.failWrites = true
        let login = LaunchAtLogin(isEnabled: { system.enabled }, apply: { try system.write($0) })
        let result = await login.set(true)
        XCTAssertEqual(result, false)
        XCTAssertEqual(login.known, false)
    }

    func testAnObsoleteReplyNeverOverwritesANewerChange() async {
        let system = System()
        system.blockFirstWrite = true
        let login = LaunchAtLogin(isEnabled: { system.enabled }, apply: { try system.write($0) })
        let first = Task { await login.set(true) }
        while !system.firstWriteStarted { await Task.yield() }
        let second = Task { await login.set(false) }
        while login.known != false { await Task.yield() }
        system.releaseFirstWrite.signal()
        let firstResult = await first.value
        let secondResult = await second.value
        XCTAssertNil(firstResult)
        XCTAssertEqual(secondResult, false)
        XCTAssertEqual(login.known, false)
    }
}
