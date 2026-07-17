import XCTest
@testable import HopCore

final class TorrentEngineClientRequestTests: XCTestCase {
    let base = URL(string: "http://127.0.0.1:3030")!

    func testAddListOnlySetsQueryAndBody() {
        let body = Data("magnet:?xt=urn:btih:abc".utf8)
        let r = TorrentEngineClient.addRequest(base: base, body: body,
                                               listOnly: true, outputFolder: nil)
        XCTAssertEqual(r.httpMethod, "POST")
        XCTAssertTrue(r.url!.absoluteString.contains("/torrents"))
        XCTAssertTrue(r.url!.absoluteString.contains("list_only=true"))
        XCTAssertEqual(r.httpBody, body)
    }
    func testAddBodyIsPassedThroughUnchangedForBinary() {
        // The start of a bencoded .torrent ("d8:") — raw bytes must survive
        // verbatim, never re-encoded as a string, or rqbit rejects the payload.
        let body = Data([0x64, 0x38, 0x3a])
        let r = TorrentEngineClient.addRequest(base: base, body: body,
                                               listOnly: false, outputFolder: nil)
        XCTAssertEqual(r.httpBody, body)
    }
    func testUpdateOnlyFilesBody() throws {
        let r = TorrentEngineClient.updateOnlyFilesRequest(base: base, id: "0", indices: [0, 2])
        XCTAssertEqual(r.httpMethod, "POST")
        XCTAssertTrue(r.url!.absoluteString.hasSuffix("/torrents/0/update_only_files"))
        let json = try JSONSerialization.jsonObject(with: r.httpBody!) as! [String: [Int]]
        XCTAssertEqual(json["only_files"], [0, 2])
    }
    func testStatsPath() {
        let r = TorrentEngineClient.statsRequest(base: base, id: "0")
        XCTAssertEqual(r.httpMethod, "GET")
        XCTAssertTrue(r.url!.absoluteString.hasSuffix("/torrents/0/stats/v1"))
    }
    func testListPath() {
        let r = TorrentEngineClient.listRequest(base: base)
        XCTAssertEqual(r.httpMethod, "GET")
        XCTAssertTrue(r.url!.absoluteString.hasSuffix("/torrents"))
    }
    func testPauseAndDeletePaths() {
        XCTAssertTrue(TorrentEngineClient.pauseRequest(base: base, id: "3").url!.absoluteString.hasSuffix("/torrents/3/pause"))
        XCTAssertTrue(TorrentEngineClient.deleteRequest(base: base, id: "3").url!.absoluteString.hasSuffix("/torrents/3/delete"))
    }
    func testOutputFolderIsPercentEncoded() {
        let r = TorrentEngineClient.addRequest(base: base, body: Data("magnet:x".utf8),
                                               listOnly: false, outputFolder: "/Users/x/My Files")
        XCTAssertTrue(r.url!.absoluteString.contains("output_folder=/Users/x/My%20Files"))
    }
}
