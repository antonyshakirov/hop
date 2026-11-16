import SwiftUI
import HopPluginAPI

struct PluginNodeView: View {
    let nodes: [PluginNode]
    let action: (String) -> Void
    let module: (String) -> AnyView
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(Array(nodes.enumerated()), id: \.offset) { _, node in content(node) }
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
    private func content(_ node: PluginNode) -> AnyView {
        switch node.type {
        case "text": return AnyView(Text(node.text ?? "").font(Theme.mono(node.style == "title" ? 18 : node.style == "caption" ? 10 : 12))
            .foregroundStyle(Theme.textPrimary).fixedSize(horizontal: false, vertical: true))
        case "button": return AnyView(PluginActionButton(title: node.title ?? "") { if let id = node.action { action(id) } })
        case "divider": return AnyView(Rectangle().fill(Theme.divider).frame(height: 1))
        case "spacer": return AnyView(Spacer(minLength: 12))
        case "module": return module(node.module ?? "")
        case "row": return AnyView(HStack(alignment: .top, spacing: 12) {
            ForEach(Array((node.children ?? []).enumerated()), id: \.offset) { _, child in content(child) }
        })
        case "column": return AnyView(PluginNodeView(nodes: node.children ?? [], action: action, module: module))
        default: return AnyView(EmptyView())
        }
    }
}

struct PluginActionButton: NSViewRepresentable {
    let title: String
    let action: () -> Void
    var bordered = true
    var accessibilityID = "hop.plugin.action"
    final class Coordinator: NSObject {
        var action: () -> Void
        init(action: @escaping () -> Void) { self.action = action }
        @objc func press() { action() }
    }
    func makeCoordinator() -> Coordinator { Coordinator(action: action) }
    func makeNSView(context: Context) -> NSButton {
        let button = NSButton(title: title, target: context.coordinator, action: #selector(Coordinator.press))
        button.bezelStyle = .rounded; button.controlSize = .small
        button.setAccessibilityIdentifier("hop.plugin.action")
        return button
    }
    func updateNSView(_ button: NSButton, context: Context) {
        button.title = title; context.coordinator.action = action
        button.isBordered = bordered
        button.identifier = NSUserInterfaceItemIdentifier(accessibilityID)
        button.setAccessibilityIdentifier(accessibilityID)
        if !bordered {
            button.font = L10n.current.isRTL ? .systemFont(ofSize: 11) : .monospacedSystemFont(ofSize: 11, weight: .medium)
            button.contentTintColor = NSColor(Theme.textSecondary)
        }
    }
}
