import Foundation

/// Removing an app and the dozen places it leaves things behind.
///
/// Everything here is a pure decision — which ENTRY inside a known folder belongs
/// to the app being removed, and whether it is safe to tick by default. The
/// listing, the sizes and the move to the trash are the controller's job, so the
/// risky part of an uninstaller (deciding that a folder belongs to this app and
/// not to five others) is unit-tested rather than trusted.
///
/// The first cut guessed exact paths from the bundle identifier and missed most
/// of what a real app leaves: `Containers/<id>.<extension>` for its share
/// extensions, `Group Containers/<TEAMID>.<id>`, `Application Scripts/<id>`,
/// `Caches/<id>.ShipIt` for a Squirrel updater. Checked against three installed
/// apps, that approach found two traces of Telegram's nine (2026-07-30). Listing
/// the folders and MATCHING is what finds the rest.
public enum AppUninstall {

    /// Where a trace lives, which is also how the window groups it.
    public enum Kind: String, CaseIterable, Sendable {
        case app                 // the bundle itself
        case support             // Application Support
        case caches              // Caches
        case preferences         // Preferences/<id>.plist
        case container           // Containers/<id>[.extension]
        case groupContainer      // Group Containers/<team>.<id>
        case appScripts          // Application Scripts/<id>
        case savedState          // Saved Application State
        case httpStorages        // HTTPStorages
        case webKit              // WebKit
        case logs                // Logs
        case cookies             // Cookies/<id>.binarycookies
        case launchAgent         // LaunchAgents (user)
        case byHost              // Preferences/ByHost/<id>.<hardware uuid>.plist
        case autosave            // Autosave Information/<id>
        case crashReports        // Logs/DiagnosticReports/<Name>_*.ips
        case sharedFolder        // /Users/Shared/<Name>
        case plugin              // plug-ins, panes, importers, workflows, kexts
        case systemCaches        // /Library/Caches (admin)
        case receipt             // /var/db/receipts/<id>.{bom,plist} (admin)
        case systemSupport       // /Library/Application Support (admin)
        case systemPreferences   // /Library/Preferences (admin)
        case systemLaunchAgent   // /Library/LaunchAgents (admin)
        case launchDaemon        // /Library/LaunchDaemons (admin)
        case privilegedHelper    // /Library/PrivilegedHelperTools (admin)

        /// Whether removing it needs an administrator.
        public var needsAdmin: Bool {
            switch self {
            case .systemSupport, .systemPreferences, .systemLaunchAgent,
                 .launchDaemon, .privilegedHelper, .systemCaches, .receipt:
                return true
            default:
                return false
            }
        }
    }

    /// How an entry was recognised, which decides whether it is ticked.
    public enum MatchKind: Equatable, Sendable {
        /// The bundle identifier, in any of its real shapes.
        case identifier
        /// A folder named exactly after the app ("Application Support/Notes").
        case exactName
        /// A folder that STARTS with the app's name ("Telegram Desktop" for
        /// "Telegram"): often the same app, sometimes a different one, so it is
        /// offered rather than assumed.
        case namePrefix
    }

    /// One found thing.
    public struct Candidate: Equatable, Sendable {
        public let path: String
        public let kind: Kind
        public let match: MatchKind
        /// A folder belonging to a VENDOR, not an app: removing it takes the
        /// company's other products with it.
        public let shared: Bool

        public init(path: String, kind: Kind, match: MatchKind, shared: Bool = false) {
            self.path = path
            self.kind = kind
            self.match = match
            self.shared = shared
        }

        public var byIdentifier: Bool { match == .identifier }

        /// Ticked by default: an identifier match or the app's exact name, and
        /// never a vendor folder or a mere name prefix. Leaving exact-name folders
        /// unticked made the default run a half-uninstall — that is where an app's
        /// gigabytes live.
        public var ticked: Bool { !shared && match != .namePrefix }
    }

    /// Folder names that belong to a company rather than to one app.
    public static let vendorFolders: Set<String> = [
        "google", "microsoft", "adobe", "jetbrains", "apple", "mozilla",
        "zoom.us", "telegram", "yandex", "dropbox", "logitech", "razer",
        "steam", "epic games", "unity", "docker", "vmware", "parallels",
    ]

    public static func isVendorFolder(_ name: String) -> Bool {
        vendorFolders.contains(name.lowercased())
    }

    /// Suffixes that are part of the file TYPE rather than the identifier, so they
    /// come off before matching: `com.acme.notes.plist` is the same name as
    /// `com.acme.notes`.
    private static let typeSuffixes = [
        ".plist", ".savedState", ".binarycookies", ".plist.lockfile", ".sfl3", ".bom", ".ips",
        // bundle-shaped leftovers: a quick-look generator, a preference pane, an
        // audio plug-in, a saved workflow. Their base name is the app's, so the
        // extension has to come off before comparing.
        ".qlgenerator", ".prefPane", ".bundle", ".plugin", ".component", ".driver",
        ".workflow", ".saver", ".mdimporter", ".appex", ".framework", ".kext",
        ".service", ".dockextension", ".wdgt", ".colorPicker", ".app",
    ]

    /// The identifier or name an entry carries, with the file type removed.
    public static func base(of entry: String) -> String {
        for suffix in typeSuffixes.sorted(by: { $0.count > $1.count })
        where entry.hasSuffix(suffix) {
            return String(entry.dropLast(suffix.count))
        }
        return entry
    }

    /// How (or whether) `entry` inside one of the known folders belongs to this
    /// app. Every rule is anchored on a DOT, so `com.acme.notesuite` is never
    /// swept up with `com.acme.notes`.
    public static func match(entry: String, identifier id: String, appName name: String)
    -> MatchKind? {
        let base = base(of: entry)
        if !id.isEmpty {
            if base == id { return .identifier }
            if base.hasPrefix(id + ".") { return .identifier }       // its extensions, helpers
            if base.hasSuffix("." + id) { return .identifier }       // <TEAMID>.<id>
            if base.contains("." + id + ".") { return .identifier }  // <TEAMID>.<id>.<extension>
        }
        guard !name.isEmpty else { return nil }
        if base.compare(name, options: .caseInsensitive) == .orderedSame { return .exactName }
        // a crash report is "<App Name>_2026-07-30-120000.ips" — the underscore is
        // the boundary macOS itself uses
        if base.lowercased().hasPrefix(name.lowercased() + "_") { return .exactName }
        // a space keeps "Notes" from claiming "Notesnook"
        if base.lowercased().hasPrefix(name.lowercased() + " ") { return .namePrefix }
        return nil
    }

    /// Folders whose CONTENTS are listed and matched, relative to `~/Library`.
    public static let userFolders: [(name: String, kind: Kind)] = [
        ("Application Support", .support),
        ("Caches", .caches),
        ("Preferences", .preferences),
        ("Containers", .container),
        ("Group Containers", .groupContainer),
        ("Application Scripts", .appScripts),
        ("Saved Application State", .savedState),
        ("HTTPStorages", .httpStorages),
        ("WebKit", .webKit),
        ("Logs", .logs),
        ("Cookies", .cookies),
        ("LaunchAgents", .launchAgent),
        // Per-host preferences: a real file, commonly missed, and the reason a
        // reinstalled app remembers a setting nobody expected it to.
        ("Preferences/ByHost", .byHost),
        // Autosave Information is protected by macOS: without Full Disk Access even
        // `ls` is refused, so the folder is listed and simply comes back empty.
        ("Autosave Information", .autosave),
        ("Logs/DiagnosticReports", .crashReports),
        ("Application Support/CrashReporter", .crashReports),
        // Plug-in style leftovers. Every uninstaller worth comparing against looks
        // here, and an app that installed a quick-look generator or a preference
        // pane leaves it behind on its own (added 2026-07-30).
        ("Internet Plug-Ins", .plugin),
        ("PreferencePanes", .plugin),
        ("QuickLook", .plugin),
        ("Spotlight", .plugin),
        ("Services", .plugin),
        ("Widgets", .plugin),
        ("Screen Savers", .plugin),
        ("Input Methods", .plugin),
        ("ColorPickers", .plugin),
        ("Frameworks", .plugin),
        ("Audio/Plug-Ins/HAL", .plugin),
        ("Audio/Plug-Ins/Components", .plugin),
    ]

    /// The same, under `/Library` — every one of these needs an administrator.
    public static let systemFolders: [(name: String, kind: Kind)] = [
        ("Application Support", .systemSupport),
        ("Preferences", .systemPreferences),
        ("LaunchAgents", .systemLaunchAgent),
        ("LaunchDaemons", .launchDaemon),
        ("PrivilegedHelperTools", .privilegedHelper),
        ("Caches", .systemCaches),
        ("Internet Plug-Ins", .plugin),
        ("PreferencePanes", .plugin),
        ("QuickLook", .plugin),
        ("Spotlight", .plugin),
        ("Extensions", .plugin),
        ("Frameworks", .plugin),
        ("Audio/Plug-Ins/HAL", .plugin),
        ("Audio/Plug-Ins/Components", .plugin),
    ]

    /// Folders outside both Library trees, by absolute path.
    public static let otherFolders: [(path: String, kind: Kind)] = [
        // Some installers leave a folder here for every user of the Mac.
        ("/Users/Shared", .sharedFolder),
        // The installer's own record. It CAN go — it is a file like any other —
        // and until 2026-07-30 it was listed as an unremovable remainder, which
        // was simply wrong (Anton asked why; the answer was "no reason").
        ("/var/db/receipts", .receipt),
    ]

    /// Turns one directory entry into a candidate, or nothing. `kind` says which
    /// folder it came from; `name` is the app's display name.
    /// Whether a found path needs an administrator to move: any system location,
    /// whatever kind it is. A plug-in folder exists in both trees.
    public static func needsAdmin(path: String, kind: Kind) -> Bool {
        kind.needsAdmin || path.hasPrefix("/Library/") || path.hasPrefix("/var/db/")
            || path.hasPrefix("/Users/Shared/")
    }

    public static func candidate(
        directory: String, entry: String, kind: Kind,
        identifier id: String, appName name: String
    ) -> Candidate? {
        guard let match = match(entry: entry, identifier: id, appName: name) else { return nil }
        // launchd folders hold labels, and a label that merely starts with the
        // app's NAME is not a job of this app
        if kind == .launchAgent || kind == .systemLaunchAgent || kind == .launchDaemon {
            guard match == .identifier, entry.hasSuffix(".plist") else { return nil }
        }
        let vendor = match != .identifier && isVendorFolder(base(of: entry))
        return Candidate(path: "\(directory)/\(entry)", kind: kind, match: match, shared: vendor)
    }

    // MARK: - Leftovers of apps that are already gone

    /// Whether `identifier` looks like a leftover: nothing installed answers to it
    /// and nothing installed OWNS it.
    ///
    /// The owner check is the one that matters. An app called `com.foo.App` ships a
    /// helper `com.foo.App.Updater` and a login item `com.foo.Updater`; neither is
    /// an installed app on its own, so asking the system "is this installed?"
    /// answers no while the owner sits right there in /Applications. A dot-anchored
    /// prefix of any installed identifier is therefore NOT a leftover.
    public static func isLeftover(identifier: String, installedIdentifiers: Set<String>) -> Bool {
        guard !identifier.isEmpty else { return false }
        // Apple's own data is the system's business
        guard !identifier.hasPrefix("com.apple.") else { return false }
        guard !installedIdentifiers.contains(identifier) else { return false }
        for installed in installedIdentifiers where !installed.isEmpty {
            if identifier.hasPrefix(installed + ".") { return false }   // its helper
            if installed.hasPrefix(identifier + ".") { return false }   // its family
        }
        return true
    }

    /// A leftover nobody has touched for this long is safe to OFFER. Anything
    /// written to recently is still in use by something — a background helper, a
    /// mounted volume's app — and offering it is how a tool deletes live data.
    public static let leftoverQuietDays = 30

    public static func isQuiet(modified: Date, now: Date = Date(),
                              days: Int = leftoverQuietDays) -> Bool {
        now.timeIntervalSince(modified) > Double(days) * 86_400
    }

    // MARK: - Finding the identifier when the app is already gone

    /// The identifier an entry implies for an app called `name`, or nil.
    ///
    /// This is for the case that actually happens: the app was dragged to the
    /// Trash first, so its Info.plist is unavailable and only name matches work —
    /// which is how a run found 13 traces where 22 were waiting (measured
    /// 2026-07-30). A preference file called `ru.keepcoder.Telegram.plist` says the
    /// identifier out loud: its LAST dot-component is the app's name.
    public static func impliedIdentifier(from entry: String, appName name: String) -> String? {
        guard !name.isEmpty else { return nil }
        let base = base(of: entry)
        // strip a team prefix if there is one: <TEAMID>.<id>
        let parts = base.split(separator: ".").map(String.init)
        guard parts.count >= 3 else { return nil }
        // Compare with separators removed: an id spells a display name as
        // "hop-uninstall-test", "HopUninstallTest" or "hop_uninstall_test", and all
        // three mean the same app.
        guard let last = parts.last, squashed(last) == squashed(name) else { return nil }
        // an id needs at least org.name form, and a team prefix is 10 upper-case
        // characters — drop it so the id itself comes out
        var id = parts
        if let first = id.first, first.count == 10,
           first.uppercased() == first, !first.contains(where: \.isLowercase) {
            id.removeFirst()
        }
        guard id.count >= 2 else { return nil }
        return id.joined(separator: ".")
    }

    /// A name with case and separators taken out, for comparing an identifier's
    /// last component with a display name.
    static func squashed(_ text: String) -> String {
        text.lowercased().filter { $0.isLetter || $0.isNumber }
    }

    /// The one identifier a set of entries agrees on, if they agree. Two different
    /// answers mean two different apps share a name, and guessing then is exactly
    /// how somebody else's data gets removed — so it returns nothing.
    public static func agreedIdentifier(entries: [String], appName name: String) -> String? {
        let found = Set(entries.compactMap { impliedIdentifier(from: $0, appName: name) })
        return found.count == 1 ? found.first : nil
    }

    // MARK: - Clearing a cache without removing the app

    /// Whether a found path is a cache macOS itself considers disposable.
    ///
    /// The rule is literal on purpose: a folder NAMED `Caches`, belonging to this
    /// app. Those the system may purge at any moment, so an app that cannot
    /// survive losing one is already broken. Everything else stays.
    public static func isDisposableCache(path: String, kind: Kind) -> Bool {
        if kind == .caches || kind == .systemCaches { return true }
        // Containers/<id>/Data/Library/Caches — the sandboxed equivalent
        return path.contains("/Data/Library/Caches")
    }

    /// A container holds an app's cache AND its data in one folder, so it is never
    /// cleared from outside: Telegram's group container is 25 GB of media cache
    /// mixed with the account database, and removing it logs somebody out and
    /// takes their local history (Anton asked, 2026-07-30). The window shows the
    /// size and says the app's own "clear cache" is the only safe route.
    public static func holdsMixedData(_ kind: Kind) -> Bool {
        kind == .container || kind == .groupContainer
    }

    /// Where a sandboxed app keeps the disposable half of its container.
    public static func containerCache(_ containerPath: String) -> String {
        "\(containerPath)/Data/Library/Caches"
    }

    /// The launchd domain a plist in `directory` belongs to, for `launchctl
    /// bootout`: a user agent is `gui/<uid>`, anything under /Library is `system`.
    public static func launchdDomain(forDirectory directory: String, uid: UInt32) -> String {
        directory.hasPrefix("/Library") ? "system" : "gui/\(uid)"
    }

    /// What an honest report still has to admit. Kept here so the UI and the docs
    /// cannot drift apart on the promise.
    ///
    /// Receipts left this list on 2026-07-30: they are ordinary files in
    /// /var/db/receipts and are now removed with the rest, behind the same admin
    /// prompt. What remains here genuinely cannot be removed by an app.
    public enum Remainder: String, CaseIterable, Sendable {
        /// The index is a database macOS maintains, not a per-app file: it forgets
        /// a deleted file by itself within seconds. Erasing it (`mdutil -E`) would
        /// re-index the whole disk for hours to achieve nothing.
        case spotlight
        /// Unified logging keeps ring buffers, not per-app files. Crash reports ARE
        /// per-app and are removed; the rest cannot be picked apart.
        case systemLogs
        /// Removable through the Security framework, deliberately not touched: the
        /// match is on a service name an app chose, and a wrong guess costs
        /// somebody a password they cannot get back.
        case keychain
        /// A system or network extension, and a VPN profile, are unloaded by the
        /// system on its own terms — through its own prompt, not by moving a file.
        case systemExtension
    }
}
