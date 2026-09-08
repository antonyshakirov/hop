import AppKit
import Combine
import HopCore
import SwiftUI

/// A window per shot; `shotOneWindow` folds them into macOS's own tabs.
/// SPEC: docs/spec.md — "Screenshot (capture and mark up)"
@MainActor
final class ShotEditorWindows: NSObject, NSWindowDelegate {
    static let oneWindowKey = "shotOneWindow"
    private static let tabbingID = "hop.shot"

    private var editors: [ObjectIdentifier: ScreenshotEditor] = [:]
    private var titleWatchers: [ObjectIdentifier: AnyCancellable] = [:]
    private var order: [NSWindow] = []
    private var released: Set<ObjectIdentifier> = []

    private var foldsIntoTabs: Bool { UserDefaults.standard.bool(forKey: Self.oneWindowKey) }

    /// The open editors, for the Dock-icon bookkeeping in the delegate.
    var windows: [NSWindow] { order }

    /// Called before a window is ordered in, so the policy switch happens first.
    var willShow: (() -> Void)?

    func present(image: CGImage, rect: CaptureRect, lang: AppLanguage) {
        let editor = ScreenshotEditor(base: image, rect: rect)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1180, height: 760),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered, defer: false
        )
        let key = ObjectIdentifier(window)
        editors[key] = editor

        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = false
        window.isReleasedWhenClosed = false
        window.contentMinSize = Self.minimum
        window.collectionBehavior.insert(.fullScreenPrimary)
        window.animationBehavior = .documentWindow
        window.delegate = self
        window.title = editor.fileName
        titleWatchers[key] = editor.$fileName
            .sink { [weak window] name in window?.title = name }

        let host = NSHostingController(
            rootView: ScreenshotEditorView(
                editor: editor,
                lang: lang,
                onClose: { [weak self, weak window] in
                    guard let window else { return }
                    self?.released.insert(ObjectIdentifier(window))
                    window.close()
                }
            )
            .hopLayoutDirection()
        )
        host.sizingOptions = []
        window.contentViewController = host
        window.appearance = NSAppearance(named: Theme.isDark ? .darkAqua : .aqua)

        place(window, shot: rect)
        order.append(window)
        willShow?()
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    private func place(_ window: NSWindow, shot: CaptureRect) {
        window.setContentSize(Self.contentSize(for: shot, on: window.screen))

        guard let host = order.last else {
            window.tabbingMode = .disallowed
            window.titleVisibility = .hidden
            window.center()
            return
        }

        guard foldsIntoTabs else {
            window.tabbingMode = .disallowed
            window.titleVisibility = .hidden
            window.cascadeTopLeft(from: NSPoint(x: host.frame.minX, y: host.frame.maxY))
            return
        }

        window.tabbingMode = .preferred
        window.tabbingIdentifier = Self.tabbingID
        window.titleVisibility = .visible
        host.tabbingMode = .preferred
        host.tabbingIdentifier = Self.tabbingID
        host.titleVisibility = .visible
        host.addTabbedWindow(window, ordered: .above)
    }

    /// The window is the SHAPE of the shot plus the header over it, never
    /// bigger than its own pixels and never bigger than the display. Below the
    /// floor the toolbar would not fit, and there the picture is scaled up
    /// instead.
    private static func contentSize(for shot: CaptureRect, on screen: NSScreen?) -> NSSize {
        let room = (screen ?? NSScreen.main)?.visibleFrame.size
            ?? NSSize(width: 1440, height: 900)
        let fit = min(room.width * 0.92 / max(shot.width, 1),
                      (room.height * 0.92 - headerHeight) / max(shot.height, 1),
                      1)
        return NSSize(width: max(minimum.width, shot.width * fit),
                      height: max(minimum.height, shot.height * fit + headerHeight))
    }

    private static let headerHeight: CGFloat = 47
    /// Lying flat the toolbar is about 660pt wide; the height only has to hold
    /// the picture, and a short window keeps the toolbar off its sides.
    private static let minimum = NSSize(width: 720, height: 380)

    // MARK: - Closing

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        let key = ObjectIdentifier(sender)
        if released.contains(key) { return true }
        guard let editor = editors[key], editor.hasUnsavedMarks else { return true }

        let lang = L10n.current
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = L10n.t(.shotCloseTitle, lang)
        alert.informativeText = L10n.t(.shotCloseBody, lang)
        alert.addButton(withTitle: L10n.t(.shotCloseConfirm, lang))
        alert.addButton(withTitle: L10n.t(.quitCancel, lang))
        return alert.runModal() == .alertFirstButtonReturn
    }

    func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow else { return }
        let key = ObjectIdentifier(window)
        editors[key] = nil
        titleWatchers[key] = nil
        released.remove(key)
        // The window leaves the list a tick later: the app delegate reads it
        // from its own observer of the same notification, to decide whether the
        // Dock icon still has a window behind it.
        DispatchQueue.main.async { [weak self, weak window] in
            guard let window else { return }
            self?.order.removeAll { $0 === window }
        }
    }
}
