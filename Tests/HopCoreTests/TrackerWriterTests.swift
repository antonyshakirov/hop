import XCTest
@testable import HopCore

final class TrackerWriterTests: XCTestCase {
    private final class Log: @unchecked Sendable {
        private let lock = NSLock()
        private var items: [Int] = []
        let started = DispatchSemaphore(value: 0)
        let release = DispatchSemaphore(value: 0)
        var blockFirst = false
        func add(_ value: Int) {
            lock.lock(); let first = items.isEmpty; items.append(value); lock.unlock()
            if first, blockFirst { started.signal(); release.wait() }
        }
        var values: [Int] { lock.lock(); defer { lock.unlock() }; return items }
    }

    private func data(_ marker: Int) -> TrackerData {
        var value = TrackerData.empty
        value.projects = [TrackerProject(name: "p\(marker)")]
        return value
    }

    func testTheLastWriteWinsAndWritesNeverReorder() {
        let log = Log()
        log.blockFirst = true
        let writer = TrackerWriter(directory: FileManager.default.temporaryDirectory,
                                   save: { data, _ in log.add(Int(data.projects[0].name.dropFirst()) ?? -1) })
        writer.write(data(1))
        XCTAssertEqual(log.started.wait(timeout: .now() + 5), .success)
        for value in 2...6 { writer.write(data(value)) }
        log.release.signal()
        writer.flush()
        XCTAssertEqual(log.values.first, 1)
        XCTAssertEqual(log.values.last, 6)
        XCTAssertEqual(log.values, log.values.sorted())
    }

    func testAWriteReturnsBeforeTheDiskDoesAndFlushWaitsForIt() {
        let log = Log()
        log.blockFirst = true
        let writer = TrackerWriter(directory: FileManager.default.temporaryDirectory,
                                   save: { data, _ in log.add(Int(data.projects[0].name.dropFirst()) ?? -1) })
        writer.write(data(1))
        XCTAssertEqual(log.started.wait(timeout: .now() + 5), .success)
        XCTAssertEqual(log.values, [1])
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.2) { log.release.signal() }
        writer.write(data(2))
        writer.flush()
        XCTAssertEqual(log.values, [1, 2])
    }

    func testAFailedWriteIsReportedAndTheNextOneStillRuns() {
        let failures = Log()
        let saved = Log()
        let writer = TrackerWriter(directory: FileManager.default.temporaryDirectory,
            save: { data, _ in
                let number = Int(data.projects[0].name.dropFirst()) ?? -1
                if number == 1 { throw CocoaError(.fileWriteOutOfSpace) }
                saved.add(number)
            }, failed: { _ in failures.add(1) })
        writer.write(data(1)); writer.flush()
        writer.write(data(2)); writer.flush()
        XCTAssertEqual(failures.values, [1])
        XCTAssertEqual(saved.values, [2])
    }

    func testTheWrittenFileRoundTripsThroughTheStore() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("TrackerWriterTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let writer = TrackerWriter(directory: dir)
        let value = data(7)
        writer.write(value); writer.flush()
        XCTAssertEqual(TrackerStore.load(from: dir), value)
    }
}
