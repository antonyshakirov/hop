import Foundation

enum PanelPopoverGeometry {
    static func anchoredFrame(_ frame: CGRect, top: CGFloat, visibleFrame: CGRect) -> CGRect {
        var result = frame
        let fittingHeight = min(frame.height, visibleFrame.height)
        let fittingTop = min(visibleFrame.maxY, max(visibleFrame.minY + fittingHeight, top))
        result.origin.y = fittingTop - frame.height
        return result
    }
}
