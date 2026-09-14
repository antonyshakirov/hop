import XCTest
@testable import HopCore

final class RqbitListDecodingTests: XCTestCase {
    private func fixture(_ name: String) throws -> Data {
        let url = Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures")!
        return try Data(contentsOf: url)
    }
    private let expectedInfoHash = "481b6e3617be4c88f96cb25e47c9d8272130071e"
    private let torrentName = "debian-13.6.0-amd64-netinst.iso"

    func testListOnlyHasNoIdButHasFiles() throws {
        let r = try RqbitDecoding.addResult(from: fixture("rqbit-add-list-only"))
        XCTAssertNil(r.id)
        XCTAssertEqual(r.infoHash, expectedInfoHash)
        XCTAssertEqual(r.name, torrentName)
        XCTAssertEqual(r.files.count, 1)
        XCTAssertEqual(r.files[0].index, 0)
        XCTAssertEqual(r.files[0].name, torrentName)
        XCTAssertEqual(r.files[0].lengthBytes, 791674880)
        XCTAssertTrue(r.files[0].selected)
    }
    func testRealAddHasIntegerId() throws {
        let r = try RqbitDecoding.addResult(from: fixture("rqbit-add"))
        XCTAssertEqual(r.id, "0")
        XCTAssertEqual(r.infoHash, expectedInfoHash)
        XCTAssertEqual(r.files.count, 1)
    }
    func testListDecodesItems() throws {
        let items = try RqbitDecoding.list(from: fixture("rqbit-list"))
        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items[0].id, "0")
        XCTAssertEqual(items[0].infoHash, expectedInfoHash)
        XCTAssertEqual(items[0].name, torrentName)
    }

    // rqbit 9.0.1 adds total_pieces, per-file components/attributes and drops the
    // trailing slash on a listed output_folder; the fields Hop reads are unchanged.
    func testRqbit9ListOnlyDecodes() throws {
        let r = try RqbitDecoding.addResult(from: fixture("rqbit9-add-list-only"))
        XCTAssertNil(r.id)
        XCTAssertEqual(r.infoHash, "8a6007286dfea5b2a5bbda15a6a774434eb03ed7")
        XCTAssertEqual(r.name, "hns-stan.mkv")
        XCTAssertEqual(r.files.count, 1)
        XCTAssertEqual(r.files[0].lengthBytes, 9128454644)
        XCTAssertTrue(r.files[0].selected)
    }
    func testRqbit9ListDecodes() throws {
        let items = try RqbitDecoding.list(from: fixture("rqbit9-list"))
        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items[0].id, "0")
        XCTAssertEqual(items[0].infoHash, "8a6007286dfea5b2a5bbda15a6a774434eb03ed7")
        XCTAssertEqual(items[0].outputFolder, "/tmp/hop-tests/out")
    }
}
