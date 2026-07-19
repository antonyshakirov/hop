import XCTest
@testable import HopCore

final class TrackerModelTests: XCTestCase {
    private let projectID = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
    private let taskID = UUID(uuidString: "22222222-2222-2222-2222-222222222222")!

    private func populatedData() -> TrackerData {
        let project = TrackerProject(id: projectID, name: "Hop", isExpanded: false)
        let task = TrackerTask(id: taskID, projectID: projectID, name: "Ship 1.4")
        let closedInterval = TrackerInterval(
            taskID: taskID,
            start: Date(timeIntervalSinceReferenceDate: 1_000),
            end: Date(timeIntervalSinceReferenceDate: 1_600)
        )
        let openInterval = TrackerInterval(taskID: taskID, start: Date(timeIntervalSinceReferenceDate: 2_000))
        let correction = TrackerCorrection(taskID: taskID, day: Date(timeIntervalSinceReferenceDate: 0), seconds: -120)
        return TrackerData(
            projects: [project],
            tasks: [task],
            intervals: [closedInterval, openInterval],
            corrections: [correction]
        )
    }

    func testDefaultInitializers() {
        let project = TrackerProject(name: "Untitled")
        XCTAssertTrue(project.isExpanded)

        let task = TrackerTask(projectID: projectID, name: "Untitled task")
        XCTAssertEqual(task.projectID, projectID)

        let interval = TrackerInterval(taskID: taskID, start: Date(timeIntervalSinceReferenceDate: 0))
        XCTAssertNil(interval.end)
    }

    func testRoundTripEncodeDecode() throws {
        let original = populatedData()
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(TrackerData.self, from: data)
        XCTAssertEqual(decoded, original)
    }

    func testOpenIntervalRoundTripsNilEnd() throws {
        let interval = TrackerInterval(taskID: taskID, start: Date(timeIntervalSinceReferenceDate: 2_000))
        let data = try JSONEncoder().encode(interval)
        let decoded = try JSONDecoder().decode(TrackerInterval.self, from: data)
        XCTAssertNil(decoded.end)
        XCTAssertEqual(decoded, interval)
    }

    // A future app version may add fields to the persisted JSON; older
    // builds must keep loading the fields they know about instead of
    // failing the whole decode.
    func testDecodeToleratesUnknownFields() throws {
        let json = """
        {
            "future": 1,
            "projects": [{"id": "\(projectID.uuidString)", "name": "Hop", "isExpanded": false}],
            "tasks": [{"id": "\(taskID.uuidString)", "projectID": "\(projectID.uuidString)", "name": "Ship 1.4"}],
            "intervals": [
                {"taskID": "\(taskID.uuidString)", "start": 1000, "end": 1600, "extra": "ignored"},
                {"taskID": "\(taskID.uuidString)", "start": 2000}
            ],
            "corrections": [{"taskID": "\(taskID.uuidString)", "day": 0, "seconds": -120}]
        }
        """
        let decoded = try JSONDecoder().decode(TrackerData.self, from: Data(json.utf8))
        XCTAssertEqual(decoded, populatedData())
    }

    func testEmptyHasAllArraysEmpty() {
        let empty = TrackerData.empty
        XCTAssertTrue(empty.projects.isEmpty)
        XCTAssertTrue(empty.tasks.isEmpty)
        XCTAssertTrue(empty.intervals.isEmpty)
        XCTAssertTrue(empty.corrections.isEmpty)
        XCTAssertTrue(empty.rootOrder.isEmpty)
    }

    // A task written with `projectID` (the old shape, every task nested) must
    // keep decoding to a nested task.
    func testDecodeNestedTaskKeepsItsProjectID() throws {
        let json = """
        {"id": "\(taskID.uuidString)", "projectID": "\(projectID.uuidString)", "name": "Ship 1.4"}
        """
        let decoded = try JSONDecoder().decode(TrackerTask.self, from: Data(json.utf8))
        XCTAssertEqual(decoded.projectID, projectID)
    }

    // A project-less root task omits `projectID` on disk and decodes to nil.
    func testDecodeRootTaskWithoutProjectIDIsNil() throws {
        let json = """
        {"id": "\(taskID.uuidString)", "name": "Root task"}
        """
        let decoded = try JSONDecoder().decode(TrackerTask.self, from: Data(json.utf8))
        XCTAssertNil(decoded.projectID)
    }

    func testRootTaskEncodesWithoutProjectIDKeyAndRoundTrips() throws {
        let task = TrackerTask(projectID: nil, name: "Root task")
        let encoded = try JSONEncoder().encode(task)
        let asString = String(decoding: encoded, as: UTF8.self)
        XCTAssertFalse(asString.contains("projectID"))
        let decoded = try JSONDecoder().decode(TrackerTask.self, from: encoded)
        XCTAssertEqual(decoded, task)
    }

    // An old file has no `rootOrder`; the decode must tolerate its absence
    // (the engine derives the order on load).
    func testDecodeToleratesMissingRootOrder() throws {
        let json = """
        {
            "projects": [{"id": "\(projectID.uuidString)", "name": "Hop", "isExpanded": true}],
            "tasks": [{"id": "\(taskID.uuidString)", "projectID": "\(projectID.uuidString)", "name": "Ship 1.4"}],
            "intervals": [],
            "corrections": []
        }
        """
        let decoded = try JSONDecoder().decode(TrackerData.self, from: Data(json.utf8))
        XCTAssertTrue(decoded.rootOrder.isEmpty)
        XCTAssertEqual(decoded.tasks.first?.projectID, projectID)
    }

    func testRootOrderRoundTrips() throws {
        var data = populatedData()
        let rootTaskID = UUID()
        data.tasks.append(TrackerTask(id: rootTaskID, projectID: nil, name: "Root"))
        data.rootOrder = [projectID, rootTaskID]
        let encoded = try JSONEncoder().encode(data)
        let decoded = try JSONDecoder().decode(TrackerData.self, from: encoded)
        XCTAssertEqual(decoded.rootOrder, [projectID, rootTaskID])
        XCTAssertEqual(decoded, data)
    }
}
