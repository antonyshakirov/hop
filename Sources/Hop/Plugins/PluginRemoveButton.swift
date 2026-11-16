import SwiftUI

struct PluginRemoveButton: NSViewRepresentable {
    let id: String
    let name: String
    let lang: AppLanguage
    let action: () -> Void
    final class Coordinator: NSObject {
        var action: () -> Void
        init(action: @escaping () -> Void) { self.action = action }
        @objc func press() { action() }
    }
    func makeCoordinator() -> Coordinator { Coordinator(action: action) }
    func makeNSView(context: Context) -> NSButton {
        let button = NSButton(title: "", target: context.coordinator, action: #selector(Coordinator.press))
        button.image = Self.image
        button.imagePosition = .imageOnly
        button.imageScaling = .scaleProportionallyDown
        button.isBordered = false
        return button
    }
    func updateNSView(_ button: NSButton, context: Context) {
        context.coordinator.action = action
        button.isEnabled = context.environment.isEnabled
        button.contentTintColor = NSColor(Theme.textTertiary)
        button.toolTip = PluginCopy.text(.remove, lang)
        button.identifier = NSUserInterfaceItemIdentifier("hop.plugins.remove." + id)
        button.setAccessibilityIdentifier("hop.plugins.remove." + id)
        button.setAccessibilityLabel(PluginCopy.text(.remove, lang) + " " + name)
    }
    private static let image: NSImage? = {
        let svg = #"<svg xmlns="http://www.w3.org/2000/svg" width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="black" stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round"><path d="M3 6h18M9 6V4h6v2M5 6l1 14h12l1-14M10 10v6M14 10v6"/></svg>"#
        let image = NSImage(data: Data(svg.utf8))
        image?.isTemplate = true
        return image
    }()
}
