import Foundation

/// An archive kind Hop recognizes when something is dropped on it.
public enum ArchiveFormat: String, Sendable, CaseIterable {
    case zip, tar, tarGz, tarBz2, tarXz, gzip, sevenZip, rar

    /// Unpacked with tools every Mac already has (ditto, tar, gunzip).
    /// The rest need the downloadable 7-Zip helper.
    public var isNative: Bool {
        switch self {
        case .sevenZip, .rar: return false
        default: return true
        }
    }
}

/// What a pack job produces. RAR is deliberately absent: the format is
/// proprietary and no free packer may create it — Hop only ever EXTRACTS rar.
public enum PackFormat: String, Sendable, CaseIterable, Identifiable {
    case zip, tarGz, sevenZip

    public var id: String { rawValue }

    /// Short chip label — the extension itself, so it needs no translation.
    public var label: String {
        switch self {
        case .zip: return "zip"
        case .tarGz: return "tar.gz"
        case .sevenZip: return "7z"
        }
    }

    public var fileExtension: String {
        switch self {
        case .zip: return "zip"
        case .tarGz: return "tar.gz"
        case .sevenZip: return "7z"
        }
    }

    /// Only 7z needs the downloadable helper; zip and tar.gz are native.
    public var isNative: Bool { self != .sevenZip }
}

/// Pure naming and recognition rules for the archive module. Everything that
/// decides WHAT to do (which format, where the result goes, what it is called)
/// lives here with tests; the controller only runs the tools.
public enum ArchiveRules {
    /// Extensions in longest-first order, so "photos.tar.gz" is a gzipped tar
    /// and not a bare gzip, and "notes.tar.bz2" never matches ".bz2" alone.
    private static let extensions: [(suffix: String, format: ArchiveFormat)] = [
        (".tar.gz", .tarGz), (".tar.bz2", .tarBz2), (".tar.xz", .tarXz),
        (".tgz", .tarGz), (".tbz", .tarBz2), (".tbz2", .tarBz2), (".txz", .tarXz),
        (".zip", .zip), (".tar", .tar), (".gz", .gzip),
        (".7z", .sevenZip), (".rar", .rar),
    ]

    /// The archive format of a file NAME, or nil when it is not an archive we
    /// handle. Case-insensitive: ".ZIP" off a Windows share is still a zip.
    /// A dotfile like ".zip" (no stem) is not an archive.
    public static func format(ofFileNamed name: String) -> ArchiveFormat? {
        let lower = name.lowercased()
        for entry in extensions where lower.hasSuffix(entry.suffix) {
            guard lower.count > entry.suffix.count else { return nil }
            return entry.format
        }
        return nil
    }

    /// "photos.tar.gz" → "photos". Falls back to the whole name when nothing
    /// matches, so a caller always gets something to name a folder with.
    public static func baseName(ofArchive name: String) -> String {
        let lower = name.lowercased()
        for entry in extensions where lower.hasSuffix(entry.suffix) {
            return String(name.dropLast(entry.suffix.count))
        }
        return name
    }

    /// A name that does not collide with `taken`, macOS style: "photos",
    /// then "photos 2", "photos 3"… The suffix goes BEFORE the extension, so
    /// "photos 2.zip" stays a zip. Comparison is case-insensitive, because the
    /// default macOS volume is too — "Photos.zip" and "photos.zip" are one file.
    public static func uniqueName(base: String, extension ext: String, taken: Set<String>) -> String {
        let lowerTaken = Set(taken.map { $0.lowercased() })
        let suffix = ext.isEmpty ? "" : ".\(ext)"
        var candidate = base + suffix
        var counter = 2
        while lowerTaken.contains(candidate.lowercased()) {
            candidate = "\(base) \(counter)\(suffix)"
            counter += 1
            // a folder with thousands of collisions is pathological, not a
            // reason to spin forever
            if counter > 1000 { return "\(base) \(UUID().uuidString.prefix(6))\(suffix)" }
        }
        return candidate
    }

    /// What a pack job is called, before collision handling: one item packs
    /// under its own name ("report.pages" → "report.zip", a folder → its name),
    /// several items pack under the name of the folder holding them, and a
    /// mixed drop with no common parent falls back to "archive".
    public static func packBaseName(for paths: [String], commonParent: String?) -> String {
        guard !paths.isEmpty else { return "archive" }
        if paths.count == 1 {
            let name = (paths[0] as NSString).lastPathComponent
            let stem = (name as NSString).deletingPathExtension
            return stem.isEmpty ? name : stem
        }
        guard let parent = commonParent else { return "archive" }
        let name = (parent as NSString).lastPathComponent
        // "/" has no last component worth using, and neither does an empty one
        return name.isEmpty || name == "/" ? "archive" : name
    }

    /// The folder every dropped item shares, or nil when they come from
    /// different places (a multi-window drag). Also the folder results go into:
    /// Hop always writes NEXT TO the original, never into Downloads.
    public static func commonParent(of paths: [String]) -> String? {
        let parents = Set(paths.map { ($0 as NSString).deletingLastPathComponent })
        guard parents.count == 1, let only = parents.first, !only.isEmpty else { return nil }
        return only
    }

    /// Whether an entry path inside an archive is safe to write. Absolute paths
    /// and any "../" escape the destination folder ("zip slip"); the extraction
    /// tools mostly refuse these themselves, but a rule with tests beats trusting
    /// somebody else's flags.
    public static func isSafeEntryPath(_ path: String) -> Bool {
        guard !path.hasPrefix("/"), !path.hasPrefix("~") else { return false }
        let components = path.split(separator: "/", omittingEmptySubsequences: true)
        return !components.contains("..")
    }
}
