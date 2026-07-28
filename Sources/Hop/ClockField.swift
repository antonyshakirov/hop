import AppKit
import SwiftUI

/// A two-digit clock field — hours or minutes — backed by NSTextField.
///
/// Not SwiftUI's `TextField`: on focus it hands the text to AppKit's field
/// editor, whose vertical metric differs from the unfocused render, so the digits
/// visibly hop the moment you click them. An earlier fix nudged the text by
/// 1.5pt and only moved the hop to the other side (Anton, 2026-07-28). AppKit
/// draws both states itself, so there is nothing to compensate.
///
/// It also validates as you type rather than on commit: hours clamp to 0…23 and
/// minutes to 0…59, and a third digit is refused outright.
struct ClockField: NSViewRepresentable {
    @Binding var value: Int
    let range: ClosedRange<Int>
    var width: CGFloat = 34

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSTextField {
        let field = NSTextField(string: Self.formatted(value))
        field.isBordered = false
        field.drawsBackground = false
        field.alignment = .center
        field.focusRingType = .none
        field.usesSingleLineMode = true
        field.cell?.wraps = false
        field.cell?.isScrollable = true
        field.font = .monospacedDigitSystemFont(ofSize: 11, weight: .semibold)
        field.delegate = context.coordinator
        return field
    }

    func updateNSView(_ field: NSTextField, context: Context) {
        context.coordinator.parent = self
        field.textColor = NSColor(Theme.textPrimary)
        // Never overwrite what the user is typing.
        if field.currentEditor() == nil {
            let formatted = Self.formatted(value)
            if field.stringValue != formatted { field.stringValue = formatted }
        }
    }

    /// Always two digits, so a clock reads `09:05` rather than `9:5`.
    static func formatted(_ value: Int) -> String {
        String(format: "%02d", value)
    }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: ClockField

        init(_ parent: ClockField) { self.parent = parent }

        func controlTextDidChange(_ notification: Notification) {
            guard let field = notification.object as? NSTextField else { return }
            let digits = String(field.stringValue.filter(\.isNumber).prefix(2))
            var text = digits
            if let typed = Int(digits) {
                // Clamp while typing: "9" is on its way to "19", but "99" is not
                // a time and must not survive long enough to be committed.
                let clamped = min(max(typed, parent.range.lowerBound), parent.range.upperBound)
                if clamped != typed { text = String(clamped) }
                parent.value = clamped
            }
            if field.stringValue != text { field.stringValue = text }
        }

        func controlTextDidEndEditing(_ notification: Notification) {
            guard let field = notification.object as? NSTextField else { return }
            field.stringValue = ClockField.formatted(parent.value)
        }
    }
}
