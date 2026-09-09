import XCTest
@testable import HopCore

/// SPEC: docs/spec.md — the presenting pointer.
final class PointerAidsTests: XCTestCase {

    func testNothingSwitchedOnIsNothingToWatch() {
        var aids = PointerAids.standard
        aids.ring = false
        aids.clicks = false
        XCTAssertFalse(aids.isOn)
        aids.trail = true
        XCTAssertTrue(aids.isOn)
    }

    func testAMarkFadesToNothingOverItsLife() {
        XCTAssertEqual(PointerAids.fade(age: 0, life: 0.5), 1)
        XCTAssertEqual(PointerAids.fade(age: 0.25, life: 0.5), 0.5, accuracy: 0.001)
        XCTAssertEqual(PointerAids.fade(age: 0.5, life: 0.5), 0)
        XCTAssertEqual(PointerAids.fade(age: 10, life: 0.5), 0, "an old mark never goes negative")
    }

    func testAClickRingGrowsWhileItFades() {
        let born = PointerAids.clickRadius(age: 0, from: 20)
        let gone = PointerAids.clickRadius(age: PointerAids.clickLife, from: 20)
        XCTAssertEqual(born, 20)
        XCTAssertGreaterThan(gone, born)
        XCTAssertEqual(gone, PointerAids.clickRadius(age: 99, from: 20), "it stops growing when it is gone")
    }

    func testTheStandardAidsAreTheQuietOnes() {
        let aids = PointerAids.standard
        XCTAssertTrue(aids.ring)
        XCTAssertTrue(aids.clicks)
        XCTAssertFalse(aids.spotlight, "dimming the whole screen is never the default")
        XCTAssertFalse(aids.trail)
    }
}
