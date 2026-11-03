import AppKit
import SwiftUI

struct TrackerNamePointer: NSViewRepresentable {
    struct Value {
        let translation: CGSize
        let location: CGPoint
    }

    let row: UUID
    let origin: CGPoint
    let onClick: () -> Void
    let onChanged: (Value) -> Void
    let onEnded: (Value) -> Void
    let onCancelled: () -> Void

    func makeNSView(context: Context) -> Surface {
        let view = Surface()
        view.setAccessibilityElement(false)
        return view
    }

    func updateNSView(_ view: Surface, context: Context) {
        view.identifier = NSUserInterfaceItemIdentifier("tracker-name-" + row.uuidString)
        view.origin = origin
        view.onClick = onClick
        view.onChanged = onChanged
        view.onEnded = onEnded
        view.onCancelled = onCancelled
    }

    final class Surface: NSView {
        var origin = CGPoint.zero
        var onClick: () -> Void = {}
        var onChanged: (Value) -> Void = { _ in }
        var onEnded: (Value) -> Void = { _ in }
        var onCancelled: () -> Void = {}

        override var isFlipped: Bool { true }
        override var needsPanelToBecomeKey: Bool { false }
        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

        override func mouseDown(with event: NSEvent) {
            guard event.type == .leftMouseDown, let window else { return }
            let initial = event.locationInWindow
            let initialScreen = window.convertPoint(toScreen: initial)
            let local = convert(initial, from: nil)
            let start = CGPoint(x: origin.x + local.x, y: origin.y + local.y)
            let click = onClick, change = onChanged, end = onEnded, cancel = onCancelled
            var dragging = false
            PanelFrameLog.write("trackerPointerDown", "origin=\(start)")
            while let next = window.nextEvent(matching: [.leftMouseDragged, .leftMouseUp, .keyDown],
                                               until: .distantFuture, inMode: .eventTracking, dequeue: true) {
                if next.type == .keyDown {
                    if next.keyCode == 53 { cancel(); return }
                    continue
                }
                let screen = window.convertPoint(toScreen: next.locationInWindow)
                let translation = CGSize(width: screen.x - initialScreen.x,
                                         height: initialScreen.y - screen.y)
                let value = Value(translation: translation,
                                  location: CGPoint(x: start.x + translation.width,
                                                    y: start.y + translation.height))
                if !dragging, hypot(translation.width, translation.height) >= 3 {
                    dragging = true
                    change(value)
                    _ = StatusItemController.preventActivation(of: window, prevented: false)
                    NSApp.activate()
                    window.makeKey()
                    PanelFrameLog.write("trackerPointerBegin", "point=\(value.location)")
                } else if dragging, next.type == .leftMouseDragged {
                    change(value)
                }
                if next.type == .leftMouseUp {
                    if dragging {
                        PanelFrameLog.write("trackerPointerEnd", "point=\(value.location)")
                        end(value)
                    } else if event.clickCount == 1, bounds.contains(convert(next.locationInWindow, from: nil)) {
                        click()
                    }
                    return
                }
                window.contentView?.layoutSubtreeIfNeeded()
                window.displayIfNeeded()
            }
            if dragging { cancel() }
        }
    }
}
