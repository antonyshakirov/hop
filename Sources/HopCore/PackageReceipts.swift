import Foundation

/// SPEC: docs/spec.md — "Removed apps, by their installer records". Tests: PackageReceiptsTests.
public enum PackageReceipts {
    /// The outermost app bundles among a package's paths, as absolute paths.
    public static func appBundles(in files: [String], prefix: String) -> [String] {
        let root = "/" + prefix.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        var bundles = Set<String>()
        for file in files {
            let parts = file.split(separator: "/").map(String.init)
            guard let index = parts.firstIndex(where: { $0.hasSuffix(".app") }) else { continue }
            let relative = parts[...index].joined(separator: "/")
            bundles.insert(root == "/" ? "/" + relative : root + "/" + relative)
        }
        return bundles.sorted()
    }

    /// The apps a record names when every one of them is gone; nil while any is still somewhere.
    public static func removedApps(files: [String], prefix: String,
                                   exists: (String) -> Bool,
                                   installedNames: Set<String>) -> [String]? {
        let bundles = appBundles(in: files, prefix: prefix)
        guard !bundles.isEmpty else { return nil }
        for bundle in bundles {
            let name = (bundle as NSString).lastPathComponent
            if exists(bundle) || installedNames.contains(name) { return nil }
        }
        return bundles
    }

    /// Apple's own records and the system's are never offered.
    public static func isOffered(receipt identifier: String) -> Bool {
        !identifier.hasPrefix("com.apple.")
    }
}
