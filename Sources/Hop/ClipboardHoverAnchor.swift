import AppKit
import SwiftUI

// SPEC: docs/spec.md — Clipboard, entry hover preview.
struct ClipboardHoverAnchor: NSViewRepresentable {
    let id: UUID
    let text: String
    let lang: AppLanguage

    func makeNSView(context: Context) -> ClipboardHoverAnchorView { ClipboardHoverAnchorView() }
    func updateNSView(_ view: ClipboardHoverAnchorView, context: Context) {
        view.configure(id: id, text: text, rtl: lang.isRTL)
    }
    static func dismantleNSView(_ view: ClipboardHoverAnchorView, coordinator: ()) { view.cancelPreview() }
}

@MainActor
final class ClipboardHoverAnchorView: NSView {
    private(set) var itemID = UUID()
    private(set) var previewText = ""
    private(set) var rtl = false
    private var dark = Theme.isDark
    var controller = ClipboardHoverController.shared
    private var area: NSTrackingArea?

    func configure(id: UUID, text: String, rtl: Bool) {
        guard itemID != id || previewText != text || self.rtl != rtl || dark != Theme.isDark else { return }
        cancelPreview()
        itemID = id; previewText = text; self.rtl = rtl; dark = Theme.isDark
    }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let area { removeTrackingArea(area) }
        let fresh = NSTrackingArea(rect: .zero,
            options: [.mouseEnteredAndExited, .mouseMoved, .activeAlways, .inVisibleRect], owner: self, userInfo: nil)
        addTrackingArea(fresh); area = fresh
    }
    override func mouseEntered(with event: NSEvent) { controller.request(from: self) }
    override func mouseMoved(with event: NSEvent) { controller.request(from: self) }
    override func mouseExited(with event: NSEvent) { cancelPreview() }
    override func viewWillMove(toWindow newWindow: NSWindow?) { cancelPreview(); super.viewWillMove(toWindow: newWindow) }
    override func setFrameOrigin(_ newOrigin: NSPoint) {
        if frame.origin != newOrigin { cancelPreview() }
        super.setFrameOrigin(newOrigin)
    }
    override func setFrameSize(_ newSize: NSSize) {
        if frame.size != newSize { cancelPreview() }
        super.setFrameSize(newSize)
    }
    func cancelPreview() { controller.cancel(owner: self) }
    var pointerInside: Bool {
        guard let window, window.isVisible, !isHiddenOrHasHiddenAncestor else { return false }
        return visibleRect.contains(convert(window.convertPoint(fromScreen: NSEvent.mouseLocation), from: nil))
    }
}
