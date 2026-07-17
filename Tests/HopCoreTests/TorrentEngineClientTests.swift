import XCTest
@testable import HopCore

final class TorrentEngineClientTests: XCTestCase {
    let base = URL(string: "http://127.0.0.1:3030")!
    private func fixture(_ name: String) throws -> Data {
        try Data(contentsOf: Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures")!)
    }
    struct StubTransport: HTTPTransport {
        let data: Data
        let status: Int
        func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
            (data, HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!)
        }
    }
    struct AuthCheckingTransport: HTTPTransport {
        let expected: String
        let data: Data
        func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
            guard request.value(forHTTPHeaderField: "Authorization") == expected else { throw URLError(.userAuthenticationRequired) }
            return (data, HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        }
    }

    func testStatsRoundTrip() async throws {
        let client = TorrentEngineClient(baseURL: base, basicAuth: "hop:t",
                                         transport: StubTransport(data: try fixture("rqbit-stats"), status: 200))
        let stats = try await client.stats(id: "0")
        XCTAssertGreaterThan(stats.totalBytes, 0)
        XCTAssertEqual(stats.peersLive, 104)
    }
    func testListRoundTrip() async throws {
        let client = TorrentEngineClient(baseURL: base, basicAuth: "hop:t",
                                         transport: StubTransport(data: try fixture("rqbit-list"), status: 200))
        let items = try await client.list()
        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items[0].id, "0")
    }
    func testAddListOnlyRoundTrip() async throws {
        let client = TorrentEngineClient(baseURL: base, basicAuth: "hop:t",
                                         transport: StubTransport(data: try fixture("rqbit-add-list-only"), status: 200))
        let r = try await client.addListOnly(body: Data("magnet:x".utf8))
        XCTAssertNil(r.id)
        XCTAssertEqual(r.files.count, 1)
    }
    func testAddsBasicAuthHeader() async throws {
        let expected = "Basic " + Data("hop:secret".utf8).base64EncodedString()
        let client = TorrentEngineClient(baseURL: base, basicAuth: "hop:secret",
                                         transport: AuthCheckingTransport(expected: expected, data: try fixture("rqbit-list")))
        _ = try await client.list() // succeeds only if the Authorization header matched
    }
    func testNon2xxThrows() async throws {
        let client = TorrentEngineClient(baseURL: base, basicAuth: "hop:t",
                                         transport: StubTransport(data: Data(), status: 500))
        do { _ = try await client.list(); XCTFail("expected throw") }
        catch { XCTAssertEqual(error as? TorrentEngineClient.EngineError, .http(500)) }
    }
}
