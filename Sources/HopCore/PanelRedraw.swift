import Foundation

/// Whether a clock tick has to reach the panel's view tree.
/// SPEC: docs/spec.md - "What a running clock costs". Tests: PanelRedrawTests.
public struct PanelRedraw {
    private var visible = false
    private var missed = false

    public init() {}

    /// False means the panel is off screen and the tick is remembered, not drawn.
    public mutating func ticks() -> Bool {
        if !visible { missed = true }
        return visible
    }

    /// True means the panel is coming back owing one redraw for what it missed.
    public mutating func setVisible(_ nowVisible: Bool) -> Bool {
        let owed = nowVisible && !visible && missed
        visible = nowVisible
        if nowVisible { missed = false }
        return owed
    }
}
