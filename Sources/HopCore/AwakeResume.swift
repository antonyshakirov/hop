import Foundation

// SPEC: docs/spec.md — "Keep awake survives an update". Test in AwakeResumeTests.
public struct AwakeResume: Codable, Equatable, Sendable {
    public enum Session: Equatable, Sendable {
        case none
        case endless
        case until(Date)
    }

    public static let relaunchWindow: TimeInterval = 10 * 60

    public var active: Bool
    public var until: Date?
    public var optionSeconds: TimeInterval?
    public var lid: Bool
    public var savedAt: Date

    public init(active: Bool, until: Date?, optionSeconds: TimeInterval?, lid: Bool, savedAt: Date) {
        self.active = active
        self.until = until
        self.optionSeconds = optionSeconds
        self.lid = lid
        self.savedAt = savedAt
    }

    public func isFresh(now: Date) -> Bool {
        let age = now.timeIntervalSince(savedAt)
        return age >= 0 && age <= Self.relaunchWindow
    }

    public func session(now: Date) -> Session {
        guard active, isFresh(now: now) else { return .none }
        guard let until else { return .endless }
        return until > now ? .until(until) : .none
    }

    public func keepsLid(now: Date) -> Bool {
        lid && session(now: now) != .none
    }
}
