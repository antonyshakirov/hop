import Foundation

/// SPEC: docs/spec.md — "A permission that goes missing says so", Hop's row dropped once per run.
public enum PermissionAsk {
    public enum Trigger: CaseIterable, Sendable {
        case featureStopped
        case screenModule
        case button
    }

    public enum Destination: Equatable, Sendable {
        case permissionsPage
        case systemSettings
    }

    public struct Plan: Equatable, Sendable {
        public let dropsTheRow: Bool
        public let requests: Bool
        public let opens: Destination?

        public init(dropsTheRow: Bool, requests: Bool, opens: Destination?) {
            self.dropsTheRow = dropsTheRow
            self.requests = requests
            self.opens = opens
        }
    }

    /// nil — nothing is asked; Hop's row is never dropped twice in one run.
    public static func plan(_ trigger: Trigger, askedThisRun: Bool, droppedThisRun: Bool) -> Plan? {
        switch trigger {
        case .featureStopped:
            guard !askedThisRun else { return nil }
            return Plan(dropsTheRow: !droppedThisRun, requests: true, opens: nil)
        case .screenModule:
            return Plan(dropsTheRow: !droppedThisRun, requests: true, opens: .permissionsPage)
        case .button:
            return droppedThisRun
                ? Plan(dropsTheRow: false, requests: false, opens: .systemSettings)
                : Plan(dropsTheRow: true, requests: true, opens: nil)
        }
    }
}
