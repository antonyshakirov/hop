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
    var weight: NSFont.Weight = .regular
    var monospaced = true
    var alignment: NSTextAlignment = .natural
    var colour: Color?
    /// Two-way: set it to put the caret in, and it comes back false when the
    /// field gives the caret up.
    var focus: Binding<Bool>?
    /// Applied to every keystroke, before the text reaches the binding: what
    /// it returns is what the field shows and what the binding gets.
    var filter: ((String) -> String)?
    var onSubmit: () -> Void = {}
    var onCancel: () -> Void = {}

    func makeNSView(context: Context) -> NSTextField {
        let field = NSTextField()
        field.cell = SteadyCell(textCell: "")
        // A hand-made cell comes back neither editable nor selectable, whatever
        // the field it is put into was. Set AFTER the swap, or the field is
        // read-only and looks like it simply ignores the keyboard.
        field.isEditable = true
        field.isSelectable = true
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.usesSingleLineMode = true
        field.lineBreakMode = .byTruncatingTail
        field.cell?.isScrollable = true
        field.cell?.wraps = false
        field.stringValue = text
        field.delegate = context.coordinator
        apply(to: field)
        return field
    }

    func updateNSView(_ field: NSTextField, context: Context) {
        context.coordinator.owner = self
        apply(to: field)
        // While the caret is in the field the text on screen is the user's own
        // and is left alone — except when the binding was changed from OUTSIDE
        // the keyboard: a value the coordinator never saw typed (the add row
        // clearing its draft after Return) has to reach the field even mid-edit,
        // or the appended task's text stays put in front of the next one.
        if field.stringValue != text,
           field.currentEditor() == nil || text != context.coordinator.typed {
            field.stringValue = text
            context.coordinator.typed = text
        }
        guard let focus else { return }
        let holds = field.currentEditor() != nil
        if focus.wrappedValue, !holds {
            DispatchQueue.main.async { field.window?.makeFirstResponder(field) }
        } else if !focus.wrappedValue, holds {
            DispatchQueue.main.async { field.window?.makeFirstResponder(nil) }
        }
    }

    private func apply(to field: NSTextField) {
        field.font = monospaced
            ? NSFont.monospacedSystemFont(ofSize: size, weight: weight)
            : NSFont.systemFont(ofSize: size, weight: weight)
        field.alignment = alignment
        field.textColor = colour.map { NSColor($0) } ?? .labelColor
        // The stock placeholder colour is faint enough to read as an empty
        // field with nothing to say. This one asks for something.
        field.placeholderAttributedString = NSAttributedString(
            string: placeholder,
            attributes: [.font: field.font ?? NSFont.systemFont(ofSize: size),
                         .foregroundColor: NSColor.secondaryLabelColor])
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        var owner: SteadyField
        /// The last value the KEYBOARD put into the binding, so `updateNSView`
        /// can tell a round trip of the user's own typing from a change made
        /// elsewhere.
        var typed: String

        init(_ owner: SteadyField) {
            self.owner = owner
            typed = owner.text
        }

        func controlTextDidChange(_ notification: Notification) {
            guard let field = notification.object as? NSTextField else { return }
            var typed = field.stringValue
            // Written straight into the field: `updateNSView` leaves the text
            // alone while the caret is in it, so a filtered binding alone would
            // change the value and leave the rejected characters on screen.
            if let filter = owner.filter {
                let kept = filter(typed)
                if kept != typed {
                    field.stringValue = kept
                    typed = kept
                }
            }
            self.typed = typed
            owner.text = typed
        }

        func controlTextDidBeginEditing(_ notification: Notification) {
            guard let focus = owner.focus, !focus.wrappedValue else { return }
            DispatchQueue.main.async { focus.wrappedValue = true }
        }

        func controlTextDidEndEditing(_ notification: Notification) {
            guard let focus = owner.focus, focus.wrappedValue else { return }
            DispatchQueue.main.async { focus.wrappedValue = false }
        }

        func control(_ control: NSControl, textView: NSTextView,
                     doCommandBy selector: Selector) -> Bool {
            switch selector {
            case #selector(NSResponder.insertNewline(_:)):
                owner.onSubmit()
                return true
            case #selector(NSResponder.cancelOperation(_:)):
                owner.onCancel()
                return true
            default:
                return false
            }
        }
    }
}

/// One rectangle for the placeholder, the caret and the typed text.
final class SteadyCell: NSTextFieldCell {
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
