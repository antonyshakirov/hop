import Foundation

/// Transport seam so the client is testable without a live engine.
public protocol HTTPTransport: Sendable {
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

/// Talks to a local rqbit instance over its HTTP API.
public struct TorrentEngineClient {
    let baseURL: URL
    let basicAuth: String   // "user:pass"; the instance adds the Authorization header on send
    let transport: HTTPTransport

    public init(baseURL: URL, basicAuth: String, transport: HTTPTransport) {
        self.baseURL = baseURL
        self.basicAuth = basicAuth
        self.transport = transport
    }

    // MARK: - Pure request builders (no auth header — added by the instance on send)

    /// Join a path onto the base without appendingPathComponent, which would
    /// percent-encode the slashes in multi-segment paths.
    static func url(_ base: URL, _ path: String) -> URL {
        let b = base.absoluteString
        return URL(string: b.hasSuffix("/") ? b + path : b + "/" + path)!
    }

    /// The body is either a magnet/HTTP-URL as UTF-8 bytes or the raw bytes of a
    /// `.torrent` file. rqbit sniffs the content, so it must arrive verbatim —
    /// never re-encode it as a string here.
    static func addRequest(base: URL, body: Data, listOnly: Bool, outputFolder: String?) -> URLRequest {
        var comps = URLComponents(url: url(base, "torrents"), resolvingAgainstBaseURL: false)!
        var items = [
            URLQueryItem(name: "list_only", value: listOnly ? "true" : "false"),
            URLQueryItem(name: "overwrite", value: "true"),
        ]
        if let outputFolder { items.append(URLQueryItem(name: "output_folder", value: outputFolder)) }
        comps.queryItems = items
        var req = URLRequest(url: comps.url!)
        req.httpMethod = "POST"
        req.httpBody = body
        return req
    }

    static func updateOnlyFilesRequest(base: URL, id: String, indices: [Int]) -> URLRequest {
        var req = URLRequest(url: url(base, "torrents/\(id)/update_only_files"))
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try? JSONSerialization.data(withJSONObject: ["only_files": indices])
        return req
    }

    static func statsRequest(base: URL, id: String) -> URLRequest {
        var req = URLRequest(url: url(base, "torrents/\(id)/stats/v1")); req.httpMethod = "GET"; return req
    }
    static func listRequest(base: URL) -> URLRequest {
        var req = URLRequest(url: url(base, "torrents")); req.httpMethod = "GET"; return req
    }
    static func pauseRequest(base: URL, id: String) -> URLRequest { post(base, "torrents/\(id)/pause") }
    static func startRequest(base: URL, id: String) -> URLRequest { post(base, "torrents/\(id)/start") }
    static func forgetRequest(base: URL, id: String) -> URLRequest { post(base, "torrents/\(id)/forget") }
    static func deleteRequest(base: URL, id: String) -> URLRequest { post(base, "torrents/\(id)/delete") }

    private static func post(_ base: URL, _ path: String) -> URLRequest {
        var req = URLRequest(url: url(base, path)); req.httpMethod = "POST"; return req
    }
}

extension TorrentEngineClient {
    public enum EngineError: Error, Equatable { case http(Int) }

    public func addListOnly(body: Data) async throws -> AddResult {
        try RqbitDecoding.addResult(from: await send(Self.addRequest(base: baseURL, body: body, listOnly: true, outputFolder: nil)))
    }
    public func add(body: Data, outputFolder: String?) async throws -> AddResult {
        try RqbitDecoding.addResult(from: await send(Self.addRequest(base: baseURL, body: body, listOnly: false, outputFolder: outputFolder)))
    }
    public func setSelectedFiles(id: String, indices: [Int]) async throws {
        _ = try await send(Self.updateOnlyFilesRequest(base: baseURL, id: id, indices: indices))
    }
    public func stats(id: String) async throws -> TorrentStats {
        try RqbitDecoding.stats(from: await send(Self.statsRequest(base: baseURL, id: id)))
    }
    public func list() async throws -> [ListedTorrent] {
        try RqbitDecoding.list(from: await send(Self.listRequest(base: baseURL)))
    }
    public func pause(id: String) async throws { _ = try await send(Self.pauseRequest(base: baseURL, id: id)) }
    public func resume(id: String) async throws { _ = try await send(Self.startRequest(base: baseURL, id: id)) }
    public func forget(id: String) async throws { _ = try await send(Self.forgetRequest(base: baseURL, id: id)) }
    public func delete(id: String) async throws { _ = try await send(Self.deleteRequest(base: baseURL, id: id)) }

    private func authorized(_ request: URLRequest) -> URLRequest {
        var req = request
        let token = Data(basicAuth.utf8).base64EncodedString()
        req.setValue("Basic \(token)", forHTTPHeaderField: "Authorization")
        return req
    }
    @discardableResult
    private func send(_ request: URLRequest) async throws -> Data {
        let (data, response) = try await transport.send(authorized(request))
        guard (200..<300).contains(response.statusCode) else { throw EngineError.http(response.statusCode) }
        return data
    }
}
