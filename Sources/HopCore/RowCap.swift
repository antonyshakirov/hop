import CoreGraphics

/// Per-module "visible rows" cap for the scrollable list modules (to-dos and the
/// tracker). The cap is ALWAYS active now (the "all"/unlimited option is gone):
/// the list shows at most `cap` rows and any overflow scrolls inside a fixed
/// height. The stored setting is a plain Int; the practical range is 3…15, and a
/// stored 0 — the previous "all" sentinel — reads as the default (10), so no
/// persisted migration is needed. Any out-of-range value clamps into range.
public enum RowCap {
    public static let minRows = 3
    public static let maxRows = 15
    /// The default visible-row count for the tracker and to-do lists, and what a
    /// stored 0 (legacy "all") reads as on the clamp-on-read path.
    public static let defaultRows = 10

    /// Each to-do / tracker row is 26pt tall (22pt content + 2pt padding × 2) —
    /// the shared row rhythm. INTEGRAL on purpose: a fractional list height made
    /// the hosting controller re-measure and jump the header (fixed three times).
    public static let rowHeight: CGFloat = 26

    /// The `spacing:` the list VStack puts between rows. A capped list showing
    /// exactly `cap` rows must budget for the (cap − 1) gaps between them, or it
    /// shows ~cap−1 full rows plus a sliver of the next.
    public static let rowSpacing: CGFloat = 3

    /// The normalized row cap, always in 3…15. A stored 0 (legacy "all") or any
    /// value below the minimum reads as the default; anything above the maximum
    /// clamps down. There is no unlimited branch.
    public static func cap(_ stored: Int) -> Int {
        guard stored > 0 else { return defaultRows }
        return min(max(stored, minRows), maxRows)
    }

    /// The fixed list height when the list overflows the cap; nil when every row
    /// already fits (natural height, no scroll). `cap` rows plus the (cap − 1)
    /// inter-row gaps = 29·cap − 3 — always integral (26 and 3 are both whole),
    /// so the header never lands on a fractional pixel.
    public static func listHeight(stored: Int, count: Int) -> CGFloat? {
        let cap = cap(stored)
        guard count > cap else { return nil }
        return CGFloat(cap) * (rowHeight + rowSpacing) - rowSpacing
    }

    /// True when the list should scroll: the cap is exceeded.
    public static func scrolls(stored: Int, count: Int) -> Bool {
        listHeight(stored: stored, count: count) != nil
    }
}
