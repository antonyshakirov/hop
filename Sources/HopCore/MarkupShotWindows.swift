import Foundation

/// SPEC: docs/spec.md — "The panel stays on screen while the picture is taken".
public struct MarkupShotWindows: Equatable {
    public let leftOut: [UInt32]
    public let panelStepsAside: Bool

    public init(ours: [UInt32], layer: Set<UInt32>, panel: UInt32?) {
        leftOut = ours.filter { !layer.contains($0) }
        panelStepsAside = panel.map { !ours.contains($0) } ?? false
    }
}
