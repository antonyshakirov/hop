import AppKit
import SwiftUI

/// Deliberately NOT excluded from screen capture: a drawing invisible in a
/// shared screen would defeat the module.
/// SPEC: docs/spec.md — "Draw over the screen".
final class MarkupOverlayWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    /// SPEC: docs/spec.md — hiding the Dock only holds while Hop is the active
    /// app, and an app with no main window is not one.
    override var canBecomeMain: Bool { true }

    init(screen: NSScreen, content: NSView) {
        super.init(contentRect: screen.frame,
                   styleMask: [.borderless],
                   backing: .buffered,
                   defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        // The whole screen means the menu bar and the Dock too: at .screenSaver
        // the layer was drawn over them but the clicks still went through to
        // them. The shielding level is the one above both. SPEC: docs/spec.md
        level = NSWindow.Level(rawValue: Int(CGShieldingWindowLevel()))
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        isReleasedWhenClosed = false
        ignoresMouseEvents = false
        appearance = NSAppearance(named: Theme.isDark ? .darkAqua : .aqua)
        contentView = content
        setFrame(screen.frame, display: false)
    }
}

/// A click on a window that is not key is normally spent making it key, and the
/// press that should have started a selection draws nothing. The overlay has one
/// gesture and no other purpose: the FIRST press must count.
final class FirstMouseHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

@MainActor
final class MarkupOverlayController {
    private var windows: [MarkupOverlayWindow] = []
    private var make: ((NSScreen) -> NSView)?
    private var passesClicks = false
    private var watching = false
    /// SPEC: docs/spec.md — a display plugged in or taken away while the layer is up.
    var onRebuild: (@MainActor () -> Void)?

    var isShowing: Bool { !windows.isEmpty }

    func show(content: @escaping (NSScreen) -> NSView) {
        make = content
        rebuild()
        startWatchingScreens()
    }

    func hide() {
        for window in windows {
            window.orderOut(nil)
            window.contentView = nil
        }
        windows.removeAll()
        make = nil
    }

    func makeKey(on screen: NSScreen?) {
        let wanted = screen.flatMap { screen in windows.first { $0.screen == screen } }
        (wanted ?? windows.first)?.makeKeyAndOrderFront(nil)
    }

    /// `true` hands every click to whatever is underneath; the toolbar lives in
    /// a window of its own and keeps taking them either way.
    func setPassesClicks(_ passes: Bool) {
        passesClicks = passes
        for window in windows { window.ignoresMouseEvents = passes }
    }

    private func rebuild() {
        guard let make else { return }
        for window in windows {
            window.orderOut(nil)
            window.contentView = nil
        }
        windows = NSScreen.screens.map { screen in
            let window = MarkupOverlayWindow(screen: screen, content: make(screen))
            window.ignoresMouseEvents = passesClicks
            window.orderFrontRegardless()
            return window
        }
    }

    private func startWatchingScreens() {
        guard !watching else { return }
        watching = true
        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.make != nil else { return }
                self.rebuild()
                self.onRebuild?()
            }
        }
    }
}

/// The toolbar's own window: small, always able to take a click, and above the
/// drawing layer. It has to be separate — a layer that lets clicks through does
/// so for everything inside it, and the panel would go with it.
final class MarkupToolbarWindow: NSPanel {
    override var canBecomeKey: Bool { true }

    init(content: NSView) {
        super.init(contentRect: NSRect(x: 0, y: 0, width: 10, height: 10),
                   styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        // The system draws the shadow, OUTSIDE the window: a shadow drawn
        // inside it is clipped by the window's own edge, and the clipped edge
        // reads as a dark rectangle under the panel. SPEC: docs/spec.md
        hasShadow = true
        level = NSWindow.Level(rawValue: Int(CGShieldingWindowLevel()) + 1)
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        isReleasedWhenClosed = false
        isMovableByWindowBackground = false
        hidesOnDeactivate = false
        appearance = NSAppearance(named: Theme.isDark ? .darkAqua : .aqua)
        contentView = content
        setContentSize(content.fittingSize)
    }
}
