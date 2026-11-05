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
    var onEndEditing: () -> Void = {}
    var onCancel: () -> Void = {}
    var onOutsideInteraction: (() -> Void)? = nil

    func makeNSView(context: Context) -> NSTextField {
        let field: SteadyTextField = onOutsideInteraction == nil ? SteadyTextField() : PointerExitField()
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
        field.onFocus = { context.coordinator.beginEditing() }
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
            DispatchQueue.main.async {
                guard focus.wrappedValue, field.currentEditor() == nil else { return }
                field.window?.makeFirstResponder(field)
            }
        } else if !focus.wrappedValue, holds {
            DispatchQueue.main.async {
                guard !focus.wrappedValue, field.currentEditor() != nil else { return }
                field.window?.makeFirstResponder(nil)
            }
        }
    }

    private func apply(to field: NSTextField) {
        if let field = field as? PointerExitField {
            let changed = (field.onOutsideInteraction == nil) != (onOutsideInteraction == nil)
            field.onOutsideInteraction = onOutsideInteraction
            if changed { field.updateTrackingAreas() }
        }
        field.font = monospaced
            ? NSFont.monospacedSystemFont(ofSize: size, weight: weight)
            : NSFont.systemFont(ofSize: size, weight: weight)
        field.alignment = alignment
        field.textColor = colour.map { NSColor($0) } ?? .labelColor
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = alignment
        // The stock placeholder colour is faint enough to read as an empty
        // field with nothing to say. This one asks for something.
        field.placeholderAttributedString = NSAttributedString(
            string: placeholder,
            attributes: [.font: field.font ?? NSFont.systemFont(ofSize: size),
                         .paragraphStyle: paragraph,
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
                    let editor = field.currentEditor() as? NSTextView
                    let selection = editor?.selectedRange()
                    let raw = typed as NSString
                    var restoredSelection: NSRange?
                    if let selection, selection.location != NSNotFound {
                        let start = min(selection.location, raw.length)
                        let end = start + min(selection.length, raw.length - start)
                        let before = min(filter(raw.substring(to: start)).utf16.count, kept.utf16.count)
                        let after = min(filter(raw.substring(to: end)).utf16.count, kept.utf16.count)
                        restoredSelection = NSRange(location: before, length: max(0, after - before))
                    }
                    field.stringValue = kept
                    if let restoredSelection { editor?.setSelectedRange(restoredSelection) }
                    typed = kept
                }
            }
            self.typed = typed
            owner.text = typed
        }

        func beginEditing() {
            owner.focus?.wrappedValue = true
        }

        func controlTextDidBeginEditing(_ notification: Notification) {
            beginEditing()
        }

        func controlTextDidEndEditing(_ notification: Notification) {
            owner.focus?.wrappedValue = false
            owner.onEndEditing()
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

class SteadyTextField: NSTextField {
    var onFocus: (() -> Void)?

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    private var typingClickMonitor: Any?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let typingClickMonitor { NSEvent.removeMonitor(typingClickMonitor) }
        typingClickMonitor = nil
        guard window != nil else { return }
        typingClickMonitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { [weak self] event in
            guard let self, event.window === self.window, !self.isHiddenOrHasHiddenAncestor,
                  self.visibleRect.contains(self.convert(event.locationInWindow, from: nil)) else { return event }
            self.activateForTyping()
            return event
        }
    }

    deinit {
        if let typingClickMonitor { NSEvent.removeMonitor(typingClickMonitor) }
    }

    override func becomeFirstResponder() -> Bool {
        let accepted = super.becomeFirstResponder()
        if accepted {
            onFocus?()
            activateForTyping()
        }
        return accepted
    }

    private func activateForTyping() {
        guard let window, window.isVisible else { return }
        _ = StatusItemController.preventActivation(of: window, prevented: false)
        NSApp.activate()
        window.makeKey()
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

private final class PointerExitField: SteadyTextField {
    var onOutsideInteraction: (() -> Void)?
    private var pointerArea: NSTrackingArea?
    private var clickMonitor: Any?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let clickMonitor { NSEvent.removeMonitor(clickMonitor); self.clickMonitor = nil }
        updateTrackingAreas()
    }
    deinit { if let clickMonitor { NSEvent.removeMonitor(clickMonitor) } }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let pointerArea { removeTrackingArea(pointerArea); self.pointerArea = nil }
        guard onOutsideInteraction != nil else {
            if let clickMonitor { NSEvent.removeMonitor(clickMonitor); self.clickMonitor = nil }
            return
        }
        let area = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect], owner: self)
        addTrackingArea(area); pointerArea = area
        if clickMonitor == nil, window != nil {
            clickMonitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { [weak self] event in
                guard let self, let window = self.window, event.window === window,
                      !self.bounds.contains(self.convert(event.locationInWindow, from: nil)) else { return event }
                self.dismiss()
                return event
            }
        }
    }
    private func dismiss() {
        window?.makeFirstResponder(nil)
        onOutsideInteraction?()
    }
    override func mouseExited(with event: NSEvent) {
        if onOutsideInteraction != nil { dismiss() } else { super.mouseExited(with: event) }
    }
}
