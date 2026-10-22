import Foundation

public struct AppQuitApplication: Identifiable, Equatable, Sendable {
    public struct ID: Hashable, Sendable {
        public let processIdentifier: Int32
        public let launchDate: Date?
        public let bundleIdentifier: String?
        public let bundlePath: String?
    }

    public let id: ID
    public let name: String
    public let isRegular: Bool
    public let isTerminated: Bool

    public var pinIdentifier: String? { AppQuitPolicy.pinIdentifier(id.bundleIdentifier) }

    public init(processIdentifier: Int32, bundleIdentifier: String?, name: String, launchDate: Date? = nil,
                bundlePath: String? = nil, isRegular: Bool = true, isTerminated: Bool = false) {
        id = ID(processIdentifier: processIdentifier, launchDate: launchDate,
                bundleIdentifier: bundleIdentifier, bundlePath: bundlePath)
        self.name = name
        self.isRegular = isRegular
        self.isTerminated = isTerminated
    }
}

public enum AppQuitPolicy {
    public static func pinIdentifier(_ bundleIdentifier: String?) -> String? {
        guard let identifier = bundleIdentifier?.trimmingCharacters(in: .whitespacesAndNewlines),
              !identifier.isEmpty else { return nil }
        return identifier.lowercased()
    }

    public static func visibleApplications(_ applications: [AppQuitApplication], ownProcessIdentifier: Int32,
                                           ownBundleIdentifier: String? = nil) -> [AppQuitApplication] {
        let ownIdentifier = pinIdentifier(ownBundleIdentifier)
        var seen = Set<AppQuitApplication.ID>()
        return applications.filter { application in
            guard application.isRegular, !application.isTerminated,
                  application.id.processIdentifier != ownProcessIdentifier else { return false }
            if let identifier = application.pinIdentifier {
                guard identifier != "com.apple.finder", identifier != ownIdentifier,
                      !identifier.hasPrefix("com.antonshakirov.minimo"),
                      !identifier.hasPrefix("com.antonshakirov.hop") else { return false }
            }
            return seen.insert(application.id).inserted
        }.sorted {
            let order = $0.name.localizedStandardCompare($1.name)
            return order == .orderedSame ? $0.id.processIdentifier < $1.id.processIdentifier : order == .orderedAscending
        }
    }

    public static func quitCandidates(_ applications: [AppQuitApplication], pinnedBundleIdentifiers: Set<String>,
                                      ownProcessIdentifier: Int32, ownBundleIdentifier: String? = nil) -> [AppQuitApplication] {
        let pins = Set(pinnedBundleIdentifiers.compactMap { pinIdentifier($0) })
        return visibleApplications(applications, ownProcessIdentifier: ownProcessIdentifier,
                                   ownBundleIdentifier: ownBundleIdentifier).filter {
            guard let identifier = $0.pinIdentifier else { return true }
            return !pins.contains(identifier)
        }
    }
}
