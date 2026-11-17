import SwiftUI

struct CoolingSettingsLink: NSViewRepresentable {
    let title: String
    let action: () -> Void
    final class Coordinator: NSObject {
        var action: () -> Void
        init(action: @escaping () -> Void) { self.action = action }
        @objc func press() { action() }
    }
    func makeCoordinator() -> Coordinator { Coordinator(action: action) }
    func makeNSView(context: Context) -> NSButton {
        let button = NSButton(title: title, target: context.coordinator, action: #selector(Coordinator.press))
        let svg = #"<svg xmlns="http://www.w3.org/2000/svg" width="10" height="10" viewBox="0 0 14 14" fill="none" stroke="black" stroke-width="1.4" stroke-linecap="round" stroke-linejoin="round"><path d="M3 11 11 3M4 3h7v7"/></svg>"#
        button.image = NSImage(data: Data(svg.utf8)); button.image?.isTemplate = true
        button.imagePosition = .imageTrailing; button.isBordered = false; button.alignment = .left
        return button
    }
    func updateNSView(_ button: NSButton, context: Context) {
        context.coordinator.action = action
        button.title = title; button.isEnabled = context.environment.isEnabled
        button.font = L10n.current.isRTL ? .systemFont(ofSize: 12) : .monospacedSystemFont(ofSize: 12, weight: .regular)
        button.contentTintColor = NSColor(Theme.textPrimary)
        button.toolTip = title; button.setAccessibilityLabel(title)
        button.identifier = NSUserInterfaceItemIdentifier("hop.cooling.settings")
        button.setAccessibilityIdentifier("hop.cooling.settings")
    }
}
