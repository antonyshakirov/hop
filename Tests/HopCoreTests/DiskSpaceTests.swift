import XCTest
@testable import HopCore

final class DiskSpaceTests: XCTestCase {
    func testFitsBoundary() {
        XCTAssertTrue(DiskSpace.fits(requiredBytes: 100, availableBytes: 100))
        XCTAssertTrue(DiskSpace.fits(requiredBytes: 100, availableBytes: 101))
        XCTAssertFalse(DiskSpace.fits(requiredBytes: 100, availableBytes: 99))
    }
    func testRequiredSumsSelectedOnly() {
        let files = [
            TorrentFile(index: 0, name: "a", lengthBytes: 100, selected: true),
            TorrentFile(index: 1, name: "b", lengthBytes: 50, selected: false),
            TorrentFile(index: 2, name: "c", lengthBytes: 25, selected: true),
        ]
        XCTAssertEqual(DiskSpace.required(for: files), 125)
    }
}
