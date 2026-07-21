import CoreGraphics
import Foundation

/// Pure geometry for the settings "modules & tabs" table: given the laid-out
/// frames of a column's chips and the pointer location, decide the index at
/// which a dragged chip should be inserted. Extracted from the panel view so
/// the frames→index math is testable without SwiftUI, and so the live insertion
/// indicator and the committed drop share ONE resolver and can never disagree.
public enum SettingsDropGeometry {
    /// How a column lays its chips out.
    /// - `stacked`: the space columns grow top-to-bottom, so only a sibling's
    ///   vertical midpoint decides order.
    /// - `wrapping`: the inactive bucket flows left-to-right and wraps, so
    ///   reading order counts an earlier row, OR the same row to the left.
    public enum Flow { case stacked, wrapping }

    /// Insert index for a chip dropped at `point` among `keys` (a column's
    /// ordered module keys), EXCLUDING the dragged key itself. Each sibling's
    /// frame comes from `frames`; a sibling with no frame is skipped (stacked)
    /// or treated as not-yet-passed (wrapping), matching the view's tolerant
    /// reads while frames are still settling.
    public static func insertIndex(
        point: CGPoint,
        keys: [String],
        excluding dragged: String,
        frames: [String: CGRect],
        flow: Flow
    ) -> Int {
        let siblings = keys.filter { $0 != dragged }
        switch flow {
        case .stacked:
            return siblings.filter {
                (frames[$0]?.midY ?? .greatestFiniteMagnitude) < point.y
            }.count
        case .wrapping:
            return siblings.filter { key in
                guard let f = frames[key] else { return false }
                return f.maxY <= point.y || (f.minY <= point.y && f.midX < point.x)
            }.count
        }
    }
}
