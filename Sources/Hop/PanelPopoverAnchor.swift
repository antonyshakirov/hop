import AppKit

@MainActor
final class PanelPopoverAnchor {
    private let window: NSWindow
    var screen: NSScreen? { window.screen }

    init(screenRect: NSRect) {
        window = NSWindow(contentRect: screenRect, styleMask: .borderless,
                          backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.level = .statusBar
        window.ignoresMouseEvents = true
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
    }

    func show(_ popover: NSPopover) {
        guard let view = window.contentView else { return }
        window.orderFrontRegardless()
        popover.show(relativeTo: view.bounds, of: view, preferredEdge: .minY)
    }

    func realign(_ popover: NSPopover) {
        guard popover.isShown, let view = window.contentView else { return }
        var nudge = view.bounds
        nudge.size.width += 0.5
        popover.positioningRect = nudge
        popover.positioningRect = view.bounds
    }

    func close() { window.orderOut(nil) }
}
