import AppKit
import HopCore
import OSLog
import SwiftUI

/// A borderless panel that takes clicks without becoming key or activating Hop.
/// SPEC: docs/spec.md — "Ink while a key is held".
final class HoldInkWindow: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    init(screen: NSScreen, view: HoldInkView) {
        super.init(contentRect: screen.frame,
                   styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered,
                   defer: false)
        level = NSWindow.Level(rawValue: Int(CGShieldingWindowLevel()))
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        contentView = view
        setFrame(screen.frame, display: false)
    }
}

final class HoldInkView: NSView {
    var ink = MarkupSettings.standardHoldInk {
        didSet { colour = NSColor(Color(markupHex: ink.hex)) }
    }

    private var colour = NSColor(Color(markupHex: MarkupSettings.standardHoldInk.hex))
    private var finished: [NSBezierPath] = []
    private var live: [MarkupPoint] = []

    override var isFlipped: Bool { true }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(
            rect: .zero,
            options: [.mouseEnteredAndExited, .mouseMoved, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil))
    }

    func clear() {
        finished.removeAll()
        live.removeAll()
        needsDisplay = true
    }

    func showNib() {
        MarkupCursors.pencil()?.set()
    }

    override func mouseEntered(with event: NSEvent) { showNib() }
    override func mouseMoved(with event: NSEvent) { showNib() }

    override func mouseDown(with event: NSEvent) { begin(event) }
    override func rightMouseDown(with event: NSEvent) { begin(event) }
    override func otherMouseDown(with event: NSEvent) { begin(event) }
    override func mouseDragged(with event: NSEvent) { extend(event) }
    override func rightMouseDragged(with event: NSEvent) { extend(event) }
    override func otherMouseDragged(with event: NSEvent) { extend(event) }
    override func mouseUp(with event: NSEvent) { end() }
    override func rightMouseUp(with event: NSEvent) { end() }
    override func otherMouseUp(with event: NSEvent) { end() }

    private func point(of event: NSEvent) -> MarkupPoint {
        let local = convert(event.locationInWindow, from: nil)
        return MarkupPoint(x: local.x, y: local.y)
    }

    private func begin(_ event: NSEvent) {
        showNib()
        if !live.isEmpty { end() }
        let start = point(of: event)
        live = [start]
        invalidateTail()
    }

    private func extend(_ event: NSEvent) {
        showNib()
        let next = point(of: event)
        guard let last = live.last else {
            live = [next]
            return
        }
        guard MarkupGeometry.worthAdding(next, after: last) else { return }
        live.append(next)
        invalidateTail()
    }

    private func end() {
        guard !live.isEmpty else { return }
        finished.append(path(through: live))
        live.removeAll()
    }

    private func invalidateTail() {
        let tail = live.suffix(4)
        guard let xs = tail.map(\.x).min(), let xe = tail.map(\.x).max(),
              let ys = tail.map(\.y).min(), let ye = tail.map(\.y).max() else { return }
        let pad = ink.width * 2 + 2
        setNeedsDisplay(NSRect(x: xs - pad, y: ys - pad, width: xe - xs + pad * 2, height: ye - ys + pad * 2))
    }

    private func path(through points: [MarkupPoint]) -> NSBezierPath {
        let path = NSBezierPath()
        path.lineWidth = ink.width
        path.lineCapStyle = .round
        path.lineJoinStyle = .round
        guard let first = points.first else { return path }
        path.move(to: NSPoint(x: first.x, y: first.y))
        if points.count == 1 {
            path.line(to: NSPoint(x: first.x, y: first.y))
            return path
        }
        for curve in MarkupGeometry.curves(through: points) {
            path.curve(to: NSPoint(x: curve.to.x, y: curve.to.y),
                       controlPoint1: NSPoint(x: curve.control1.x, y: curve.control1.y),
                       controlPoint2: NSPoint(x: curve.control2.x, y: curve.control2.y))
        }
        return path
    }

    override func draw(_ dirtyRect: NSRect) {
        colour.setStroke()
        for stroke in finished where stroke.bounds.insetBy(dx: -ink.width, dy: -ink.width).intersects(dirtyRect) {
            stroke.stroke()
        }
        if !live.isEmpty {
            path(through: live).stroke()
        }
    }
}

/// Resolved at run time, so a macOS without them loses only the background cursor, not the app.
private enum BackgroundCursor {
    private typealias DefaultConnectionFn = @convention(c) () -> Int32
    private typealias SetPropertyFn = @convention(c) (Int32, Int32, CFString, CFTypeRef) -> Int32

    /// nil when the symbols are gone; otherwise the status the window server answered.
    static func allow() -> Int32? {
        guard let handle = dlopen(nil, RTLD_NOW),
              let connectionSymbol = dlsym(handle, "_CGSDefaultConnection"),
              let setSymbol = dlsym(handle, "CGSSetConnectionProperty") else { return nil }
        let connection = unsafeBitCast(connectionSymbol, to: DefaultConnectionFn.self)()
        let set = unsafeBitCast(setSymbol, to: SetPropertyFn.self)
        return set(connection, connection, "SetsCursorInBackground" as CFString, kCFBooleanTrue)
    }
}

/// SPEC: docs/spec.md — "Ink while a key is held".
@MainActor
final class HoldInkLayer {
    private var windows: [HoldInkWindow] = []
    private var cursorUnlocked = false
    private var screensAtBuild: [NSRect] = []
    private var generation = 0
    private(set) var isShowing = false

    init() {
        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.screensChanged() }
        }
    }

    func show(ink: MarkupInk) {
        generation += 1
        if !cursorUnlocked {
            // WORKAROUND: the window server ignores NSCursor.set from an app that is not frontmost, and Hop never becomes frontmost here.
            let status = BackgroundCursor.allow()
            if status != 0 {
                Logger(subsystem: "com.antonshakirov.hop", category: "Markup")
                    .error("hold ink: background cursor refused, status \(status.map(String.init) ?? "no symbol")")
            }
            cursorUnlocked = true
        }
        let frames = NSScreen.screens.map(\.frame)
        if frames != screensAtBuild {
            windows.forEach { $0.orderOut(nil) }
            windows = NSScreen.screens.map { HoldInkWindow(screen: $0, view: HoldInkView()) }
            screensAtBuild = frames
        }
        for window in windows {
            guard let view = window.contentView as? HoldInkView else { continue }
            view.ink = ink
            view.clear()
            window.alphaValue = 1
            window.ignoresMouseEvents = false
            window.orderFrontRegardless()
        }
        isShowing = true
        (windows.first?.contentView as? HoldInkView)?.showNib()
    }

    func fadeAway() {
        guard isShowing else { return }
        isShowing = false
        let fading = generation
        windows.forEach { $0.ignoresMouseEvents = true }
        NSCursor.arrow.set()
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.3
            windows.forEach { $0.animator().alphaValue = 0 }
        }, completionHandler: { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.generation == fading else { return }
                self.putAway()
            }
        })
    }

    func dismiss() {
        generation += 1
        let wasShowing = isShowing
        isShowing = false
        putAway()
        if wasShowing { NSCursor.arrow.set() }
    }

    private func putAway() {
        for window in windows {
            window.orderOut(nil)
            window.alphaValue = 1
            (window.contentView as? HoldInkView)?.clear()
        }
    }

    private func screensChanged() {
        dismiss()
        windows.forEach { $0.orderOut(nil) }
        windows = []
        screensAtBuild = []
    }
}
