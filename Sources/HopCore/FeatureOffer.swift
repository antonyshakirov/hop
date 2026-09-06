import Foundation

/// What a "new modules" card still has to offer.
/// SPEC: docs/spec.md - "What's-new card (module checklist)".
public enum FeatureOffer {
    /// The modules worth offering: the ones the panel is not already showing.
    /// A card offering to switch on what is already on reads as if the app had
    /// forgotten the user.
    public static func remaining(_ keys: [String], active: Set<String>) -> [String] {
        keys.filter { !active.contains($0) }
    }

    /// Whether the card has anything left to say.
    public static func worthShowing(_ keys: [String], active: Set<String>) -> Bool {
        !remaining(keys, active: active).isEmpty
    }
}
