import Foundation

/// Whether a module's change has to reach the panel's view tree.
/// SPEC: docs/spec.md - "What a running clock costs". Tests: PanelRedrawTests.
public struct PanelRedraw {
    private var surfaces: Set<String> = []
    private var missed = false

    public init() {}

    /// False means nothing draws the panel; the change is remembered, not drawn.
    public mutating func ticks() -> Bool {
        if surfaces.isEmpty { missed = true }
        return !surfaces.isEmpty
    }

    /// True means the panel is coming back owing one redraw for what it missed.
    public mutating func setVisible(_ visible: Bool, surface: String) -> Bool {
        let wasEmpty = surfaces.isEmpty
        if visible { surfaces.insert(surface) } else { surfaces.remove(surface) }
        let owed = wasEmpty && !surfaces.isEmpty && missed
        if !surfaces.isEmpty { missed = false }
        return owed
    }
}
