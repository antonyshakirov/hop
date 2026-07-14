import Foundation

/// Crash loop guard: if the app keeps dying at startup, the next
/// launch goes into safe mode — no modules, updater only.
/// Otherwise a bug that crashes the launch would also cut off the path to fixing it.
public enum LaunchGuard {
    public static let attemptsKey = "launchAttempts"
    /// How many consecutive unfinished launches it takes to enter safe mode.
    public static let threshold = 3
    /// How many seconds of uptime count as a successful launch.
    public static let stableAfter: TimeInterval = 30

    /// Register a launch. true — crash loop, time for safe mode.
    /// The counter is written immediately: cfprefsd survives a process crash.
    public static func registerLaunch(defaults: UserDefaults = .standard) -> Bool {
        let attempts = defaults.integer(forKey: attemptsKey) + 1
        defaults.set(attempts, forKey: attemptsKey)
        return attempts >= threshold
    }

    /// The launch is deemed successful (survived stableAfter or exited cleanly).
    public static func markStable(defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: attemptsKey)
    }
}
