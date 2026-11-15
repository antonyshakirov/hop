import Foundation

public enum PluginJSONBounds {
    public static func check(_ data: Data, maximumBytes: Int, maximumDepth: Int = 32) throws {
        guard data.count <= maximumBytes else { throw PluginError.invalidPackage }
        var quoted = false, escaped = false, depth = 0
        for byte in data {
            if quoted {
                if escaped { escaped = false }
                else if byte == 92 { escaped = true }
                else if byte == 34 { quoted = false }
            } else if byte == 34 { quoted = true }
            else if byte == 123 || byte == 91 {
                depth += 1
                guard depth <= maximumDepth else { throw PluginError.invalidPackage }
            } else if byte == 125 || byte == 93 { depth -= 1 }
            guard depth >= 0 else { throw PluginError.invalidPackage }
        }
        guard !quoted, depth == 0 else { throw PluginError.invalidPackage }
    }
}
