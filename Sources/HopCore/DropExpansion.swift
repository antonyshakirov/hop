import Foundation

/// What a drop onto the converter stands for. SPEC: docs/spec.md, "Converter".
/// Tests: `DropExpansionTests`.
public enum DropExpansion {
    public static let limit = 500

    /// Folders give their files, at most `limit` each; a package stays one item.
    public static func expand(_ urls: [URL], limit: Int = limit) -> [URL] {
        var out: [URL] = []
        for url in urls {
            guard url.isFileURL else {
                out.append(url)
                continue
            }
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory)
            else { continue }
            guard isDirectory.boolValue, !isPackage(url) else {
                out.append(url)
                continue
            }
            let keys: [URLResourceKey] = [.isRegularFileKey, .isPackageKey]
            let items = FileManager.default.enumerator(
                at: url, includingPropertiesForKeys: keys,
                options: [.skipsHiddenFiles, .skipsPackageDescendants])
            var taken = 0
            while taken < limit, let item = items?.nextObject() as? URL {
                let values = try? item.resourceValues(forKeys: Set(keys))
                guard values?.isRegularFile == true || values?.isPackage == true else { continue }
                out.append(item)
                taken += 1
            }
        }
        return out
    }

    private static func isPackage(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.isPackageKey]))?.isPackage == true
    }
}
