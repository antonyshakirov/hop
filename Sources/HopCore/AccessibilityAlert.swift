import Foundation

/// SPEC: docs/spec.md — "A permission that goes missing says so".
public enum AccessibilityAlert: String, Equatable, Sendable, CaseIterable {
    case none
    case missing
    case lost
    case stale
}

public enum AccessibilityVerdict {

    /// `suppressionProven` is the keyboard lock's measurement, nil while none
    /// has been made; it only ever overrules a granted permission.
    public static func alert(granted: Bool,
                             wasGrantedBefore: Bool,
                             suppressionProven: Bool?) -> AccessibilityAlert {
        guard granted else { return wasGrantedBefore ? .lost : .missing }
        return suppressionProven == false ? .stale : .none
    }

    /// Whether the panel carries the alert at the top.
    public static func showsBanner(_ alert: AccessibilityAlert,
                                   featureWasBlocked: Bool) -> Bool {
        switch alert {
        case .none: return false
        case .missing: return featureWasBlocked
        case .lost, .stale: return true
        }
    }
}

/// The 1 Hz check under a live keyboard lock.
/// SPEC: docs/spec.md — "Keyboard lock (cleaning mode)".
public enum TapWatchdog {
    public enum Step: Equatable, Sendable {
        case fine
        case reArm
        case giveUp
    }

    public static func step(tapEnabled: Bool, reArmedLastTick: Bool) -> Step {
        if tapEnabled { return .fine }
        return reArmedLastTick ? .giveUp : .reArm
    }
}
