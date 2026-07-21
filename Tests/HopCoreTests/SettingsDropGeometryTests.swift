import CoreGraphics
import XCTest
@testable import HopCore

final class SettingsDropGeometryTests: XCTestCase {

    /// A stacked chip 100 wide / 20 tall at the given top-left.
    private func chip(_ x: CGFloat, _ y: CGFloat) -> CGRect {
        CGRect(x: x, y: y, width: 100, height: 20)
    }

    // MARK: - stacked (space columns)

    // The dragged key is excluded from the sibling scan: dropping "b" below all
    // three lands after a and c (count 2), NOT after itself too (count 3).
    func testStackedExcludesDraggedKey() {
        let frames = ["a": chip(0, 0), "b": chip(0, 20), "c": chip(0, 40)]
        let idx = SettingsDropGeometry.insertIndex(
            point: CGPoint(x: 50, y: 100), keys: ["a", "b", "c"],
            excluding: "b", frames: frames, flow: .stacked)
        XCTAssertEqual(idx, 2)
    }

    func testStackedEmptyColumnReturnsZero() {
        let idx = SettingsDropGeometry.insertIndex(
            point: CGPoint(x: 10, y: 10), keys: [],
            excluding: "x", frames: [:], flow: .stacked)
        XCTAssertEqual(idx, 0)
    }

    // Dropped above every chip's midpoint → index clamps to the front (0).
    func testStackedAboveAllReturnsZero() {
        let frames = ["a": chip(0, 0), "b": chip(0, 20)]
        let idx = SettingsDropGeometry.insertIndex(
            point: CGPoint(x: 50, y: -5), keys: ["a", "b"],
            excluding: "x", frames: frames, flow: .stacked)
        XCTAssertEqual(idx, 0)
    }

    // Dropped below every chip → index equals the sibling count (the end).
    func testStackedBelowAllReturnsCount() {
        let frames = ["a": chip(0, 0), "b": chip(0, 20)]
        let idx = SettingsDropGeometry.insertIndex(
            point: CGPoint(x: 50, y: 999), keys: ["a", "b"],
            excluding: "x", frames: frames, flow: .stacked)
        XCTAssertEqual(idx, 2)
    }

    // A sibling whose frame has not arrived yet is skipped (treated as below).
    func testStackedMissingFrameIsSkipped() {
        let frames = ["a": chip(0, 0)]   // "b" has no frame yet
        let idx = SettingsDropGeometry.insertIndex(
            point: CGPoint(x: 50, y: 100), keys: ["a", "b"],
            excluding: "x", frames: frames, flow: .stacked)
        XCTAssertEqual(idx, 1)
    }

    // MARK: - wrapping (inactive bucket)

    // Reading order: earlier rows always count; the same row counts only chips
    // to the left of the point.
    func testWrappingCountsEarlierRowsAndLeftInSameRow() {
        let frames = ["a": CGRect(x: 0, y: 0, width: 100, height: 20),
                      "b": CGRect(x: 110, y: 0, width: 100, height: 20),
                      "c": CGRect(x: 0, y: 30, width: 100, height: 20)]
        // point in row 2, far left: a and b are earlier rows, c is same row to the right
        let idx = SettingsDropGeometry.insertIndex(
            point: CGPoint(x: 5, y: 40), keys: ["a", "b", "c"],
            excluding: "x", frames: frames, flow: .wrapping)
        XCTAssertEqual(idx, 2)
    }

    func testWrappingMissingFrameIsNotCounted() {
        let frames = ["a": CGRect(x: 0, y: 0, width: 100, height: 20)]   // "b" missing
        let idx = SettingsDropGeometry.insertIndex(
            point: CGPoint(x: 5, y: 40), keys: ["a", "b"],
            excluding: "x", frames: frames, flow: .wrapping)
        XCTAssertEqual(idx, 1)
    }
}
