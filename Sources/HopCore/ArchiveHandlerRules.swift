/// Pure Launch Services ownership rules for archive types. The app target reads
/// the live handlers; this type decides which states Hop may change.
public enum ArchiveHandlerRules {
    public static let handledContentTypes = [
        "public.zip-archive", "com.rarlab.rar-archive",
        "org.7-zip.7-zip-archive", "public.tar-archive",
        "org.gnu.gnu-zip-archive", "org.gnu.gnu-zip-tar-archive",
        "public.bzip2-archive", "org.tukaani.xz-archive",
    ]

    /// Rar is the only archive format Hop may claim automatically. Every other
    /// declared type exists solely so Finder can offer Hop under Open With.
    public static let claimableContentTypes = ["com.rarlab.rar-archive"]

    /// Types that belong back with macOS's Archive Utility when repairing
    /// associations left by an older Hop version. Rar is deliberately excluded:
    /// the recovery action must not undo the one association Hop is allowed to
    /// own.
    public static let archiveUtilityContentTypes = handledContentTypes.filter {
        !claimableContentTypes.contains($0)
    }

    public static func isAppleHandler(_ bundleID: String?) -> Bool {
        bundleID?.lowercased().hasPrefix("com.apple.") ?? false
    }

    public static func shouldClaim(
        currentHandler: String?,
        hopBundleID: String
    ) -> Bool {
        !isAppleHandler(currentHandler)
            && currentHandler?.caseInsensitiveCompare(hopBundleID) != .orderedSame
    }

    public static func holdsUnexpectedType(
        contentType: String,
        currentHandler: String?,
        hopBundleID: String
    ) -> Bool {
        !claimableContentTypes.contains(contentType)
            && currentHandler?.caseInsensitiveCompare(hopBundleID) == .orderedSame
    }

    public static func contentTypesToRestore(
        currentHandlers: [String: String],
        hopBundleID: String
    ) -> [String] {
        archiveUtilityContentTypes.filter { type in
            currentHandlers[type]?
                .caseInsensitiveCompare(hopBundleID) == .orderedSame
        }
    }
}
