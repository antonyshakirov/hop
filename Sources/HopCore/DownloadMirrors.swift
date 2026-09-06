import Foundation

/// The hosts one downloadable file may be fetched from.
/// SPEC: docs/spec.md — "Update channel", mirrors.
public enum DownloadMirrors {
    /// Shipped hosts, in the order they are tried.
    public static let hosts = ["hop.tools", "ru.hop.tools"]

    /// The same file on every host, the URL's own host first; a URL pointing
    /// anywhere else is returned alone.
    public static func alternatives(for url: URL, hosts: [String] = hosts) -> [URL] {
        guard let host = url.host, hosts.contains(host) else { return [url] }
        var ordered = [host]
        ordered.append(contentsOf: hosts.filter { $0 != host })
        return ordered.compactMap { swap(url, to: $0) }
    }

    /// The shipped hosts plus whatever a manifest declared. A declaration is a
    /// host name; anything carrying a scheme, port or path is ignored.
    public static func hosts(declared: [String], adding shipped: [String] = hosts) -> [String] {
        var result = shipped
        for entry in declared {
            let host = entry.trimmingCharacters(in: .whitespaces).lowercased()
            guard isPlainHost(host), !result.contains(host) else { continue }
            result.append(host)
        }
        return result
    }

    /// The same file on `host`, for an address of ours; anything else stands.
    public static func moving(_ url: URL, to host: String, hosts: [String] = hosts) -> URL {
        guard let current = url.host, hosts.contains(current), hosts.contains(host)
        else { return url }
        return swap(url, to: host) ?? url
    }

    private static func isPlainHost(_ host: String) -> Bool {
        guard !host.isEmpty, !host.hasPrefix("."), !host.hasSuffix("."),
              host.contains("."), host.count <= 253 else { return false }
        return host.allSatisfy { $0.isLetter || $0.isNumber || $0 == "." || $0 == "-" }
    }

    private static func swap(_ url: URL, to host: String) -> URL? {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        else { return nil }
        components.host = host
        return components.url
    }
}
