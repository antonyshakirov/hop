import Foundation

/// Whether this Mac has run Hop before.
/// SPEC: docs/spec.md — "Onboarding", who the wizard is for.
public enum FirstRun {
    /// Keys an older version is certain to have written, none of them a
    /// registered default.
    public static let marks = [
        "panelTabs", "activeSpaceID", "canonicalLayoutSeeded", "trackerTabSeeded",
        "todosSeeded", "moduleVisibilityMigrated", "optInModulesSeeded",
        "optInModulesSeeded170", "onboardingStep",
    ]

    /// Prefixes of the per-release flags every version writes as it announces
    /// itself: `newsSeen.1.9`, `featureSeen.torrent`, `permissionsReset.1.10.0`.
    public static let markPrefixes = ["newsSeen.", "newsShown.", "featureSeen.",
                                     "permissionsReset."]

    /// True when the app's own defaults hold nothing an earlier version left.
    /// Read BEFORE this launch writes anything of its own.
    public static func isFresh(domain: [String: Any]) -> Bool {
        for key in domain.keys {
            if marks.contains(key) { return false }
            if markPrefixes.contains(where: { key.hasPrefix($0) }) { return false }
        }
        return true
    }

    /// SPEC: docs/spec.md — "Onboarding", a wizard left halfway opens again.
    public static func needsWizard(domain: [String: Any]) -> Bool {
        if domain["onboardingDone"] as? Bool == true { return false }
        if isFresh(domain: domain) { return true }
        return domain["onboardingStep"] != nil || domain["onboardingSeededAllOn"] as? Bool == true
    }
}
