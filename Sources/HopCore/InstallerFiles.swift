import Foundation

/// Installers left over after installing: the .dmg an app came in, the .pkg from
/// a driver, the disk image nobody opened again.
///
/// Deliberately narrow. A "junk finder" that sweeps a whole home folder is how
/// people lose things they meant to keep, so this looks at the few folders a
/// download actually lands in, only at their top level, and only for the three
/// file types that ARE installers. Everything else — an .iso that might be a
/// film, a .zip that might be a project — is none of its business.
public enum InstallerFiles {

    /// The extensions that mean "this is how something was installed".
    public static let extensions: Set<String> = ["dmg", "pkg", "mpkg"]

    /// Where a download lands. Top level only: an installer is never three folders
    /// deep, and walking a whole home directory is both slow and the wrong promise.
    public static let folders = ["Downloads", "Desktop", "Documents"]

    /// Whether this file name is an installer.
    public static func isInstaller(_ name: String) -> Bool {
        extensions.contains((name as NSString).pathExtension.lowercased())
    }

    /// One found installer. `modified` is shown rather than acted upon: age is a
    /// hint for the person deciding, not a rule for us — a keepsake installer of a
    /// licensed app can be five years old and still wanted.
    public struct Found: Equatable, Sendable, Identifiable {
        public let path: String
        public let bytes: Int64
        public let modified: Date

        public var id: String { path }
        public var name: String { (path as NSString).lastPathComponent }

        public init(path: String, bytes: Int64, modified: Date) {
            self.path = path
            self.bytes = bytes
            self.modified = modified
        }
    }

    /// Biggest first: the reason to look at this list at all is space.
    public static func sorted(_ found: [Found]) -> [Found] {
        found.sorted { $0.bytes > $1.bytes }
    }

    /// Nothing is ever ticked by default here. An installer on disk is somebody's
    /// choice — a licensed app's original, an offline installer for a machine with
    /// no network — and a tool that pre-ticks them all is a tool that eventually
    /// deletes one that mattered.
    public static let tickedByDefault = false
}
