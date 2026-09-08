import AppKit
import SwiftUI

/// A one-line field whose placeholder and whose typed text sit in the SAME
/// place. AppKit draws the placeholder through the cell and the typed text
/// through the window's field editor, and the two disagree by a point, so the
/// text hops the moment the field is clicked into.
/// SPEC: docs/spec.md — "Screenshot (capture and mark up)"
struct SteadyField: NSViewRepresentable {
    @Binding var text: String
    var placeholder: String = ""
    var size: CGFloat = 11
    var onSubmit: () -> Void = {}

    func makeNSView(context: Context) -> NSTextField {
        let field = NSTextField()
        field.cell = SteadyCell(textCell: "")
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.usesSingleLineMode = true
        field.lineBreakMode = .byTruncatingTail
        field.cell?.isScrollable = true
        field.cell?.wraps = false
        field.font = NSFont.monospacedSystemFont(ofSize: size, weight: .regular)
        field.textColor = .labelColor
        field.placeholderString = placeholder
        field.stringValue = text
        field.delegate = context.coordinator
        return field
    }

    func updateNSView(_ field: NSTextField, context: Context) {
        context.coordinator.owner = self
        field.placeholderString = placeholder
        if field.stringValue != text, field.currentEditor() == nil {
            field.stringValue = text
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        var owner: SteadyField

        init(_ owner: SteadyField) { self.owner = owner }

        func controlTextDidChange(_ notification: Notification) {
            guard let field = notification.object as? NSTextField else { return }
            owner.text = field.stringValue
        }

        func control(_ control: NSControl, textView: NSTextView,
                     doCommandBy selector: Selector) -> Bool {
            guard selector == #selector(NSResponder.insertNewline(_:)) else { return false }
            owner.onSubmit()
            return true
        }
    }
}

/// One rectangle for the placeholder, the caret and the typed text.
private final class SteadyCell: NSTextFieldCell {
    private func steady(_ bounds: NSRect) -> NSRect {
        var rect = super.drawingRect(forBounds: bounds)
        let height = cellSize(forBounds: bounds).height
        rect.origin.y += (rect.height - height) / 2
        rect.size.height = height
        return rect
    }

    override func drawingRect(forBounds rect: NSRect) -> NSRect { steady(rect) }

    override func select(withFrame rect: NSRect, in controlView: NSView, editor textObj: NSText,
                         delegate: Any?, start selStart: Int, length selLength: Int) {
        super.select(withFrame: steady(rect), in: controlView, editor: textObj,
                     delegate: delegate, start: selStart, length: selLength)
    }

    override func edit(withFrame rect: NSRect, in controlView: NSView, editor textObj: NSText,
                       delegate: Any?, event: NSEvent?) {
        super.edit(withFrame: steady(rect), in: controlView, editor: textObj,
                   delegate: delegate, event: event)
    }
}
