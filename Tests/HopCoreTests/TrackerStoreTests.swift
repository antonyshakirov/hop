import XCTest
@testable import HopCore

final class TrackerStoreTests: XCTestCase {
    private var dir: URL!

    override func setUp() {
        super.setUp()
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("TrackerStoreTests-\(UUID().uuidString)")
        try! FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: dir)
        dir = nil
        super.tearDown()
    }

    func testLoadFromEmptyDirectoryReturnsEmpty() {
        XCTAssertEqual(TrackerStore.load(from: dir), .empty)
    }

    func testSaveThenLoadRoundTrips() throws {
        let project = TrackerProject(name: "Hop")
        let task = TrackerTask(projectID: project.id, name: "Ship 1.5")
        let interval = TrackerInterval(
            taskID: task.id,
            start: Date(timeIntervalSinceReferenceDate: 1_000),
            end: Date(timeIntervalSinceReferenceDate: 2_000)
        )
        let correction = TrackerCorrection(taskID: task.id, day: Date(timeIntervalSinceReferenceDate: 0), seconds: 60)
        let data = TrackerData(projects: [project], tasks: [task], intervals: [interval], corrections: [correction])

        try TrackerStore.save(data, to: dir)

        XCTAssertEqual(TrackerStore.load(from: dir), data)
    }

    func testOpenIntervalSurvivesRoundTrip() throws {
        let task = TrackerTask(projectID: UUID(), name: "Task")
        let openInterval = TrackerInterval(taskID: task.id, start: Date(timeIntervalSinceReferenceDate: 1_000))
        let data = TrackerData(projects: [], tasks: [task], intervals: [openInterval], corrections: [])

        try TrackerStore.save(data, to: dir)
        let loaded = TrackerStore.load(from: dir)

        XCTAssertNil(loaded.intervals.first?.end)
        XCTAssertEqual(loaded, data)
    }

    func testLoadOfGarbageBytesReturnsEmptyAndBacksUpTheFile() throws {
        let fileURL = dir.appendingPathComponent("tracker.json")
        let garbage = Data([0xFF, 0x00, 0xDE, 0xAD, 0xBE, 0xEF])
        try garbage.write(to: fileURL)

        let loaded = TrackerStore.load(from: dir)

        XCTAssertEqual(loaded, .empty)
        let bakURL = dir.appendingPathComponent("tracker.json.bak")
        XCTAssertTrue(FileManager.default.fileExists(atPath: bakURL.path))
        XCTAssertEqual(try Data(contentsOf: bakURL), garbage)
        XCTAssertFalse(FileManager.default.fileExists(atPath: fileURL.path))
    }

    func testLoadOfGarbageBytesReplacesAnOlderBackup() throws {
        let fileURL = dir.appendingPathComponent("tracker.json")
        let bakURL = dir.appendingPathComponent("tracker.json.bak")
        try Data("stale backup".utf8).write(to: bakURL)
        let garbage = Data([0x01, 0x02, 0x03])
        try garbage.write(to: fileURL)

        let loaded = TrackerStore.load(from: dir)

        XCTAssertEqual(loaded, .empty)
        XCTAssertEqual(try Data(contentsOf: bakURL), garbage)
    }
}
