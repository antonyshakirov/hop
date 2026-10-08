import XCTest
@testable import HopCore

final class MediaSizeTests: XCTestCase {
    func testMultiplePassesCountEveryInferenceTile() {
        XCTAssertEqual(MediaSize(width: 32, height: 16).inferenceTiles(to: MediaSize(width: 7680, height: 3840)), 74)
        XCTAssertEqual(MediaSize(width: Int.max, height: Int.max).inferenceTiles(to: MediaSize(width: 7680, height: 4320)), 0)
    }

    func testSmallImageCanReachEightKWithoutFactorLimit() {
        XCTAssertEqual(MediaSize(width: 320, height: 180).output(for: .eightK), MediaSize(width: 7680, height: 4320))
    }

    func testFourKOnlyOffersEightKTarget() {
        XCTAssertEqual(MediaSize(width: 3840, height: 2160).choices, [.double, .eightK])
    }

    func testPortraitUsesPortraitBounds() {
        XCTAssertEqual(MediaSize(width: 1080, height: 1920).output(for: .eightK), MediaSize(width: 4320, height: 7680))
    }

    func testSquareAndUltrawideKeepTheirShape() {
        XCTAssertEqual(MediaSize(width: 500, height: 500).output(for: .eightK), MediaSize(width: 4320, height: 4320))
        XCTAssertEqual(MediaSize(width: 1000, height: 250).output(for: .eightK), MediaSize(width: 7680, height: 1920))
    }

    func testEqualSmallerAndOverCapChoicesDisappear() {
        let source = MediaSize(width: 4000, height: 2250)
        XCTAssertEqual(source.choices, [.eightK])
        XCTAssertTrue(MediaSize(width: 7680, height: 4320).choices.isEmpty)
        XCTAssertTrue(MediaSize(width: 9000, height: 5000).choices.isEmpty)
        XCTAssertNil(source.output(for: .double))
    }

    func testInvalidAndOverflowSizesCannotAllocate() {
        for size in [MediaSize(width: 0, height: 100), MediaSize(width: -1, height: 10), MediaSize(width: .max, height: .max)] {
            XCTAssertTrue(size.choices.isEmpty)
            XCTAssertNil(size.rgbaBytes)
        }
    }

    func testOddSizesNeverStretchByMoreThanRounding() {
        let source = MediaSize(width: 731, height: 997)
        let out = source.output(for: .fourK)!
        XCTAssertLessThanOrEqual(out.width, 2160)
        XCTAssertLessThanOrEqual(out.height, 3840)
        XCTAssertEqual(Double(out.width) / Double(out.height), 731.0 / 997, accuracy: 0.001)
    }

    func testTileCoverageIsExactAtPartialEdges() {
        let size = MediaSize(width: 401, height: 203)
        let tiles = MediaTiles.tiles(for: size)
        var covered = Set<Int>()
        for tile in tiles {
            XCTAssertLessThanOrEqual(tile.width, MediaTiles.core)
            XCTAssertLessThanOrEqual(tile.height, MediaTiles.core)
            for y in tile.y..<(tile.y + tile.height) {
                for x in tile.x..<(tile.x + tile.width) {
                    XCTAssertTrue(covered.insert(y * size.width + x).inserted)
                }
            }
        }
        XCTAssertEqual(covered.count, size.width * size.height)
    }
}
