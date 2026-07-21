import CoreGraphics

/// Per-module "visible rows" cap for the scrollable list modules (to-dos and the
/// tracker). The stored setting is a plain Int: 0 means "all" — no cap, the
/// DEFAULT, so existing users see no change; 3…15 caps the visible rows and the
/// overflow scrolls inside a fixed-height area. A value outside 3…15 but > 0
/// clamps into that range.
public enum RowCap {
    /// The stored sentinel for "show all rows" (no cap).
    public static let all = 0
    public static let minRows = 3
    public static let maxRows = 15

    /// Each to-do / tracker row is 26pt tall (22pt content + 2pt padding × 2) —
    /// the shared row rhythm. INTEGRAL on purpose: a fractional list height made
    /// the hosting controller re-measure and jump the header (fixed three times).
    public static let rowHeight: CGFloat = 26

    /// The `spacing:` the list VStack puts between rows. A capped list showing
    /// exactly `cap` rows must budget for the (cap − 1) gaps between them, or it
    /// shows ~cap−1 full rows plus a sliver of the next.
    public static let rowSpacing: CGFloat = 3

    /// Normalized cap: nil = show all; otherwise a row count in 3…15.
    public static func cap(_ stored: Int) -> Int? {
        guard stored > 0 else { return nil }
        return min(max(stored, minRows), maxRows)
    }

    /// The fixed list height when a cap is active AND the list overflows it; nil
    /// when uncapped or when every row already fits (natural height, no scroll).
    /// `cap` rows plus the (cap − 1) inter-row gaps = 29·cap − 3 — always integral
    /// (26 and 3 are both whole), so the header never lands on a fractional pixel.
    public static func listHeight(stored: Int, count: Int) -> CGFloat? {
        guard let cap = cap(stored), count > cap else { return nil }
        return CGFloat(cap) * (rowHeight + rowSpacing) - rowSpacing
    }

    /// True when the list should scroll: a cap is active and is exceeded.
    public static func scrolls(stored: Int, count: Int) -> Bool {
        listHeight(stored: stored, count: count) != nil
    }
}
