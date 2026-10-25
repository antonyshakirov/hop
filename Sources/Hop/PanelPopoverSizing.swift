import AppKit

@MainActor
enum PanelPopoverSizing {
    @discardableResult
    static func apply(_ desired: NSSize, to popover: NSPopover) -> Bool {
        guard desired.width > 0, desired.height > 0, popover.contentSize != desired else { return false }
        popover.contentSize = desired
        return true
    }
}
