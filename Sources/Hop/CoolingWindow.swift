import AppKit
import SwiftUI

// SPEC: docs/spec.md — Cooling controls.
@MainActor
final class CoolingWindow: NSWindow, NSWindowDelegate {
    static let contentWidth: CGFloat = 500
    private let controller: CoolingController
    private var measuredHeight: CGFloat?

    init(controller: CoolingController) {
        self.controller = controller
        super.init(contentRect: NSRect(x: 0, y: 0, width: Self.contentWidth, height: 100),
                   styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
        title = L10n.t(.coolingTitle, L10n.current).capitalizedFirst
        titlebarAppearsTransparent = true
        isReleasedWhenClosed = false
        delegate = self
        let host = NSHostingController(rootView: CoolingWindowRoot(controller: controller,
            onHeightChange: { [weak self] height in self?.fit(contentHeight: height) }).hopLayoutDirection())
        host.sizingOptions = []
        contentViewController = host
        fitToContent()
    }

    func windowDidChangeScreen(_ notification: Notification) { fitToContent() }

    func fitToContent() {
        if let measuredHeight { fit(contentHeight: measuredHeight); return }
        let content = CoolingView(controller: controller, lang: L10n.current,
                                  allowsFanControls: ModuleActivation.isOn("system"))
            .frame(width: Self.contentWidth).fixedSize(horizontal: false, vertical: true)
        let measurement = NSHostingView(rootView: content.hopLayoutDirection())
        measurement.frame.size.width = Self.contentWidth
        fit(contentHeight: measurement.fittingSize.height)
    }

    func fit(contentHeight: CGFloat) {
        guard contentHeight.isFinite, contentHeight > 0 else { return }
        measuredHeight = contentHeight
        let visible = (screen ?? NSScreen.main)?.visibleFrame
        let height = min(ceil(contentHeight), floor((visible?.height ?? 900) * 0.8))
        guard abs(contentRect(forFrameRect: frame).height - height) > 0.5 else { return }
        let size = frameRect(forContentRect: NSRect(x: 0, y: 0, width: Self.contentWidth, height: height)).size
        var origin = NSPoint(x: frame.minX, y: frame.maxY - size.height)
        if let visible {
            origin.y = max(visible.minY, min(origin.y, visible.maxY - size.height))
        }
        setFrame(NSRect(origin: origin, size: size), display: isVisible)
    }
}
