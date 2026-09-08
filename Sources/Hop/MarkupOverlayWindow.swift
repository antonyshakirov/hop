import AppKit
import SwiftUI

/// Deliberately NOT excluded from screen capture: a drawing invisible in a
/// shared screen would defeat the module.
/// SPEC: .claude/specs/2026-09-07-markup-modules-design.md
final class MarkupOverlayWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    init(screen: NSScreen, content: NSView) {
        super.init(contentRect: screen.frame,
                   styleMask: [.borderless],
                   backing: .buffered,
                   defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = .screenSaver
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        isReleasedWhenClosed = false
        ignoresMouseEvents = false
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
        hasShadow = false
        level = NSWindow.Level(rawValue: NSWindow.Level.screenSaver.rawValue + 1)
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        isReleasedWhenClosed = false
        isMovableByWindowBackground = false
        hidesOnDeactivate = false
        contentView = content
        setContentSize(content.fittingSize)
    }
}
