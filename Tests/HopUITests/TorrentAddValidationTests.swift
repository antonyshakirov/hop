import XCTest
@testable import Hop
import HopCore

final class TorrentAddValidationTests: XCTestCase {
    @MainActor
    func testInvalidSelectionIsRejectedWithoutAnEngine() async {
        let controller = TorrentController()
        let pending = TorrentController.PendingAdd(source: .file(Data()), name: "test", files: [
            TorrentFile(index: 0, name: "one.bin", lengthBytes: 10, selected: true),
            TorrentFile(index: 1, name: "two.bin", lengthBytes: 10, selected: true),
        ])
        for selection: Set<Int> in [[], [-1], [2], [0, 2]] {
            do {
                try await controller.confirmAdd(pending, selectedIndices: selection)
                XCTFail("Invalid selection was accepted")
            } catch {
                XCTAssertEqual(error as? TorrentEngineClient.EngineError, .invalidSelection)
            }
            XCTAssertTrue(controller.torrents.isEmpty)
        }
    }
}
