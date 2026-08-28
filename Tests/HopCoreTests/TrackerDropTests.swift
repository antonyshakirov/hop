import XCTest
@testable import HopCore

final class TrackerDropTests: XCTestCase {
    // A list that looks like this on screen (rows 26pt apart):
    //   0  loose1            (top level task)
    //   1  ▾ project         (unfolded)
    //   2      inside1
    //   3      inside2
    //   4  loose2            (top level task)
    private let loose1 = UUID(), project = UUID(), inside1 = UUID()
    private let inside2 = UUID(), loose2 = UUID()

    private func rows(expanded: Bool = true) -> [TrackerDrop.Row] {
        var rows: [TrackerDrop.Row] = [
            .init(id: loose1, midY: 10),
            .init(id: project, isProject: true, isExpanded: expanded, midY: 36),
        ]
        if expanded {
            rows.append(.init(id: inside1, parent: project, midY: 62))
            rows.append(.init(id: inside2, parent: project, midY: 88))
        }
        rows.append(.init(id: loose2, midY: expanded ? 114 : 62))
        return rows
    }

    private func target(_ dragged: UUID, isProject: Bool = false, at y: Double,
                        expanded: Bool = true) -> TrackerDrop.Target {
        TrackerDrop.target(rows: rows(expanded: expanded), dragging: dragged,
                           isProject: isProject, at: y)
    }

    // MARK: - Tasks

    func testDroppingAboveEverythingLandsFirstAtTheTopLevel() {
        XCTAssertEqual(target(loose2, at: 2), TrackerDrop.Target(parent: nil, index: 0))
    }

    func testDroppingJustBelowAnUnfoldedProjectGoesInsideItFirst() {
        XCTAssertEqual(target(loose1, at: 50), TrackerDrop.Target(parent: project, index: 0))
    }

    func testDroppingBetweenTwoOfAProjectsTasksGoesInsideIt() {
        XCTAssertEqual(target(loose1, at: 75), TrackerDrop.Target(parent: project, index: 1))
    }

    func testDroppingBelowAProjectsLastTaskStaysInsideIt() {
        // the row above the pointer belongs to the project, so this is "last in
        // the project" — leaving it is done above the project or below a row
        // that belongs to nobody
        XCTAssertEqual(target(loose1, at: 100), TrackerDrop.Target(parent: project, index: 2))
    }

    func testDroppingBelowALooseTaskStaysAtTheTopLevel() {
        // last of the three top-level rows: loose1, the project, loose2
        XCTAssertEqual(target(inside1, at: 130), TrackerDrop.Target(parent: nil, index: 3))
    }

    func testDroppingUnderAFoldedProjectStaysAtTheTopLevel() {
        // nothing of the project is on screen, so under it means after it
        XCTAssertEqual(target(loose2, isProject: false, at: 50, expanded: false),
                       TrackerDrop.Target(parent: nil, index: 2))
    }

    func testATaskLeavesItsProjectByGoingAboveIt() {
        XCTAssertEqual(target(inside2, at: 20), TrackerDrop.Target(parent: nil, index: 1))
    }

    func testTheDraggedTaskIsNotItsOwnLandmark() {
        // dragging inside1 down past inside2: the answer counts inside2 only
        XCTAssertEqual(target(inside1, at: 100), TrackerDrop.Target(parent: project, index: 1))
    }

    func testDroppingOnAProjectsOwnRowGoesInsideIt() {
        // the pointer is on the project line itself, not between lines
        XCTAssertEqual(target(loose1, at: 36), TrackerDrop.Target(parent: project, index: 0))
    }

    func testAFoldedProjectStillTakesADropOnItsRow() {
        // nothing of it is on screen to aim between, so its own row is the way in
        XCTAssertEqual(target(loose2, at: 36, expanded: false),
                       TrackerDrop.Target(parent: project, index: 0))
    }

    func testJustBelowAFoldedProjectIsStillTheTopLevel() {
        // one row further down and it is an ordinary top-level drop again
        XCTAssertEqual(target(loose2, at: 55, expanded: false),
                       TrackerDrop.Target(parent: nil, index: 2))
    }

    func testAProjectDroppedOnAnotherProjectsRowStaysAtTheTopLevel() {
        // projects do not nest, so the "into it" rule is for tasks only
        XCTAssertEqual(target(project, isProject: true, at: 10),
                       TrackerDrop.Target(parent: nil, index: 0))
    }

    // MARK: - Projects

    func testAProjectAlwaysLandsAtTheTopLevel() {
        // pointer sits between the project's own two tasks, and a project still
        // cannot go inside a project
        XCTAssertEqual(target(project, isProject: true, at: 75),
                       TrackerDrop.Target(parent: nil, index: 1))
    }

    func testAProjectCarriesItsTasksSoTheyAreNotLandmarks() {
        // below everything: only loose1 and loose2 count, so the project lands last
        XCTAssertEqual(target(project, isProject: true, at: 200),
                       TrackerDrop.Target(parent: nil, index: 2))
    }

    func testAProjectDroppedAtTheTopGoesFirst() {
        XCTAssertEqual(target(project, isProject: true, at: 2),
                       TrackerDrop.Target(parent: nil, index: 0))
    }

    // MARK: - Degenerate input

    func testAnEmptyListTakesTheFirstSlot() {
        XCTAssertEqual(TrackerDrop.target(rows: [], dragging: loose1, isProject: false, at: 40),
                       TrackerDrop.Target(parent: nil, index: 0))
    }
}
