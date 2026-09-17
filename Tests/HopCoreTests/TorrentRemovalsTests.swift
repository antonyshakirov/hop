import XCTest
@testable import HopCore

final class TorrentRemovalsTests: XCTestCase {
    private let a = String(repeating: "a", count: 40)
    private let b = String(repeating: "b", count: 40)

    func testARemovalStaysPendingUntilTheEngineStopsListingIt() {
        var r = TorrentRemovals()
        r.add(infoHash: a, deleteFiles: false)
        XCTAssertTrue(r.contains(a))

        XCTAssertEqual(r.settle(listed: [a]), [])
        XCTAssertTrue(r.contains(a), "the engine still holds it: the removal did not land")

        XCTAssertEqual(r.settle(listed: []), [PendingTorrentRemoval(infoHash: a, deleteFiles: false)])
        XCTAssertTrue(r.isEmpty)
    }

    func testHashesAreComparedWithoutCase() {
        var r = TorrentRemovals()
        r.add(infoHash: a.uppercased(), deleteFiles: false)
        XCTAssertTrue(r.contains(a))
        XCTAssertEqual(r.settle(listed: [a]).count, 0)
        XCTAssertEqual(r.settle(listed: [b]).count, 1)
    }

    func testDeletingWithFilesWinsOverAnEarlierForget() {
        var r = TorrentRemovals()
        r.add(infoHash: a, deleteFiles: true)
        r.add(infoHash: a, deleteFiles: false)
        XCTAssertEqual(r.pending, [PendingTorrentRemoval(infoHash: a, deleteFiles: true)])
        r.add(infoHash: b, deleteFiles: false)
        r.add(infoHash: b, deleteFiles: true)
        XCTAssertEqual(r.pending.last, PendingTorrentRemoval(infoHash: b, deleteFiles: true))
        XCTAssertEqual(r.pending.count, 2)
    }

    func testAddingTheTorrentBackCancelsItsRemoval() {
        var r = TorrentRemovals()
        r.add(infoHash: a, deleteFiles: false)
        r.cancel(infoHash: a.uppercased())
        XCTAssertFalse(r.contains(a))
    }

    func testVisibleHidesTorrentsStillBeingRemoved() {
        var r = TorrentRemovals()
        r.add(infoHash: a, deleteFiles: false)
        XCTAssertEqual(r.visible([a, b], infoHash: { $0 }), [b])
    }

    func testPlaceholdersTravelWithTheRemovalUntilItSettles() throws {
        var r = TorrentRemovals()
        let files = [PendingTorrentRemoval.Placeholder(name: "movie.mkv", lengthBytes: 100)]
        r.add(infoHash: a, deleteFiles: false, outputFolder: "/dl", placeholders: files)
        r.add(infoHash: a, deleteFiles: false)
        var back = try JSONDecoder().decode(TorrentRemovals.self, from: JSONEncoder().encode(r))
        let settled = back.settle(listed: [])
        XCTAssertEqual(settled.first?.outputFolder, "/dl")
        XCTAssertEqual(settled.first?.placeholders, files)
    }

    func testAFileWithoutPlaceholderFieldsStillDecodes() throws {
        let json = #"{"pending":[{"infoHash":"\#(a)","deleteFiles":true}]}"#
        let r = try JSONDecoder().decode(TorrentRemovals.self, from: Data(json.utf8))
        XCTAssertEqual(r.pending, [PendingTorrentRemoval(infoHash: a, deleteFiles: true)])
    }

    func testSomethingThatIsNotAnInfoHashIsNeverKept() throws {
        var r = TorrentRemovals()
        r.add(infoHash: "../torrents x", deleteFiles: true)
        XCTAssertTrue(r.isEmpty)
        let json = #"{"pending":[{"infoHash":"a b%","deleteFiles":true},{"infoHash":"\#(b)","deleteFiles":false}]}"#
        let decoded = try JSONDecoder().decode(TorrentRemovals.self, from: Data(json.utf8))
        XCTAssertEqual(decoded.pending.map(\.infoHash), [b])
    }

    func testRoundTripsThroughJSON() throws {
        var r = TorrentRemovals()
        r.add(infoHash: a, deleteFiles: true)
        let back = try JSONDecoder().decode(TorrentRemovals.self, from: JSONEncoder().encode(r))
        XCTAssertEqual(back, r)
    }
}
