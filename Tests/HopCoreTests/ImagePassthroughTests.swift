import XCTest
@testable import HopCore

final class ImagePassthroughTests: XCTestCase {
    private func url(_ name: String) -> URL { URL(fileURLWithPath: "/tmp/\(name)") }

    func testTheSameFormatAtFullQualityIsACopy() {
        XCTAssertTrue(ImagePassthrough.isNoOp(source: url("photo.jpg"), format: "jpeg",
                                              scale: 1, quality: 1))
        XCTAssertTrue(ImagePassthrough.isNoOp(source: url("photo.jpeg"), format: "jpeg",
                                              scale: 1, quality: 1))
        XCTAssertTrue(ImagePassthrough.isNoOp(source: url("shot.PNG"), format: "png",
                                              scale: 1, quality: 1))
    }

    func testHeicAnswersToBothOfItsNames() {
        XCTAssertTrue(ImagePassthrough.isNoOp(source: url("a.heif"), format: "heic",
                                              scale: 1, quality: 1))
    }

    func testAskingForAnotherFormatIsNotACopy() {
        XCTAssertFalse(ImagePassthrough.isNoOp(source: url("photo.jpg"), format: "png",
                                               scale: 1, quality: 1))
    }

    func testAskingForLessQualityIsNotACopy() {
        // wanting a smaller file IS asking for something
        XCTAssertFalse(ImagePassthrough.isNoOp(source: url("photo.jpg"), format: "jpeg",
                                               scale: 1, quality: 0.9))
    }

    func testScalingIsNotACopy() {
        XCTAssertFalse(ImagePassthrough.isNoOp(source: url("photo.jpg"), format: "jpeg",
                                               scale: 0.5, quality: 1))
    }
}
