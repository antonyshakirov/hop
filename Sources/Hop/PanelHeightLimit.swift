import Foundation

// SPEC: docs/spec.md — invariant #1, "The panel always fits on screen".
// Test in PanelHeightLimitTests.
enum PanelHeightLimit {
    static let margin: CGFloat = 24
    static let fallbackScreenHeight: CGFloat = 800

    static func ceiling(screenVisibleHeight: CGFloat?) -> CGFloat {
        (screenVisibleHeight ?? fallbackScreenHeight) - margin
    }

    static func clamp(_ size: CGSize, screenVisibleHeight: CGFloat?) -> CGSize {
        guard let screenVisibleHeight else { return size }
        return CGSize(width: size.width,
                      height: min(size.height, ceiling(screenVisibleHeight: screenVisibleHeight)))
    }

    static func clipboardCeiling(screenVisibleHeight: CGFloat?) -> CGFloat {
        max(208, min(430, (screenVisibleHeight ?? fallbackScreenHeight) - 560))
    }
}
