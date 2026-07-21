import CoreGraphics
import Foundation

/// Pure geometry for the settings "modules & tabs" table. The table is a row of
/// columns — the "inactive" storage column FIRST, then the space columns in
/// order, then the "+" add-tab tile — and each column stacks its chips top to
/// bottom. Extracted from the panel view so the frames→target math is testable
/// without SwiftUI, and so the live insertion indicator and the committed drop
/// share ONE resolver and can never disagree.
public enum SettingsDropGeometry {
    /// Which drop column a point falls in. A column whose frame CONTAINS the
    /// point wins; otherwise the point snaps to the nearest column by horizontal
    /// distance. Every column competes equally — "inactive" is a regular column
    /// now (no vertical-band special case, no X-nearest exclusion), so a point
    /// over it lands in it like any other. Returns nil only when there are no
    /// columns yet. The "+" add-tab tile is not passed in as a target.
    public static func columnID(at point: CGPoint, frames: [String: CGRect]) -> String? {
        if let hit = frames.first(where: { $0.value.contains(point) })?.key {
            return hit
        }
        return frames.min(by: { abs($0.value.midX - point.x) < abs($1.value.midX - point.x) })?.key
    }

    /// Insert index for a chip dropped at `point` among `keys` (a column's
    /// ordered module keys), EXCLUDING the dragged key itself. Columns stack
    /// vertically, so a sibling counts as "passed" once the point is below its
    /// vertical midpoint. A sibling with no frame yet is skipped (treated as
    /// not-yet-passed), matching the view's tolerant reads while frames settle.
    public static func insertIndex(
        point: CGPoint,
        keys: [String],
        excluding dragged: String,
        frames: [String: CGRect]
    ) -> Int {
        keys.filter { $0 != dragged }.filter {
            (frames[$0]?.midY ?? .greatestFiniteMagnitude) < point.y
        }.count
    }
}
