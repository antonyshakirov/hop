import CoreGraphics
import XCTest
@testable import HopCore

final class SettingsDropGeometryTests: XCTestCase {

    /// A stacked chip 100 wide / 20 tall at the given top-left.
    private func chip(_ x: CGFloat, _ y: CGFloat) -> CGRect {
        CGRect(x: x, y: y, width: 100, height: 20)
    }

    // MARK: - insertIndex (every column stacks)

    // The dragged key is excluded from the sibling scan: dropping "b" below all
    // three lands after a and c (count 2), NOT after itself too (count 3).
    func testStackedExcludesDraggedKey() {
        let frames = ["a": chip(0, 0), "b": chip(0, 20), "c": chip(0, 40)]
        let idx = SettingsDropGeometry.insertIndex(
            point: CGPoint(x: 50, y: 100), keys: ["a", "b", "c"],
            excluding: "b", frames: frames)
        XCTAssertEqual(idx, 2)
    }

    func testStackedEmptyColumnReturnsZero() {
        let idx = SettingsDropGeometry.insertIndex(
            point: CGPoint(x: 10, y: 10), keys: [],
            excluding: "x", frames: [:])
        XCTAssertEqual(idx, 0)
    }

    // Dropped above every chip's midpoint → index clamps to the front (0).
    func testStackedAboveAllReturnsZero() {
        let frames = ["a": chip(0, 0), "b": chip(0, 20)]
        let idx = SettingsDropGeometry.insertIndex(
            point: CGPoint(x: 50, y: -5), keys: ["a", "b"],
            excluding: "x", frames: frames)
        XCTAssertEqual(idx, 0)
    }

    // Dropped below every chip → index equals the sibling count (the end).
    func testStackedBelowAllReturnsCount() {
        let frames = ["a": chip(0, 0), "b": chip(0, 20)]
        let idx = SettingsDropGeometry.insertIndex(
            point: CGPoint(x: 50, y: 999), keys: ["a", "b"],
            excluding: "x", frames: frames)
        XCTAssertEqual(idx, 2)
    }

    // A sibling whose frame has not arrived yet is skipped (treated as below).
    func testStackedMissingFrameIsSkipped() {
        let frames = ["a": chip(0, 0)]   // "b" has no frame yet
        let idx = SettingsDropGeometry.insertIndex(
            point: CGPoint(x: 50, y: 100), keys: ["a", "b"],
            excluding: "x", frames: frames)
        XCTAssertEqual(idx, 1)
    }

    // The inactive column resolves its own insert index exactly like a space
    // column — one shared stacked resolver, no separate wrapping flow.
    func testInactiveColumnUsesTheSameStackedResolver() {
        let frames = ["a": chip(0, 0), "b": chip(0, 20)]
        let idx = SettingsDropGeometry.insertIndex(
            point: CGPoint(x: 50, y: 25), keys: ["a", "b"],
            excluding: "x", frames: frames)
        XCTAssertEqual(idx, 1, "past a's midpoint, before b's → index 1")
    }

    // MARK: - columnID (column hit-testing, inactive is a regular column)

    // A 60-wide column at x (three columns side by side: inactive | s1 | s2).
    private func column(_ x: CGFloat) -> CGRect {
        CGRect(x: x, y: 0, width: 60, height: 200)
    }

    func testColumnContainingPointWins() {
        let frames = ["inactive": column(0), "s1": column(70), "s2": column(140)]
        let hit = SettingsDropGeometry.columnID(at: CGPoint(x: 80, y: 30), frames: frames)
        XCTAssertEqual(hit, "s1")
    }

    // A point inside the FIRST (inactive) column lands in it — proving inactive
    // is a real drop target again, not excluded.
    func testFirstColumnInactiveIsAHittableTarget() {
        let frames = ["inactive": column(0), "s1": column(70), "s2": column(140)]
        let hit = SettingsDropGeometry.columnID(at: CGPoint(x: 30, y: 30), frames: frames)
        XCTAssertEqual(hit, "inactive")
    }

    // No vertical-band code: a point BELOW every column's frame (low, past their
    // maxY) snaps to the nearest by X — it is NOT forced to inactive.
    func testBelowAllColumnsSnapsByXNotToInactive() {
        let frames = ["inactive": column(0), "s1": column(70), "s2": column(140)]
        let hit = SettingsDropGeometry.columnID(at: CGPoint(x: 150, y: 999), frames: frames)
        XCTAssertEqual(hit, "s2")
    }

    // Nearest-by-X off to the far left resolves to the inactive (leftmost) column.
    func testNearestByXPastTheLeftEdgeIsInactive() {
        let frames = ["inactive": column(0), "s1": column(70), "s2": column(140)]
        let hit = SettingsDropGeometry.columnID(at: CGPoint(x: -50, y: 30), frames: frames)
        XCTAssertEqual(hit, "inactive")
    }

    func testNoColumnsReturnsNil() {
        XCTAssertNil(SettingsDropGeometry.columnID(at: CGPoint(x: 5, y: 5), frames: [:]))
    }
}
