import AppKit
import SwiftUI

struct CoolingActionButton: NSViewRepresentable {
    let title: String
    let id: String
    let lang: AppLanguage
    var selected = false
    var centered = false
    let action: () -> Void

    static let check = NSImage(data: Data(#"<svg xmlns="http://www.w3.org/2000/svg" width="12" height="12" viewBox="0 0 12 12" fill="none" stroke="black" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round"><path d="m2 6 2.5 2.5L10 3"/></svg>"#.utf8))

    final class Coordinator: NSObject {
        var action: () -> Void
        init(_ action: @escaping () -> Void) { self.action = action }
        @objc func press() { action() }
    }
    func makeCoordinator() -> Coordinator { Coordinator(action) }
    func makeNSView(context: Context) -> NSButton {
        let button = NSButton(title: title, target: context.coordinator, action: #selector(Coordinator.press))
        button.setButtonType(.momentaryPushIn)
        button.isBordered = false; button.focusRingType = .none
        return button
    }
    func updateNSView(_ button: NSButton, context: Context) {
        context.coordinator.action = action
        button.title = title; button.isEnabled = context.environment.isEnabled
        button.state = selected ? .on : .off
        button.font = lang.isRTL ? .systemFont(ofSize: 12) : .monospacedSystemFont(ofSize: 12, weight: .regular)
        button.contentTintColor = NSColor(Theme.textPrimary)
        button.alignment = centered ? .center : .left
        button.image = selected ? Self.check : nil; button.image?.isTemplate = true
        button.imagePosition = .imageLeading
        button.identifier = NSUserInterfaceItemIdentifier(id)
        button.setAccessibilityIdentifier(id); button.setAccessibilityLabel(title)
        button.setAccessibilityValue(NSNumber(value: selected))
    }
}

struct CoolingSpeedSlider: NSViewRepresentable {
    @Binding var value: Double
    let range: ClosedRange<Double>
    let id: Int
    let label: String

    final class Coordinator: NSObject {
        var value: Binding<Double>
        init(_ value: Binding<Double>) { self.value = value }
        @objc func change(_ sender: NSSlider) { value.wrappedValue = sender.doubleValue }
    }
    func makeCoordinator() -> Coordinator { Coordinator($value) }
    func makeNSView(context: Context) -> NSSlider {
        let slider = NSSlider(value: value, minValue: range.lowerBound, maxValue: range.upperBound,
                              target: context.coordinator, action: #selector(Coordinator.change(_:)))
        slider.numberOfTickMarks = 0; slider.allowsTickMarkValuesOnly = false
        slider.isContinuous = true; slider.focusRingType = .none; slider.controlSize = .small
        return slider
    }
    func updateNSView(_ slider: NSSlider, context: Context) {
        context.coordinator.value = $value
        slider.minValue = range.lowerBound; slider.maxValue = range.upperBound
        slider.doubleValue = max(range.lowerBound, min(range.upperBound, value))
        slider.isEnabled = context.environment.isEnabled
        let identifier = "hop.cooling.target.\(id)"
        slider.identifier = NSUserInterfaceItemIdentifier(identifier)
        slider.setAccessibilityIdentifier(identifier); slider.setAccessibilityLabel(label)
    }
}
