import XCTest
@testable import HopCore

final class TorrentInitialSelectionTests: XCTestCase {
    private let base = URL(string: "http://127.0.0.1:3030")!
    private let body = Data([0x64, 0x34, 0x3a, 0x69, 0x6e, 0x66, 0x6f])

    private actor Engine: HTTPTransport {
        var requests: [URLRequest] = []
        let included: [Bool]
        let updateStatus: Int

        init(included: [Bool], updateStatus: Int = 200) {
            self.included = included
            self.updateStatus = updateStatus
        }

        func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
            requests.append(request)
            let updating = request.url!.path.hasSuffix("/update_only_files")
            let files = included.enumerated().map { index, included in
                ["name": "folder\(index)/file.bin", "length": 1024, "included": included] as [String: Any]
            }
            let data = updating ? Data() : try JSONSerialization.data(withJSONObject: [
                "id": 0, "details": ["info_hash": String(repeating: "a", count: 40),
                    "name": "test", "output_folder": "/test", "files": files],
            ])
            return (data, HTTPURLResponse(url: request.url!, statusCode: updating ? updateStatus : 200,
                                         httpVersion: nil, headerFields: nil)!)
        }
    }

    func testInitialSelectionIsPartOfAddWithRawTorrentBytes() async throws {
        let engine = Engine(included: [true, false, true])
        let client = TorrentEngineClient(baseURL: base, basicAuth: "hop:test", transport: engine)
        let result = try await client.add(body: body, outputFolder: "/test/My Files", selectedIndices: [2, 0, 2])
        let requests = await engine.requests
        XCTAssertEqual(requests.count, 1)
        let request = try XCTUnwrap(requests.first)
        let query = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)!.queryItems!
        XCTAssertEqual(query.first { $0.name == "only_files" }?.value, "0,2")
        XCTAssertEqual(query.first { $0.name == "output_folder" }?.value, "/test/My Files")
        XCTAssertEqual(request.httpBody, body)
        XCTAssertEqual(result.files.map(\.selected), [true, false, true])
    }

    func testAllFilesAreExplicitlySelectedForMagnet() async throws {
        let engine = Engine(included: [true, true])
        let client = TorrentEngineClient(baseURL: base, basicAuth: "hop:test", transport: engine)
        let magnet = Data("magnet:?xt=urn:btih:abc&so=1".utf8)
        _ = try await client.add(body: magnet, outputFolder: nil, selectedIndices: [0, 1])
        let requests = await engine.requests
        let request = try XCTUnwrap(requests.first)
        let query = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)!.queryItems!
        XCTAssertEqual(query.first { $0.name == "only_files" }?.value, "0,1")
        XCTAssertEqual(request.httpBody, magnet)
    }

    func testInvalidSelectionNeverReachesEngine() async {
        for indices in [[], [-1], [0, -1]] {
            let engine = Engine(included: [true])
            let client = TorrentEngineClient(baseURL: base, basicAuth: "hop:test", transport: engine)
            do {
                _ = try await client.add(body: body, outputFolder: nil, selectedIndices: indices)
                XCTFail("Invalid selection was accepted")
            } catch {
                XCTAssertEqual(error as? TorrentEngineClient.EngineError, .invalidSelection)
            }
            let requests = await engine.requests
            XCTAssertTrue(requests.isEmpty)
        }
    }

    func testDuplicateSelectionIsUpdatedByInfoHash() async throws {
        let engine = Engine(included: [true, true, true])
        let client = TorrentEngineClient(baseURL: base, basicAuth: "hop:test", transport: engine)
        let result = try await client.add(body: body, outputFolder: nil, selectedIndices: [1])
        let requests = await engine.requests
        XCTAssertEqual(requests.count, 2)
        XCTAssertEqual(requests.last?.url?.path, "/torrents/\(String(repeating: "a", count: 40))/update_only_files")
        let data = try XCTUnwrap(requests.last?.httpBody)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: [Int]]
        XCTAssertEqual(json?["only_files"], [1])
        XCTAssertEqual(result.files.map(\.selected), [false, true, false])
    }

    func testDuplicateSelectionFailureIsReported() async {
        let engine = Engine(included: [true, true], updateStatus: 500)
        let client = TorrentEngineClient(baseURL: base, basicAuth: "hop:test", transport: engine)
        do {
            _ = try await client.add(body: body, outputFolder: nil, selectedIndices: [0])
            XCTFail("Selection update failure was hidden")
        } catch {
            XCTAssertEqual(error as? TorrentEngineClient.EngineError, .http(500))
        }
    }
}
