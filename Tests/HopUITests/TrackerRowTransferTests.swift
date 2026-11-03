import AppKit
import HopCore
import XCTest
@testable import Hop

@MainActor
final class TrackerRowTransferTests: XCTestCase {
    func testNativeTransferMovesTaskIntoFoldedProjectWithoutLosingHistory() throws {
        var clock = Date(timeIntervalSince1970: 1_790_000_000)
        let engine = TrackerEngine(now: { clock })
        let task = engine.addTask(name: "Draft")
        let project = engine.addProject(name: "Launch")
        engine.setProjectExpanded(project, false)
        engine.start(taskID: task)
        clock = clock.addingTimeInterval(60)
        engine.stop(taskID: task)
        engine.set(taskID: task, period: .total, to: 120)
        let before = try XCTUnwrap(engine.data.tasks.first { $0.id == task })
        let intervals = engine.data.intervals
        let corrections = engine.data.corrections
        let session = UUID()
        let completed = expectation(description: "Native data loaded")
        let rows: [TrackerDrop.Row] = [
            .init(id: task, midY: 13),
            .init(id: project, isProject: true, midY: 42)
        ]

        XCTAssertTrue(TrackerRowTransfer.read(
            [TrackerRowTransfer.provider(row: task, session: session)], session: session
        ) { received in
            XCTAssertTrue(Thread.isMainThread)
            XCTAssertEqual(received, task)
            if let received {
                let target = TrackerDrop.target(rows: rows, dragging: received, isProject: false, at: 42)
                engine.moveTask(received, toProject: target.parent, at: target.index)
            }
            completed.fulfill()
        })
        wait(for: [completed], timeout: 3)

        let moved = try XCTUnwrap(engine.data.tasks.first { $0.id == task })
        XCTAssertEqual(moved.projectID, project)
        XCTAssertEqual(moved.id, before.id)
        XCTAssertEqual(moved.name, before.name)
        XCTAssertEqual(engine.data.intervals, intervals)
        XCTAssertEqual(engine.data.corrections, corrections)
        XCTAssertEqual(engine.amount(taskID: task, period: .total), 120)
        XCTAssertEqual(engine.tasks(in: project).map(\.id), [task])
        XCTAssertFalse(engine.data.rootOrder.contains(task))
    }

    func testTransferFromAnotherTrackerSessionIsRejected() {
        let completed = expectation(description: "Foreign data rejected")
        XCTAssertTrue(TrackerRowTransfer.read(
            [TrackerRowTransfer.provider(row: UUID(), session: UUID())], session: UUID()
        ) { row in
            XCTAssertNil(row)
            completed.fulfill()
        })
        wait(for: [completed], timeout: 3)
    }

    func testOrdinaryTextIsNotATrackerDrop() {
        XCTAssertFalse(TrackerRowTransfer.read([NSItemProvider(object: "Draft" as NSString)], session: UUID()) {
            _ in XCTFail("An external text drag must not move a task")
        })
    }

    func testMalformedAndOversizedPayloadsAreRejected() {
        let session = UUID()
        for text in ["not a task", session.uuidString + ":" + String(repeating: "x", count: 36),
                     String(repeating: "a", count: 2048)] {
            let completed = expectation(description: "Malformed data rejected")
            let provider = NSItemProvider(item: Data(text.utf8) as NSData,
                                          typeIdentifier: TrackerRowTransfer.typeIdentifier)
            XCTAssertTrue(TrackerRowTransfer.read([provider], session: session) { row in
                XCTAssertNil(row)
                completed.fulfill()
            })
            wait(for: [completed], timeout: 3)
        }
    }
}
