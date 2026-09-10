import XCTest
@testable import HopCore

/// The first loupe on the drawing layer sat black inside its rim for half a
/// second: the stream was still coming up, and there was nothing else to read.
final class BackdropPicturesTests: XCTestCase {

    func testADisplayWithNothingTakenReadsNothing() {
        let pictures = BackdropPictures<String>()
        XCTAssertNil(pictures[1])
        XCTAssertFalse(pictures.isLive(1))
    }

    func testAStillIsReadUntilTheFirstStreamedFrameReplacesIt() {
        var pictures = BackdropPictures<String>()
        XCTAssertTrue(pictures.took(still: "still", on: 1, in: pictures.session))
        XCTAssertEqual(pictures[1], "still")
        XCTAssertFalse(pictures.isLive(1))
        pictures.streamed("live", on: 1)
        XCTAssertEqual(pictures[1], "live")
        XCTAssertTrue(pictures.isLive(1))
    }

    func testAStillThatLandsAfterTheFirstFrameIsDropped() {
        var pictures = BackdropPictures<String>()
        let session = pictures.session
        pictures.streamed("live", on: 1)
        XCTAssertFalse(pictures.took(still: "late", on: 1, in: session))
        XCTAssertEqual(pictures[1], "live")
    }

    func testAStreamStoppedByChoiceLeavesItsLastFrameAsTheStill() {
        var pictures = BackdropPictures<String>()
        pictures.streamed("live", on: 1)
        pictures.paused(1)
        XCTAssertEqual(pictures[1], "live")
        XCTAssertFalse(pictures.isLive(1))
        XCTAssertTrue(pictures.took(still: "newer", on: 1, in: pictures.session))
        XCTAssertEqual(pictures[1], "newer")
    }

    /// SPEC: docs/spec.md — a stream that DIED drops its last frame.
    func testAForgottenDisplayReadsNothing() {
        var pictures = BackdropPictures<String>()
        pictures.streamed("live", on: 1)
        pictures.forget(1)
        XCTAssertNil(pictures[1])
    }

    func testDisplaysKeepTheirOwnPictures() {
        var pictures = BackdropPictures<String>()
        pictures.took(still: "one", on: 1, in: pictures.session)
        pictures.streamed("two", on: 2)
        XCTAssertEqual(pictures[1], "one")
        XCTAssertEqual(pictures[2], "two")
        pictures.forget(2)
        XCTAssertEqual(pictures[1], "one")
    }

    func testAStillTakenBeforeTheLayerClosedIsNeverReadAfter() {
        var pictures = BackdropPictures<String>()
        let before = pictures.session
        pictures.forgetAll()
        XCTAssertFalse(pictures.took(still: "stale", on: 1, in: before))
        XCTAssertNil(pictures[1])
    }
}
