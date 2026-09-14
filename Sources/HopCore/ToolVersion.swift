import Foundation

/// SPEC: "Torrent engine: version floor". Tests: ToolVersionTests.
public enum ToolVersion {
    /// True when `installed` is older than `minimum`; an unreadable `installed` counts as older.
    public static func isBelow(_ installed: String?, minimum: String?) -> Bool {
        guard let minimum, let wanted = components(minimum) else { return false }
        guard let installed, let have = components(installed) else { return true }
        for i in 0..<max(have.count, wanted.count) {
            let a = i < have.count ? have[i] : 0
            let b = i < wanted.count ? wanted[i] : 0
            if a != b { return a < b }
        }
        return false
    }

    private static func components(_ version: String) -> [Int]? {
        var text = version.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.hasPrefix("v") { text.removeFirst() }
        let parts = text.split(separator: ".", omittingEmptySubsequences: false).map { Int($0) }
        guard !parts.isEmpty, parts.allSatisfy({ $0 != nil }) else { return nil }
        return parts.compactMap { $0 }
    }
}
