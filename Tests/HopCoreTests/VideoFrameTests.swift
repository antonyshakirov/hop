import XCTest
@testable import HopCore

final class VideoFrameTests: XCTestCase {
    private func layout(
        _ width: Double, _ height: Double, _ shape: VideoFrame.Shape,
        _ shortSide: Double?, _ fit: VideoFrame.Fit = .fill
    ) -> VideoFrame.Layout? {
        VideoFrame.layout(sourceWidth: width, sourceHeight: height,
                          shape: shape, shortSide: shortSide, fit: fit)
    }

    // MARK: - The frame a platform asks for

    func testAReelFrameIsTallWhicheverWayTheSourceRuns() {
        let fromLandscape = layout(3840, 2160, .vertical, 1080)
        XCTAssertEqual(fromLandscape?.width, 1080)
        XCTAssertEqual(fromLandscape?.height, 1920)
        let fromVertical = layout(2160, 3840, .vertical, 1080)
        XCTAssertEqual(fromVertical?.width, 1080)
        XCTAssertEqual(fromVertical?.height, 1920)
    }

    func testTheOtherThreeShapes() {
        XCTAssertEqual(layout(3840, 2160, .portrait, 1080)?.height, 1350)
        XCTAssertEqual(layout(3840, 2160, .square, 1080)?.height, 1080)
        XCTAssertEqual(layout(3840, 2160, .square, 1080)?.width, 1080)
        let wide = layout(3840, 2160, .landscape, 1080)
        XCTAssertEqual(wide?.width, 1920)
        XCTAssertEqual(wide?.height, 1080)
    }

    func testFrameSidesAreEvenBecauseEncodersRefuseOddOnes() {
        for shape in VideoFrame.Shape.allCases where shape != .source {
            for side in [539.0, 721, 1081] {
                guard let layout = layout(3840, 2160, shape, side) else { continue }
                XCTAssertEqual(layout.width.truncatingRemainder(dividingBy: 2), 0)
                XCTAssertEqual(layout.height.truncatingRemainder(dividingBy: 2), 0)
            }
        }
    }

    // MARK: - What happens to a picture of the wrong shape

    func testFillingCoversTheFrameAndPushesTheEdgesOut() {
        // a 16:9 picture in a 9:16 frame: nothing is invented, so the frame is
        // as tall as the source and the sides are cropped away
        let layout = layout(1920, 1080, .vertical, 1080, .fill)
        XCTAssertEqual(layout?.height, 1080)
        XCTAssertEqual((layout?.width ?? 0) / (layout?.height ?? 1), 9.0 / 16, accuracy: 0.01)
        XCTAssertEqual(layout?.scale ?? 0, 1, accuracy: 0.001)
        XCTAssertLessThan(layout?.offsetX ?? 0, 0)
        XCTAssertEqual(layout?.offsetY ?? -1, 0, accuracy: 0.5)
        XCTAssertEqual(layout?.hasEmptySpace, false)
    }

    func testPaddingShowsEverythingAndLeavesSpace() {
        let layout = layout(1920, 1080, .vertical, 1080, .pad)
        XCTAssertEqual(layout?.scale ?? 0, 1080 / 1920, accuracy: 0.001)
        XCTAssertEqual(layout?.offsetX ?? -1, 0, accuracy: 0.5)
        XCTAssertGreaterThan(layout?.offsetY ?? 0, 0)
        XCTAssertEqual(layout?.hasEmptySpace, true)
    }

    func testBlurLeavesTheSameSpaceAsPadding() {
        // the two differ only in what goes in the space, never in the geometry
        let padded = layout(1920, 1080, .vertical, 1080, .pad)
        let blurred = layout(1920, 1080, .vertical, 1080, .blur)
        XCTAssertEqual(padded, blurred)
    }

    func testAPictureAlreadyOfTheRightShapeIsSimplyResized() {
        let layout = layout(2160, 3840, .vertical, 1080, .fill)
        XCTAssertEqual(layout?.width, 1080)
        XCTAssertEqual(layout?.height, 1920)
        XCTAssertEqual(layout?.offsetX ?? -1, 0, accuracy: 0.5)
        XCTAssertEqual(layout?.offsetY ?? -1, 0, accuracy: 0.5)
    }

    // MARK: - Never inventing pixels

    func testAFrameLargerThanTheSourceShrinksToWhatTheSourceCanFill() {
        // 720p footage asked for a 1080-wide reel: the shape is kept, the size
        // is whatever the source can honestly fill
        let layout = layout(1280, 720, .vertical, 1080, .fill)
        XCTAssertEqual((layout?.width ?? 0) / (layout?.height ?? 1), 9.0 / 16, accuracy: 0.01)
        XCTAssertLessThanOrEqual(layout?.height ?? 0, 720)
        XCTAssertLessThanOrEqual(layout?.scale ?? 2, 1.001)
    }

    func testPaddingNeverUpscalesEither() {
        let layout = layout(640, 360, .square, 1080, .pad)
        XCTAssertLessThanOrEqual(layout?.scale ?? 2, 1.001)
        XCTAssertEqual(layout?.width, layout?.height)
    }

    // MARK: - Leaving the shape alone

    func testTheSourceShapeOnlyEverDownscales() {
        let smaller = layout(1920, 1080, .source, 720)
        XCTAssertEqual(smaller?.width, 1280)
        XCTAssertEqual(smaller?.height, 720)
        XCTAssertEqual(smaller?.offsetX, 0)
    }

    func testNothingToDoWhenTheSourceIsAlreadySmallEnough() {
        XCTAssertNil(layout(1280, 720, .source, 1080))
        XCTAssertNil(layout(1280, 720, .source, nil))
    }

    func testAnEmptySourceHasNoLayout() {
        XCTAssertNil(layout(0, 0, .vertical, 1080))
        XCTAssertNil(layout(1920, 0, .square, 1080))
    }
}
