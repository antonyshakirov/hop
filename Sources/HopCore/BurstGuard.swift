import Foundation

/// A cap on how often a signal may be answered.
/// SPEC: docs/spec.md — "What a running clock costs", the menu-bar button.
/// Tests: Tests/HopCoreTests/BurstGuardTests.swift
public struct BurstGuard {
    public let limit: Int
    public let window: TimeInterval
    public let cooldown: TimeInterval

    private var stamps: [TimeInterval] = []
    private var mutedUntil: TimeInterval?

    public init(limit: Int, window: TimeInterval, cooldown: TimeInterval) {
        self.limit = limit
        self.window = window
        self.cooldown = cooldown
    }

    /// True while the guard is refusing; `now` is a monotonic clock.
    public func isMuted(at now: TimeInterval) -> Bool {
        guard let until = mutedUntil else { return false }
        return now < until
    }

    /// Records one firing; more than `limit` inside `window` mutes `cooldown`.
    public mutating func allows(at now: TimeInterval) -> Bool {
        if let until = mutedUntil {
            guard now >= until else { return false }
            mutedUntil = nil
            stamps.removeAll()
        }
        stamps.removeAll { now - $0 > window }
        stamps.append(now)
        guard stamps.count > limit else { return true }
        mutedUntil = now + cooldown
        stamps.removeAll()
        return false
    }

    /// `muted` is true only on the firing that crosses the limit.
    public mutating func allowsAndReportsMuting(at now: TimeInterval) -> (allowed: Bool, muted: Bool) {
        let wasMuted = isMuted(at: now)
        let allowed = allows(at: now)
        return (allowed, !wasMuted && !allowed)
    }
}
