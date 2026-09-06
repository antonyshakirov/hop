import Foundation
import HopCore

/// Fetching a file from the first host that answers (`DownloadMirrors`).
/// Anything but a 200 counts as no answer, and the URL that did answer comes
/// back so the caller can ask that host for the rest of the same download.
enum MirrorFetch {
    static func data(from url: URL,
                     hosts: [String] = DownloadMirrors.hosts,
                     cachePolicy: URLRequest.CachePolicy = .useProtocolCachePolicy)
        async throws -> (data: Data, url: URL) {
        try await attempt(url, hosts) { candidate in
            var request = URLRequest(url: candidate)
            request.cachePolicy = cachePolicy
            let (data, response) = try await URLSession.shared.data(for: request)
            try check(response)
            return data
        }
    }

    static func download(from url: URL,
                         hosts: [String] = DownloadMirrors.hosts)
        async throws -> (file: URL, url: URL) {
        try await attempt(url, hosts) { candidate in
            let (file, response) = try await URLSession.shared.download(from: candidate)
            try check(response)
            return file
        }
    }

    /// Each address in turn; rethrows the LAST failure, which is the one that
    /// left nothing else to try.
    static func attempt<T>(_ url: URL, _ hosts: [String],
                           _ body: (URL) async throws -> T) async throws -> (T, URL) {
        var failure: Error = URLError(.badURL)
        for candidate in DownloadMirrors.alternatives(for: url, hosts: hosts) {
            do {
                return (try await body(candidate), candidate)
            } catch {
                failure = error
            }
        }
        throw failure
    }

    private static func check(_ response: URLResponse) throws {
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }
    }
}
