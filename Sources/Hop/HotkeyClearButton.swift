import SwiftUI

struct HotkeyClearButton: NSViewRepresentable {
    let label: String
    let id: String
    let action: () -> Void
    final class Coordinator: NSObject {
        var action: () -> Void
        init(action: @escaping () -> Void) { self.action = action }
        @objc func press() { action() }
    }
    func makeCoordinator() -> Coordinator { Coordinator(action: action) }
    func makeNSView(context: Context) -> NSButton {
        let button = NSButton(title: "", target: context.coordinator, action: #selector(Coordinator.press))
        let svg = #"<svg xmlns="http://www.w3.org/2000/svg" width="12" height="12" viewBox="0 0 16 16" fill="none" stroke="black" stroke-width="1.5" stroke-linecap="round"><path d="m4 4 8 8M12 4l-8 8"/></svg>"#
        button.image = NSImage(data: Data(svg.utf8)); button.image?.isTemplate = true
        button.imagePosition = .imageOnly; button.isBordered = false
        return button
    }
    func updateNSView(_ button: NSButton, context: Context) {
        context.coordinator.action = action
        button.isEnabled = context.environment.isEnabled
        button.contentTintColor = NSColor(Theme.textTertiary)
        button.toolTip = label
        button.setAccessibilityLabel(label)
        button.identifier = NSUserInterfaceItemIdentifier("hop.hotkey.clear." + id)
        button.setAccessibilityIdentifier("hop.hotkey.clear." + id)
    }
}
